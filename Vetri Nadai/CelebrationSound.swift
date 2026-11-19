import AVFoundation

/// Synthesizes firework booms and crackles so no audio file needs to be bundled.
final class CelebrationSound {
    static let shared = CelebrationSound()
    static let mutedKey = "fireworksMuted"

    private let engine = AVAudioEngine()
    // Several players so rapid taps overlap instead of cutting each other off.
    private let players = (0..<6).map { _ in AVAudioPlayerNode() }
    private var nextPlayer = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var showBuffer = makeBuffer(rockets: 5)
    private lazy var singleBuffer = makeBuffer(rockets: 1)

    private init() {
        for player in players {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
    }

    func playShow() { play(showBuffer) }

    func playSingle() { play(singleBuffer) }

    func stopAll() {
        players.forEach { $0.stop() }
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard !UserDefaults.standard.bool(forKey: Self.mutedKey) else { return }
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private func makeBuffer(rockets: Int) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let frameCount = Int(rate * (Firework.riseDuration + Double(rockets - 1) * 0.25 + 1.8))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let samples = buffer.floatChannelData![0]
        samples.update(repeating: 0, count: frameCount)

        func add(_ value: Float, at index: Int) {
            if index >= 0 && index < frameCount { samples[index] += value }
        }

        // Booms line up with the staggered rockets in ContentView.launchFireworks().
        for rocket in 0..<rockets {
            let burstTime = Firework.riseDuration + Double(rocket) * 0.25
            let start = Int(burstTime * rate)

            var lowPassed: Float = 0
            for n in 0..<Int(rate * 0.9) {
                let t = Float(Double(n) / rate)
                let noise = Float.random(in: -1...1)
                lowPassed += 0.04 * (noise - lowPassed)
                let crack = t < 0.02 ? noise * 0.6 : 0
                add((lowPassed * 6 + crack) * exp(-t * 5), at: start + n)
            }

            for _ in 0..<40 {
                let popStart = start + Int(Double.random(in: 0.15...1.6) * rate)
                let loudness = Float.random(in: 0.15...0.45)
                for n in 0..<Int(rate * 0.008) {
                    let t = Float(Double(n) / rate)
                    add(Float.random(in: -1...1) * loudness * exp(-t * 600), at: popStart + n)
                }
            }
        }

        var peak: Float = 0
        for i in 0..<frameCount { peak = max(peak, abs(samples[i])) }
        if peak > 0 {
            let gain = 0.9 / peak
            for i in 0..<frameCount { samples[i] *= gain }
        }
        return buffer
    }
}
