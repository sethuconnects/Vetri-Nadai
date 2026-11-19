import SwiftUI
import Combine
import AVFoundation

/// Tracks continuous foreground use and locks the app behind a scary screen once the limit is hit.
@MainActor
final class UsageLimit: ObservableObject {
    static let shared = UsageLimit()

    static let minutesKey = "usageLimitMinutes"
    static let defaultMinutes = 15
    static let range = 0...120
    private static let lockedKey = "usageLimitLocked"
    private static let sessionStartKey = "usageLimitSessionStart"
    private static let lastActiveKey = "usageLimitLastActive"
    /// Leaving the app for at least this long counts as a real break and restarts the clock.
    static let breakDuration: TimeInterval = 5 * 60

    @Published private(set) var isLocked = UserDefaults.standard.bool(forKey: UsageLimit.lockedKey)
    private let defaults = UserDefaults.standard
    private var timer: Timer?

    private init() {}

    private var limitMinutes: Int {
        defaults.object(forKey: Self.minutesKey) as? Int ?? Self.defaultMinutes
    }

    func becameActive() {
        let now = Date()
        let lastActive = defaults.object(forKey: Self.lastActiveKey) as? Date
        if defaults.object(forKey: Self.sessionStartKey) == nil
            || lastActive.map({ now.timeIntervalSince($0) >= Self.breakDuration }) ?? true {
            defaults.set(now, forKey: Self.sessionStartKey)
        }
        defaults.set(now, forKey: Self.lastActiveKey)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in UsageLimit.shared.check() }
        }
        check()
    }

    func becameInactive() {
        // Launch reports an inactive phase before the first active one; recording that would hide the break.
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        defaults.set(Date(), forKey: Self.lastActiveKey)
        DevilSound.shared.stop()
    }

    func check() {
        defaults.set(Date(), forKey: Self.lastActiveKey)
        if isLocked {
            DevilSound.shared.start()
            return
        }
        let limit = limitMinutes
        guard limit > 0, let start = defaults.object(forKey: Self.sessionStartKey) as? Date else { return }
        if Date().timeIntervalSince(start) >= Double(limit) * 60 {
            isLocked = true
            defaults.set(true, forKey: Self.lockedKey)
            DevilSound.shared.start()
        }
    }

    /// Parent-only escape hatch: clears the lock and restarts the usage clock.
    func unlock() {
        isLocked = false
        defaults.set(false, forKey: Self.lockedKey)
        defaults.set(Date(), forKey: Self.sessionStartKey)
        DevilSound.shared.stop()
    }
}

struct ScaryLockView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("ScaryImage")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        }
        // Hidden parent unlock: press and hold anywhere for 5 seconds.
        .contentShape(.rect)
        .onLongPressGesture(minimumDuration: 5) { UsageLimit.shared.unlock() }
        .accessibilityHidden(true)
    }
}

/// Synthesizes a looping, low demonic growl with an evil laugh so no audio file needs bundling.
final class DevilSound {
    static let shared = DevilSound()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var buffer = makeBuffer()

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() {
        guard !player.isPlaying else { return }
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
    }

    func stop() {
        player.stop()
    }

    private func makeBuffer() -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let duration = 6.0
        let frameCount = Int(rate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let samples = buffer.floatChannelData![0]
        let twoPi = Float.pi * 2

        var growlPhase: Float = 0
        var laughPhase: Float = 0
        var rumble: Float = 0
        for n in 0..<frameCount {
            let t = Float(Double(n) / rate)

            // Deep growl: slowly sliding pitch, rough amplitude wobble, odd harmonics for grit.
            let growlFreq = 55 + 15 * sin(twoPi * 0.17 * t) + 6 * sin(twoPi * 7 * t)
            growlPhase += twoPi * growlFreq / Float(rate)
            let raw = sin(growlPhase) + 0.6 * sin(3 * growlPhase) + 0.4 * sin(5 * growlPhase)
            let growl = tanh(raw * 2.5) * (0.6 + 0.4 * sin(twoPi * 0.5 * t))

            rumble += 0.01 * (Float.random(in: -1...1) - rumble)

            // "Ha-ha-ha" laugh bursts in the second half of the loop, pitched low and descending.
            var laugh: Float = 0
            if t > 3.0 && t < 5.4 {
                let lt = t - 3.0
                let syllable = lt.truncatingRemainder(dividingBy: 0.3)
                let envelope = syllable < 0.2 ? sin(Float.pi * syllable / 0.2) : 0
                let laughFreq = 180 - 40 * lt
                laughPhase += twoPi * laughFreq / Float(rate)
                let voice = sin(laughPhase) + 0.5 * sin(2 * laughPhase) + 0.3 * sin(3 * laughPhase)
                laugh = tanh(voice * 2) * envelope * 0.8
            }

            // Short fades at the loop edges avoid an audible click on repeat.
            let edge = min(t, Float(duration) - t)
            let fade = min(1, edge / 0.05)
            samples[n] = (growl * 0.5 + rumble * 8 + laugh) * fade
        }

        var peak: Float = 0
        for i in 0..<frameCount { peak = max(peak, abs(samples[i])) }
        if peak > 0 {
            let gain = 0.95 / peak
            for i in 0..<frameCount { samples[i] *= gain }
        }
        return buffer
    }
}
