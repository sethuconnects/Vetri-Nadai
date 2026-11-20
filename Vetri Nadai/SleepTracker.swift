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
            try await store.requestAuthorization(toShare: [], read: [sleepType])
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

    private static func night(day: Date, samples: [HKCategorySample]) -> Night? {
        func stage(_ sample: HKCategorySample) -> HKCategoryValueSleepAnalysis? {
            HKCategoryValueSleepAnalysis(rawValue: sample.value)
        }
        func intervals(_ values: Set<HKCategoryValueSleepAnalysis>) -> [DateInterval] {
            merged(samples
                .filter { stage($0).map(values.contains) ?? false }
                .map { DateInterval(start: $0.startDate, end: $0.endDate) })
        }
        func total(_ intervals: [DateInterval]) -> TimeInterval {
            intervals.reduce(0) { $0 + $1.duration }
        }

        // When a watch recorded stages, ignore the cruder "asleep" samples from other sources.
        let staged: Set<HKCategoryValueSleepAnalysis> = [.asleepCore, .asleepDeep, .asleepREM]
        let hasStages = samples.contains { stage($0).map(staged.contains) ?? false }
        let asleepIntervals = intervals(hasStages ? staged : HKCategoryValueSleepAnalysis.allAsleepValues)
        guard let first = asleepIntervals.first, let last = asleepIntervals.last else { return nil }

        // Gaps between asleep periods are times you woke up; ignore sub-minute blips.
        let gaps = zip(asleepIntervals, asleepIntervals.dropFirst())
            .map { DateInterval(start: $0.end, end: $1.start) }
            .filter { $0.duration >= 60 }

        let deep = intervals([.asleepDeep])
        let rem = intervals([.asleepREM])
        let core = intervals([.asleepCore])
        var segments = gaps.map { Segment(stage: .awake, start: $0.start, end: $0.end) }
        if hasStages {
            segments += deep.map { Segment(stage: .deep, start: $0.start, end: $0.end) }
            segments += rem.map { Segment(stage: .rem, start: $0.start, end: $0.end) }
            segments += core.map { Segment(stage: .core, start: $0.start, end: $0.end) }
        } else {
            segments += asleepIntervals.map { Segment(stage: .asleep, start: $0.start, end: $0.end) }
        }

        return Night(
            day: day,
            bedtime: first.start,
            wakeTime: last.end,
            asleep: total(asleepIntervals),
            deep: total(deep),
            rem: total(rem),
            core: total(core),
            awake: total(gaps),
            interruptions: gaps.count,
            segments: segments.sorted { $0.start < $1.start }
        )
    }
}

private func merged(_ intervals: [DateInterval]) -> [DateInterval] {
    var result: [DateInterval] = []
    for interval in intervals.sorted(by: { $0.start < $1.start }) {
        if let last = result.last, interval.start <= last.end {
            result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
        } else {
            result.append(interval)
        }
    }
    return result
}
