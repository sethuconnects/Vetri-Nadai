import Foundation
import Combine
import HealthKit

/// Reads sleep stages from Health and groups them into nights.
final class SleepTracker: ObservableObject {
    enum Stage: String, CaseIterable {
        case awake = "Woke"
        case rem = "REM"
        case core = "Core"
        case deep = "Deep"
        case asleep = "Asleep"
    }

    struct Segment: Identifiable {
        let stage: Stage
        let start: Date
        let end: Date
        var id: Date { start }
    }

    struct Night: Identifiable {
        /// Start of the day the sleep ended on (the "morning" of the night).
        let day: Date
        let bedtime: Date
        let wakeTime: Date
        let asleep: TimeInterval
        let deep: TimeInterval
        let rem: TimeInterval
        let core: TimeInterval
        let awake: TimeInterval
        let interruptions: Int
        /// Chronological stages for the timeline, including the awake gaps.
        let segments: [Segment]

        var id: Date { day }
        var rating: Rating { Rating(asleep: asleep) }
        var hasStages: Bool { deep + rem + core > 0 }
        /// Time asleep without stage data, e.g. after the watch's battery ran out.
        var unstaged: TimeInterval { max(0, asleep - deep - rem - core) }
    }

    /// Sleep quality by time asleep; each band includes its lower bound.
    enum Rating: CaseIterable {
        case veryLow, canBeBetter, decent, neat, good, veryGood, great

        init(asleep: TimeInterval) {
            switch asleep / 60 {
            case ..<360: self = .veryLow
            case ..<390: self = .canBeBetter
            case ..<405: self = .decent
            case ..<420: self = .neat
            case ..<450: self = .good
            case ..<480: self = .veryGood
            default: self = .great
            }
        }

        var title: String {
            switch self {
            case .veryLow: "Very low"
            case .canBeBetter: "Can be better"
            case .decent: "Decent"
            case .neat: "Neat"
            case .good: "Good"
            case .veryGood: "Very good"
            case .great: "Great!"
            }
        }
    }

    static let shared = SleepTracker()
    static let goal: TimeInterval = 8 * 3600
    static let historyKey = "sleepHistoryNights"
    static let defaultHistory = 7
    static let historyRange = 1...14

    /// Newest first.
    @Published private(set) var nights: [Night] = []
    @Published private(set) var hasLoaded = false

    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)

    private init() {}

    func refresh() async {
        #if DEBUG
        if DemoData.isEnabled {
            nights = DemoData.nights
            hasLoaded = true
            return
        }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else {
            hasLoaded = true
            return
        }
        do {
            try await HealthAuthorization.requestReadAccess(to: [sleepType])
            let calendar = Calendar.current
            // Always fetch the largest history (plus last night) so changing the setting is instant.
            let start = calendar.date(byAdding: .day, value: -(Self.historyRange.upperBound + 2), to: calendar.startOfDay(for: .now))!
            let query = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: sleepType, predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            let samples = try await query.result(for: store)
            // Shifting by 6h assigns anything that starts after 6 PM to the next morning.
            nights = Dictionary(grouping: samples) {
                calendar.startOfDay(for: $0.startDate.addingTimeInterval(6 * 3600))
            }
            .compactMap { Self.night(day: $0.key, samples: $0.value) }
            .sorted { $0.day > $1.day }
        } catch {
            nights = []
        }
        hasLoaded = true
    }

    typealias Period = (stage: Stage, interval: DateInterval)

    private static func night(day: Date, samples: [HKCategorySample]) -> Night? {
        night(day: day, periods: samples.compactMap { sample in
            HKCategoryValueSleepAnalysis(rawValue: sample.value)
                .flatMap(Stage.init(sleepValue:))
                .map { ($0, DateInterval(start: sample.startDate, end: sample.endDate)) }
        })
    }

    /// Builds a night from raw asleep periods, which may overlap and come from several sources.
    static func night(day: Date, periods: [Period]) -> Night? {
        let staged = periods.filter { $0.stage != .asleep }
        var usable = periods
        // Generic "asleep" samples (e.g. from iPhone) only fill time before or after the staged
        // recording, such as when the watch ran out of battery. Inside it, gaps are real wake-ups.
        if let stagedStart = staged.map(\.interval.start).min(),
           let stagedEnd = staged.map(\.interval.end).max() {
            usable = staged
            for period in periods where period.stage == .asleep {
                if period.interval.start < stagedStart {
                    usable.append((.asleep, DateInterval(start: period.interval.start, end: min(period.interval.end, stagedStart))))
                }
                if period.interval.end > stagedEnd {
                    usable.append((.asleep, DateInterval(start: max(period.interval.start, stagedEnd), end: period.interval.end)))
                }
            }
        }

        let asleepSegments = resolve(usable)
        guard let first = asleepSegments.first, let last = asleepSegments.last else { return nil }

        // Gaps between asleep periods are times you woke up; ignore sub-minute blips.
        let gaps = zip(asleepSegments, asleepSegments.dropFirst())
            .map { DateInterval(start: $0.end, end: $1.start) }
            .filter { $0.duration >= 60 }

        func total(_ stage: Stage) -> TimeInterval {
            asleepSegments.filter { $0.stage == stage }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        }

        return Night(
            day: day,
            bedtime: first.start,
            wakeTime: last.end,
            asleep: asleepSegments.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) },
            deep: total(.deep),
            rem: total(.rem),
            core: total(.core),
            awake: gaps.reduce(0) { $0 + $1.duration },
            interruptions: gaps.count,
            segments: (asleepSegments + gaps.map { Segment(stage: .awake, start: $0.start, end: $0.end) })
                .sorted { $0.start < $1.start }
        )
    }

    /// When periods overlap, the moment goes to the first stage in this list so it's only counted once.
    private static let priority: [Stage] = [.deep, .rem, .core, .asleep]

    /// Flattens overlapping periods into non-overlapping, chronological segments.
    private static func resolve(_ periods: [Period]) -> [Segment] {
        let bounds = Set(periods.flatMap { [$0.interval.start, $0.interval.end] }).sorted()
        var segments: [Segment] = []
        for (start, end) in zip(bounds, bounds.dropFirst()) {
            let covering = Set(periods.filter { $0.interval.start <= start && $0.interval.end >= end }.map(\.stage))
            guard let stage = priority.first(where: covering.contains) else { continue }
            if let previous = segments.last, previous.stage == stage, previous.end == start {
                segments[segments.count - 1] = Segment(stage: stage, start: previous.start, end: end)
            } else {
                segments.append(Segment(stage: stage, start: start, end: end))
            }
        }
        return segments
    }
}

private extension SleepTracker.Stage {
    init?(sleepValue: HKCategoryValueSleepAnalysis) {
        switch sleepValue {
        case .asleepDeep: self = .deep
        case .asleepREM: self = .rem
        case .asleepCore: self = .core
        case .asleepUnspecified: self = .asleep
        default: return nil
        }
    }
}
