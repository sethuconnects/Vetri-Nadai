import SwiftUI
import Charts

struct SleepView: View {
    let accent: Color
    @StateObject private var tracker = SleepTracker.shared
    @AppStorage(SleepTracker.historyKey) private var historyNights = SleepTracker.defaultHistory
    @State private var selectedNight: SleepTracker.Night?
    @State private var showRatingInfo = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    Label("Sleep", systemImage: "bed.double.fill")
                        .font(.headline)
                    Button { showRatingInfo = true } label: {
                        Image(systemName: "info.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("How sleep is rated")
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                if let last = tracker.nights.first {
                    Button { selectedNight = last } label: { lastNightCard(last) }
                        .buttonStyle(.plain)
                    recentCard
                } else {
                    emptyCard
                }
            }
            .padding()
            // Keeps the last row clear of the page dots when scrolled to the bottom.
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await tracker.refresh()
        }
        .sheet(item: $selectedNight) { night in
            SleepDetailView(night: night)
                .tint(accent)
        }
        .sheet(isPresented: $showRatingInfo) {
            SleepRatingInfoView()
                .tint(accent)
                .presentationDetents([.medium, .large])
        }
    }

    private func lastNightCard(_ night: SleepTracker.Night) -> some View {
        VStack(spacing: 16) {
            Text("Last sleep · \(dayLabel(night.day))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(statusColor(night).opacity(0.2), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: min(1, night.asleep / SleepTracker.goal))
                        .stroke(statusColor(night), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(statusColor(night))
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 4) {
                    Text(durationText(night.asleep))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("asleep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timeRange(night))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    statusBadge(night)
                        .padding(.top, 4)
                }
            }

            HStack {
                Text("Tap for details")
                Image(systemName: "chevron.right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: 440)
        .contentShape(.rect(cornerRadius: 32))
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent nights")
                .font(.headline)
            let recent = Array(tracker.nights.dropFirst().prefix(historyNights))
            if recent.isEmpty {
                Text("No earlier nights recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(recent) { night in
                Button { selectedNight = night } label: {
                    HStack(spacing: 12) {
                        Image(systemName: night.rating.icon)
                            .font(.title3)
                            .foregroundStyle(statusColor(night))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dayLabel(night.day))
                                .font(.headline)
                            Text(timeRange(night))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(durationText(night.asleep))
                                .font(.headline)
                                .fontDesign(.rounded)
                            Text(night.rating.title)
                                .font(.caption.bold())
                                .foregroundStyle(statusColor(night))
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: 440, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 44))
                .foregroundStyle(accent)
            if tracker.hasLoaded {
                Text("No sleep data yet")
                    .font(.title3.bold())
                Text("Wear your Apple Watch to bed, or allow sleep access in Settings › Health › Data Access.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
            }
        }
        .padding(24)
        .frame(maxWidth: 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
    }

    private func statusBadge(_ night: SleepTracker.Night) -> some View {
        Text(night.rating.title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(statusColor(night).opacity(0.2), in: .capsule)
            .foregroundStyle(statusColor(night))
    }

    private func statusColor(_ night: SleepTracker.Night) -> Color {
        night.rating.color
    }
}

extension SleepTracker.Rating {
    var hoursText: String {
        switch self {
        case .veryLow: "Under 6h"
        case .canBeBetter: "6h – 6h 30m"
        case .decent: "6h 30m – 6h 45m"
        case .neat: "6h 45m – 7h"
        case .good: "7h – 7h 30m"
        case .veryGood: "7h 30m – 8h"
        case .great: "8h or more"
        }
    }
    var color: Color {
        switch self {
        case .veryLow: .red
        // Plain yellow is hard to read on the light glass, so darken it slightly.
        case .canBeBetter, .decent: Color.yellow.mix(with: .black, by: 0.2)
        case .neat, .good, .veryGood, .great: .green
        }
    }

    var icon: String {
        switch self {
        case .veryLow: "exclamationmark.circle.fill"
        case .canBeBetter, .decent: "minus.circle.fill"
        case .neat, .good, .veryGood, .great: "checkmark.seal.fill"
        }
    }
}

struct SleepRatingInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                        GridRow {
                            Text("Rating")
                            Text("Time asleep")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        Divider()
                        ForEach(SleepTracker.Rating.allCases.reversed(), id: \.self) { rating in
                            GridRow {
                                Label {
                                    Text(rating.title)
                                        .font(.headline)
                                } icon: {
                                    Image(systemName: rating.icon)
                                        .foregroundStyle(rating.color)
                                }
                                Text(rating.hoursText)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } footer: {
                    Text("Each range includes its lower limit, so exactly 7h is Good. Time asleep counts Core, Deep and REM sleep from Health, not time spent awake in bed. If your watch only covered part of the night, sleep recorded by other sources fills in the rest. The ring fills toward an 8-hour goal.")
                }

                Section("Colours") {
                    colourRow(.green, "Neat to Great: enough sleep")
                    colourRow(SleepTracker.Rating.decent.color, "Can be better or Decent: a little short")
                    colourRow(.red, "Very low: under 6 hours")
                }
            }
            .navigationTitle("How sleep is rated")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func colourRow(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct SleepDetailView: View {
    let night: SleepTracker.Night
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(durationText(night.asleep))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                        Text("asleep · \(timeRange(night))")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Timeline") {
                    timeline
                        .frame(height: 180)
                        .padding(.vertical, 8)
                }

                Section("Stages") {
                    if night.hasStages {
                        stageRow(.deep, night.deep)
                        stageRow(.rem, night.rem)
                        stageRow(.core, night.core)
                        if night.unstaged >= 60 {
                            stageRow(.asleep, night.unstaged)
                            Text("Part of this night has no stage data, for example if your watch's battery ran out.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No stage data for this night. Deep, REM and Core are only recorded when you sleep with an Apple Watch.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    wokeRow
                }
            }
            .navigationTitle(dayLabel(night.day))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var stageOrder: [String] {
        var stages: [SleepTracker.Stage] = night.hasStages ? [.awake, .rem, .core, .deep] : [.awake, .asleep]
        if night.hasStages && night.segments.contains(where: { $0.stage == .asleep }) {
            stages.insert(.asleep, at: 1)
        }
        return stages.map(\.rawValue)
    }

    private var timeline: some View {
        Chart(night.segments) { segment in
            RectangleMark(
                xStart: .value("Start", segment.start),
                xEnd: .value("End", segment.end),
                y: .value("Stage", segment.stage.rawValue)
            )
            .foregroundStyle(segment.stage.color)
            .clipShape(.rect(cornerRadius: 3))
        }
        .chartYScale(domain: stageOrder)
        .chartXScale(domain: night.bedtime...night.wakeTime)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(ContentView.shortTimeFormat))
                    }
                }
            }
        }
    }

    private func stageRow(_ stage: SleepTracker.Stage, _ duration: TimeInterval) -> some View {
        let share = night.asleep > 0 ? duration / night.asleep : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(stage.color)
                    .frame(width: 10, height: 10)
                Text(stage.rawValue)
                    .font(.headline)
                Spacer()
                Text(durationText(duration))
                    .font(.headline)
                    .fontDesign(.rounded)
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            ProgressView(value: share)
                .tint(stage.color)
        }
        .padding(.vertical, 4)
    }

    private var wokeRow: some View {
        HStack {
            Circle()
                .fill(SleepTracker.Stage.awake.color)
                .frame(width: 10, height: 10)
            Text("Woke")
                .font(.headline)
            Spacer()
            Text(night.interruptions == 1 ? "1 time" : "\(night.interruptions) times")
                .font(.headline)
                .fontDesign(.rounded)
            Text(durationText(night.awake))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

extension SleepTracker.Stage {
    var color: Color {
        switch self {
        case .awake: .orange
        case .rem: .cyan
        case .core: .blue
        case .deep: .indigo
        case .asleep: .teal
        }
    }
}

private func durationText(_ interval: TimeInterval) -> String {
    let minutes = Int(interval / 60)
    return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
}

private func timeRange(_ night: SleepTracker.Night) -> String {
    "\(night.bedtime.formatted(ContentView.shortTimeFormat)) – \(night.wakeTime.formatted(ContentView.shortTimeFormat))"
}

private func dayLabel(_ day: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
}
