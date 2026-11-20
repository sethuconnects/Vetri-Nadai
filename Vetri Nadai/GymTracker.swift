import Foundation
import Combine
import HealthKit

/// Counts gym days per month, treating indoor walks, strength training and elliptical workouts as gym visits.
final class GymTracker: ObservableObject {
    struct Session: Identifiable {
        let id: UUID
        let name: String
        let start: Date
        let duration: TimeInterval
        let energyKcal: Double?
    }

    struct Day: Identifiable {
        let day: Date
        /// Oldest first, in the order they were done.
        let sessions: [Session]
        var id: Date { day }
    }

    static let shared = GymTracker()
    static let monthsToShow = 12

    /// Newest first.
    @Published private(set) var days: [Day] = []
    @Published private(set) var loadedMonth: Date?

    private let store = HKHealthStore()
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private var requestedMonth: Date?

    private init() {}

    static func isGymWorkout(_ workout: HKWorkout) -> Bool {
        switch workout.workoutActivityType {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .elliptical:
            return true
        case .walking:
            return workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool == true
        default:
            return false
        }
    }

    func load(month: Date) async {
        requestedMonth = month
        #if DEBUG
        if DemoData.isEnabled {
            days = DemoData.gymDays(for: month)
            loadedMonth = month
            return
        }
        #endif
        let calendar = Calendar.current
        guard HKHealthStore.isHealthDataAvailable(),
              let interval = calendar.dateInterval(of: .month, for: month) else {
            days = []
            loadedMonth = month
            return
        }
        var result: [Day] = []
        do {
            try await HealthAuthorization.requestReadAccess(to: [HKObjectType.workoutType(), energyType])
            let query = HKSampleQueryDescriptor(
                predicates: [.workout(HKQuery.predicateForSamples(withStart: interval.start, end: interval.end))],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            let sessions = try await query.result(for: store)
                .filter(Self.isGymWorkout)
                .map { workout in
                    Session(
                        id: workout.uuid,
                        name: workout.workoutActivityType.displayName(
                            isIndoor: workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool
                        ),
                        start: workout.startDate,
                        duration: workout.duration,
                        energyKcal: workout.statistics(for: energyType)?.sumQuantity()?
                            .doubleValue(for: .kilocalorie()).nonZero
                    )
                }
            result = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.start) }
                .map { Day(day: $0.key, sessions: $0.value) }
                .sorted { $0.day > $1.day }
        } catch {
            result = []
        }
        // Ignore a slow load if another month was picked in the meantime.
        guard requestedMonth == month else { return }
        days = result
        loadedMonth = month
    }

    /// Start of the current month followed by the previous months, newest first.
    static func recentMonths(now: Date = .now) -> [Date] {
        let calendar = Calendar.current
        let current = calendar.dateInterval(of: .month, for: now)!.start
        return (0..<monthsToShow).compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
    }
}

private extension Double {
    var nonZero: Double? { self > 0 ? self : nil }
}
