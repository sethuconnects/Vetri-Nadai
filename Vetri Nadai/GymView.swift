import SwiftUI

struct GymView: View {
    let accent: Color
    @StateObject private var tracker = GymTracker.shared
    @State private var month = GymTracker.recentMonths().first!
    @Environment(\.scenePhase) private var scenePhase

    private static let months = GymTracker.recentMonths()

    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30
    }

    private var isLoaded: Bool { tracker.loadedMonth == month }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                summaryCard
                if isLoaded {
                    if tracker.days.isEmpty {
                        emptyCard
                    } else {
                        ForEach(tracker.days) { dayCard($0) }
                    }
                }
            }
            .padding()
            // Keeps the last card clear of the page dots when scrolled to the bottom.
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .task(id: TaskKey(month: month, phase: scenePhase)) {
            guard scenePhase == .active else { return }
            await tracker.load(month: month)
        }
    }

    private struct TaskKey: Equatable {
        let month: Date
        let phase: ScenePhase
    }

    private var header: some View {
        HStack(spacing: 14) {
            Label("Gym", systemImage: "dumbbell.fill")
                .font(.headline)
            Picker("Month", selection: $month) {
                ForEach(Self.months, id: \.self) { month in
                    Text(month.formatted(.dateTime.month(.wide).year())).tag(month)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }

    private var summaryCard: some View {
        let gymDays = isLoaded ? tracker.days.count : 0
        return VStack(spacing: 12) {
            Text("Days in the gym · \(month.formatted(.dateTime.month(.wide)))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if isLoaded {
                    Text("\(gymDays)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .contentTransition(.numericText())
                } else {
                    ProgressView()
                }
                Text("/\(daysInMonth) days")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(gymDays), total: Double(daysInMonth))
                .tint(accent)
                .animation(.easeInOut, value: gymDays)
        }
        .padding(24)
        .frame(maxWidth: 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell")
                .font(.system(size: 40))
                .foregroundStyle(accent)
            Text("No gym workouts in \(month.formatted(.dateTime.month(.wide)))")
                .font(.headline)
            Text("Indoor walks, strength training and elliptical workouts from Health count as gym days.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
    }

    private func dayCard(_ day: GymTracker.Day) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(dayLabel(day.day))
                .font(.headline)
            ForEach(day.sessions) { session in
                HStack(spacing: 12) {
                    Image(systemName: icon(for: session.name))
                        .font(.title3)
                        .foregroundStyle(accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .font(.subheadline.weight(.semibold))
                        Text(session.start.formatted(ContentView.shortTimeFormat))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Duration.seconds(session.duration)
                            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(.rounded)
                        if let kcal = session.energyKcal {
                            Text("\(Int(kcal.rounded()).formatted()) kcal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 440, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func icon(for name: String) -> String {
        switch name {
        case "Indoor Walk": "figure.walk"
        case "Elliptical": "figure.elliptical"
        default: "dumbbell.fill"
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        let date = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        if calendar.isDateInToday(day) { return "Today · \(date)" }
        if calendar.isDateInYesterday(day) { return "Yesterday · \(date)" }
        return date
    }
}
