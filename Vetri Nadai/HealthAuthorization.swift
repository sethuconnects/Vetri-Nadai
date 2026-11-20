import HealthKit

/// Requests HealthKit read access once per data type per launch, instead of before every query.
/// Once a type has been asked about, asking again never shows a prompt, so repeating it is wasted work.
enum HealthAuthorization {
    private static let store = HKHealthStore()
    private static var requested: Set<HKObjectType> = []

    static func requestReadAccess(to types: Set<HKObjectType>) async throws {
        let missing = types.subtracting(requested)
        guard !missing.isEmpty else { return }
        try await store.requestAuthorization(toShare: [], read: missing)
        requested.formUnion(missing)
    }
}
