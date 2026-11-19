import Foundation
import Combine
import HealthKit

final class StepCounter: ObservableObject {
    struct WorkoutSummary: Identifiable {
        let id: UUID
        let name: String
        let date: Date
        let duration: TimeInterval
        let distanceMeters: Double?
        let steps: Int
        let energyKcal: Double?
    }

    static let recentWorkoutsKey = "recentWorkoutCount"
    static let defaultRecentWorkouts = 10
    static let recentWorkoutsRange = 1...20
    private static var recentWorkoutLimit: Int {
        let stored = UserDefaults.standard.object(forKey: recentWorkoutsKey) as? Int ?? defaultRecentWorkouts
        return min(max(stored, recentWorkoutsRange.lowerBound), recentWorkoutsRange.upperBound)
    }

    @Published private(set) var steps: Int?
    @Published private(set) var yesterdaySteps: Int?
    @Published private(set) var monthAverage: Int?
    @Published private(set) var stepsToTarget: Int?
    /// Newest first, up to `recentWorkoutLimit`.
    @Published private(set) var recentWorkouts: [WorkoutSummary] = []
    static let targetKey = "dailyStepTarget"
    static let monthlyTargetKey = "monthlyAverageTarget"
    static let defaultTarget = 10_000
    static var dailyTarget: Int { storedTarget(targetKey) }
    static var monthlyTarget: Int { storedTarget(monthlyTargetKey) }
    static let shared = StepCounter()
    private let store = HKHealthStore()
    private var observerQuery: HKObserverQuery?
    private let stepType = HKQuantityType(.stepCount)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let distanceTypes = [
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling),
        HKQuantityType(.distanceSwimming),
    ]

    func refresh() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let calendar = Calendar.current
        let now = Date.now
        let readTypes: Set<HKObjectType> = Set([stepType, energyType, HKObjectType.workoutType()] + distanceTypes)
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            let startOfToday = calendar.startOfDay(for: now)
            steps = Int(try await totalSteps(from: startOfToday))

            let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
            yesterdaySteps = Int(try await totalSteps(from: startOfYesterday, to: startOfToday))

            let startOfMonth = calendar.dateInterval(of: .month, for: now)!.start
            let daysSoFar = Double(calendar.component(.day, from: now))
            let monthTotal = try await totalSteps(from: startOfMonth)
            let average = monthTotal / daysSoFar
            monthAverage = Int(average)
            stepsToTarget = max(0, Int(((Double(Self.monthlyTarget) - average) * daysSoFar).rounded(.up)))

            await StepReminders.shared.reschedule(
                todaySteps: steps ?? 0,
                monthSteps: Int(monthTotal),
                daysSoFar: Int(daysSoFar)
            )
        } catch {
            steps = nil
            yesterdaySteps = nil
            monthAverage = nil
            stepsToTarget = nil
        }
        recentWorkouts = (try? await fetchRecentWorkouts()) ?? []
    }

    /// Wakes the app (at most hourly) when new steps are recorded so reminder numbers stay fresh.
    /// Must be called at launch for background delivery to work.
    func startBackgroundUpdates() {
        guard HKHealthStore.isHealthDataAvailable(), observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { @Sendable _, completionHandler, error in
            guard error == nil else { return completionHandler() }
            Task { @MainActor in
                await StepCounter.shared.refresh()
                completionHandler()
            }
        }
        observerQuery = query
        store.execute(query)
        store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { _, _ in }
    }

    private static func storedTarget(_ key: String) -> Int {
        let stored = UserDefaults.standard.object(forKey: key) as? Int ?? defaultTarget
        return max(stored, 1)
    }

    private func totalSteps(from start: Date, to end: Date? = nil) async throws -> Double {
        let range = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: range),
            options: .cumulativeSum
        )
        return try await query.result(for: store)?.sumQuantity()?.doubleValue(for: .count()) ?? 0
    }

    private func fetchRecentWorkouts() async throws -> [WorkoutSummary] {
        let query = HKSampleQueryDescriptor(
            predicates: [.workout()],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: Self.recentWorkoutLimit
        )
        var summaries: [WorkoutSummary] = []
        for workout in try await query.result(for: store) {
            summaries.append(try await summary(of: workout))
        }
        return summaries
    }

    private func summary(of workout: HKWorkout) async throws -> WorkoutSummary {
        let distance = distanceTypes.lazy
            .compactMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }
            .first { $0 > 0 }
        let energy = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let steps = try await totalSteps(from: workout.startDate, to: workout.endDate)
        let isIndoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool
        return WorkoutSummary(
            id: workout.uuid,
            name: workout.workoutActivityType.displayName(isIndoor: isIndoor),
            date: workout.startDate,
            duration: workout.duration,
            distanceMeters: distance,
            steps: Int(steps),
            energyKcal: energy.flatMap { $0 > 0 ? $0 : nil }
        )
    }
}

private extension HKWorkoutActivityType {
    func displayName(isIndoor: Bool?) -> String {
        let place = isIndoor.map { $0 ? "Indoor " : "Outdoor " } ?? ""
        switch self {
        case .walking: return place + "Walk"
        case .running: return place + "Run"
        case .cycling: return place + "Cycle"
        case .hiking: return "Hiking"
        case .swimming: return "Swimming"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Stepper"
        case .yoga: return "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .socialDance, .cardioDance: return "Dance"
        default: return "Workout"
        }
    }
}
