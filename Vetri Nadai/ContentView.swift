import SwiftUI
import Playgrounds

struct ContentView: View {
    @AppStorage("userName") private var userName = ContentView.systemUserName
    @State private var nameInput = ""
    @State private var fireworks: [Firework] = []
    @StateObject private var stepCounter = StepCounter.shared
    @StateObject private var usageLimit = UsageLimit.shared
    @State private var isRefreshing = false
    @State private var showSettings = ContentView.demoShowSettings
    @State private var page = ContentView.demoPage
    @AppStorage(StepCounter.monthlyTargetKey) private var monthlyTarget = StepCounter.defaultTarget
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage(CelebrationSound.mutedKey) private var isMuted = false
    @AppStorage("accentHex") private var accentHex = "#0A84FF"
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.self) private var environment

    private static let presets = ["#0A84FF", "#BF5AF2", "#FF375F", "#FF9F0A", "#30D158"]

    private var accent: Color { Color(hex: accentHex) }

    private var accentBinding: Binding<Color> {
        Binding(get: { accent }, set: { accentHex = $0.hex(in: environment) })
    }

    // iOS doesn't expose the owner's name to apps, so only macOS can prefill it.
    private static var systemUserName: String {
        #if os(macOS)
        return NSFullUserName()
        #else
        return ""
        #endif
    }

    private static var demoPage: Int {
        #if DEBUG
        return DemoData.page
        #else
        return 0
        #endif
    }

    private static var demoShowSettings: Bool {
        #if DEBUG
        return DemoData.showSettings
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack {
            LiquidBackground(accent: accent, isDark: isDarkMode)

            TabView(selection: $page) {
                Tab("Home", systemImage: "figure.walk", value: 0) { mainPage }
                Tab("Gym", systemImage: "dumbbell.fill", value: 1) { GymView(accent: accent) }
                Tab("Sleep", systemImage: "bed.double.fill", value: 2) { SleepView(accent: accent) }
            }
            .swipeablePages()

            FireworksView(fireworks: fireworks)
                .allowsHitTesting(false)

            if usageLimit.isLocked {
                ScaryLockView()
                    .transition(.opacity)
            }
        }
        .animation(.easeIn(duration: 0.3), value: usageLimit.isLocked)
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active {
                usageLimit.becameActive()
            } else {
                usageLimit.becameInactive()
            }
        }
        .onChange(of: usageLimit.isLocked) {
            if usageLimit.isLocked { showSettings = false }
        }
        .tint(accent)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .sheet(isPresented: $showSettings) {
            SettingsView(onChange: refreshSteps)
                .tint(accent)
        }
    }

    private var mainPage: some View {
        ZStack {
            // Stands in for the background so taps on empty space still launch fireworks.
            Color.clear
                .contentShape(.rect)
                .simultaneousGesture(fireworkTap)

            VStack(spacing: 16) {
                controlsBar
                Spacer(minLength: 0)
                Group {
                    if userName.isEmpty {
                        nameEntryView
                    } else {
                        greetingView
                    }
                }
                .padding(24)
                .frame(maxWidth: 440)
                .contentShape(.rect(cornerRadius: 32))
                .glassEffect(.regular, in: .rect(cornerRadius: 32))
                .simultaneousGesture(fireworkTap)
                Spacer(minLength: 0)
            }
            .padding()
            .padding(.bottom, 24)
        }
    }

    private var fireworkTap: some Gesture {
        SpatialTapGesture(coordinateSpace: .global).onEnded { launchFirework(at: $0.location) }
    }

    private var controlsBar: some View {
        HStack(spacing: 8) {
            Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                .foregroundStyle(accent)
                .frame(width: 20)
            Toggle("Dark mode", isOn: $isDarkMode)
                .labelsHidden()
            Spacer(minLength: 4)
            ForEach(Self.presets, id: \.self) { hex in
                Button { accentHex = hex } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: accentHex == hex ? 2 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(hex)")
            }
            ColorPicker("Custom color", selection: accentBinding, supportsOpacity: false)
                .labelsHidden()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }

    private var nameEntryView: some View {
        VStack(spacing: 16) {
            Text("What's your name?")
                .font(.title)
            TextField("Your name", text: $nameInput)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .onSubmit(saveName)
            Button("Continue", action: saveName)
                .buttonStyle(.borderedProminent)
                .disabled(nameInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func saveName() {
        let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { userName = trimmed }
    }

    private var targetReached: Bool { stepCounter.stepsToTarget == 0 }

    private var muteButton: some View {
        Button {
            isMuted.toggle()
            if isMuted { CelebrationSound.shared.stopAll() }
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.body.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 20, height: 20)
                .padding(8)
                .background(accent.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .accessibilityLabel(isMuted ? "Unmute fireworks" : "Mute fireworks")
    }

    private var refreshButton: some View {
        Button(action: refreshSteps) {
            Image(systemName: "arrow.clockwise")
                .font(.body.weight(.semibold))
                .frame(width: 20, height: 20)
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(
                    isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                    value: isRefreshing
                )
                .padding(8)
                .background(accent.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .disabled(isRefreshing)
        .accessibilityLabel("Refresh steps")
    }

    private func statRow(_ icon: String, _ title: String, _ value: String, valueColor: Color? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(valueColor ?? Color.primary)
            }
            Spacer(minLength: 0)
        }
    }

    // Verbatim styles force a 12-hour clock even if the phone is set to 24-hour time.
    private static let clockFormat = Date.VerbatimFormatStyle(
        format: "\(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits):\(second: .twoDigits) \(dayPeriod: .standard(.abbreviated))",
        locale: Locale(identifier: "en_US_POSIX"), timeZone: .current, calendar: .current
    )
    static let shortTimeFormat = Date.VerbatimFormatStyle(
        format: "\(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(dayPeriod: .standard(.abbreviated))",
        locale: Locale(identifier: "en_US_POSIX"), timeZone: .current, calendar: .current
    )
    private static let dayMonthFormat = Date.VerbatimFormatStyle(
        format: "\(day: .defaultDigits) \(month: .abbreviated)",
        locale: Locale(identifier: "en_US_POSIX"), timeZone: .current, calendar: .current
    )

    private func workoutWhen(_ date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(date) ? "Today"
            : calendar.isDateInYesterday(date) ? "Yesterday"
            : date.formatted(Self.dayMonthFormat)
        return "\(day), \(date.formatted(Self.shortTimeFormat))"
    }

    private func workoutSummary(_ workout: StepCounter.WorkoutSummary) -> String {
        let minutes = Duration.seconds(workout.duration)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        var summary = "\(workout.name) – \(minutes)"
        if let meters = workout.distanceMeters {
            let distance = meters < 1000
                ? "\(Int(meters)) m"
                : Measurement(value: meters / 1000, unit: UnitLength.kilometers)
                    .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...2))))
            summary += " – \(distance)"
            if workout.steps > 0 {
                summary += " / \(workout.steps.formatted()) steps"
            }
        }
        if let kcal = workout.energyKcal {
            summary += " – \(Int(kcal.rounded()).formatted()) kcal"
        }
        return summary
    }

    private func refreshSteps() {
        Task {
            isRefreshing = true
            await stepCounter.refresh()
            isRefreshing = false
        }
    }

    private func launchFireworks() {
        let now = Date()
        fireworks.removeAll { now.timeIntervalSince($0.start) > Firework.lifetime }
        for i in 0..<5 {
            fireworks.append(Firework(start: now.addingTimeInterval(Double(i) * 0.25)))
        }
        if targetReached { CelebrationSound.shared.playShow() }
    }

    private func launchFirework(at point: CGPoint) {
        let now = Date()
        fireworks.removeAll { now.timeIntervalSince($0.start) > Firework.lifetime }
        fireworks.append(Firework(start: now, target: point))
        if targetReached { CelebrationSound.shared.playSingle() }
    }

    private var greetingView: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("Welcome back")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("Hi \(userName)!")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accent, accent.mix(with: .pink, by: 0.4)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .onTapGesture(perform: launchFireworks)
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.headline)
                    Text(context.date, format: Self.clockFormat)
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                Divider()

                VStack(spacing: 14) {
                    HStack {
                        Text("Activity")
                            .font(.headline)
                        Spacer()
                        muteButton
                        refreshButton
                    }
                    statRow("figure.walk", "Today", stepCounter.steps.map { "\($0.formatted()) steps" } ?? "Unavailable")
                    statRow("clock.arrow.circlepath", "Yesterday", stepCounter.yesterdaySteps.map { "\($0.formatted()) steps" } ?? "—")
                    statRow(
                        "chart.bar.fill",
                        "\(context.date.formatted(.dateTime.month(.abbreviated))) average",
                        stepCounter.monthAverage.map { "\($0.formatted()) steps/day" } ?? "—"
                    )
                    if let remaining = stepCounter.stepsToTarget {
                        statRow(
                            remaining > 0 ? "target" : "checkmark.seal.fill",
                            "\(monthlyTarget.formatted(.number.notation(.compactName))) monthly average",
                            remaining > 0 ? "\(remaining.formatted()) more steps today" : "Reached!",
                            valueColor: remaining > 0 ? nil : .green
                        )
                    }
                    if !stepCounter.recentWorkouts.isEmpty {
                        PagedCarousel(items: stepCounter.recentWorkouts, accent: accent) { workout, index in
                            statRow(
                                "figure.run",
                                "\(index == 0 ? "Last workout" : "Earlier workout") · \(workoutWhen(workout.date))",
                                workoutSummary(workout)
                            )
                        }
                    }
                }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await stepCounter.refresh()
            if stepCounter.stepsToTarget == 0 {
                launchFireworks()
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await stepCounter.refresh()
            }
        }
    }
}

/// Swipeable one-item-per-page row with dot indicators.
struct PagedCarousel<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let accent: Color
    @ViewBuilder let content: (Item, Int) -> Content
    @State private var currentID: Item.ID?

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        content(item, index)
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $currentID)

            if items.count > 1 {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        Circle()
                            .fill(item.id == (currentID ?? items.first?.id) ? accent : Color.secondary.opacity(0.35))
                            .frame(width: 7, height: 7)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: currentID)
                .accessibilityHidden(true)
            }
        }
    }
}

private extension View {
    /// Swipe between pages with dots on iOS; macOS has no page style, so it falls back to regular tabs.
    @ViewBuilder func swipeablePages() -> some View {
        #if os(macOS)
        self
        #else
        self
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        #endif
    }
}

struct LiquidBackground: View {
    let accent: Color
    let isDark: Bool

    var body: some View {
        let blobColors = [
            accent,
            accent.mix(with: .indigo, by: 0.45),
            accent.mix(with: .cyan, by: 0.45),
            accent.mix(with: .pink, by: 0.35),
        ]
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(isDark ? Color(white: 0.05) : Color(white: 0.97)))

                ctx.addFilter(.blur(radius: 90))
                let radius = max(size.width, size.height) * 0.32
                for (i, color) in blobColors.enumerated() {
                    let phase = Double(i) * 1.7
                    let speed = 0.08 + Double(i) * 0.03
                    let center = CGPoint(
                        x: size.width * (0.5 + 0.4 * sin(t * speed + phase)),
                        y: size.height * (0.5 + 0.4 * cos(t * speed * 1.3 + phase * 1.7)))
                    let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    ctx.fill(Path(ellipseIn: circle), with: .color(color.opacity(isDark ? 0.55 : 0.4)))
                }
            }
        }
        .contentShape(Rectangle())
        .ignoresSafeArea()
    }
}

struct Firework: Identifiable {
    static let riseDuration = 0.9
    static let burstDuration = 1.8
    static let lifetime = riseDuration + burstDuration
    static let palette: [Color] = [.orange, .yellow, .pink, .red, .purple, .blue, .green]

    let id = UUID()
    let start: Date
    // Burst point in screen coordinates; random position when nil.
    var target: CGPoint? = nil
    let x = CGFloat.random(in: 0.15...0.85)
    let peak = CGFloat.random(in: 0.12...0.4)
    let color = Firework.palette.randomElement()!
    let sparks: [(angle: Double, speed: Double)] = (0..<60).map { _ in
        (Double.random(in: 0..<(2 * .pi)), Double.random(in: 60...180))
    }
}

struct FireworksView: View {
    let fireworks: [Firework]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(paused: fireworks.isEmpty)) { context in
            Canvas { ctx, size in
                // Additive glow only reads well on dark backgrounds.
                ctx.blendMode = colorScheme == .dark ? .plusLighter : .normal
                ctx.addFilter(.shadow(color: colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.2), radius: 4))
                for firework in fireworks {
                    draw(firework, at: context.date, in: &ctx, size: size)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func draw(_ fw: Firework, at date: Date, in ctx: inout GraphicsContext, size: CGSize) {
        let t = date.timeIntervalSince(fw.start)
        guard t >= 0, t < Firework.lifetime else { return }

        let burstX = fw.target?.x ?? fw.x * size.width
        let burstY = fw.target?.y ?? fw.peak * size.height

        if t < Firework.riseDuration {
            let p = t / Firework.riseDuration
            let eased = 1 - (1 - p) * (1 - p)
            let headY = size.height + (burstY - size.height) * eased
            var trail = Path()
            trail.move(to: CGPoint(x: burstX, y: headY))
            trail.addLine(to: CGPoint(x: burstX, y: min(size.height, headY + 40)))
            ctx.stroke(trail, with: .color(.orange.opacity(0.7)), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: burstX - 3, y: headY - 3, width: 6, height: 6)), with: .color(.yellow))
            return
        }

        let e = t - Firework.riseDuration
        let fade = 1 - e / Firework.burstDuration

        if e < 0.15 {
            let r = 24 * (1 - e / 0.15)
            ctx.fill(Path(ellipseIn: CGRect(x: burstX - r, y: burstY - r, width: r * 2, height: r * 2)), with: .color(.white))
        }

        // Drag slows sparks over time while gravity pulls them down.
        let drag = 1.5
        let gravity = 90.0
        let travel = (1 - exp(-drag * e)) / drag
        let sparkRadius = 0.5 + 2.5 * fade
        for spark in fw.sparks {
            let x = burstX + cos(spark.angle) * spark.speed * travel
            let y = burstY + sin(spark.angle) * spark.speed * travel + 0.5 * gravity * e * e
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - sparkRadius, y: y - sparkRadius, width: sparkRadius * 2, height: sparkRadius * 2)),
                with: .color(fw.color.opacity(fade)))
        }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x0A84FF
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    func hex(in environment: EnvironmentValues) -> String {
        let resolved = resolve(in: environment)
        func byte(_ component: Float) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(resolved.red), byte(resolved.green), byte(resolved.blue))
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
