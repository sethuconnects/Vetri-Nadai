#if DEBUG
import Foundation

/// Sample data for README screenshots. Only active in Debug builds launched with `-demoData`.
/// Optional: `-demoPage <0|1|2>` opens Home, Gym or Sleep; `-demoSettings` opens the Settings sheet.
enum DemoData {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-demoData")
    static var page: Int { isEnabled ? UserDefaults.standard.integer(forKey: "demoPage") : 0 }
    static var showSettings: Bool { isEnabled && UserDefaults.standard.bool(forKey: "demoSettings") }

    private static var calendar: Calendar { .current }

    private static func today(_ hour: Int, _ minute: Int, daysAgo: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    // MARK: Steps

    static let steps = 8_432
    static let yesterdaySteps = 11_204
    static let monthAverage = 9_615
    static var stepsToTarget: Int {
        (StepCounter.monthlyTarget - monthAverage) * calendar.component(.day, from: .now)
    }

    static var workouts: [StepCounter.WorkoutSummary] {
        [
            .init(id: UUID(), name: "Strength Training", date: today(7, 5), duration: 52 * 60,
                  distanceMeters: nil, steps: 0, energyKcal: 318),
            .init(id: UUID(), name: "Outdoor Walk", date: today(18, 40, daysAgo: 1), duration: 46 * 60,
                  distanceMeters: 4_250, steps: 5_610, energyKcal: 214),
            .init(id: UUID(), name: "Elliptical", date: today(7, 10, daysAgo: 2), duration: 25 * 60,
                  distanceMeters: nil, steps: 0, energyKcal: 190),
        ]
    }

    // MARK: Gym

    static func gymDays(for month: Date) -> [GymTracker.Day] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let lastDay = min(interval.end, calendar.startOfDay(for: .now).addingTimeInterval(86_400))
        var days: [GymTracker.Day] = []
        var day = interval.start
        var index = 0
        while day < lastDay {
            // Roughly 4–5 gym days a week, skipping Sundays.
            let weekday = calendar.component(.weekday, from: day)
            if weekday != 1 && index % 7 != 3 {
                days.append(.init(day: day, sessions: sessions(on: day, variant: index)))
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
            index += 1
        }
        return days.reversed()
    }

    private static func sessions(on day: Date, variant: Int) -> [GymTracker.Session] {
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        let strength = GymTracker.Session(id: UUID(), name: "Strength Training", start: at(7, 5),
                                          duration: Double(45 + variant % 3 * 5) * 60, energyKcal: Double(280 + variant % 4 * 15))
        switch variant % 3 {
        case 0:
            return [strength, .init(id: UUID(), name: "Elliptical", start: at(7, 58), duration: 20 * 60, energyKcal: 165)]
        case 1:
            return [.init(id: UUID(), name: "Indoor Walk", start: at(6, 50), duration: 30 * 60, energyKcal: 140), strength]
        default:
            return [strength]
        }
    }

    // MARK: Sleep

    static var nights: [SleepTracker.Night] {
        // Minutes asleep per night, newest first, to show a spread of ratings.
        let lengths = [468, 412, 352, 437, 385, 495, 401, 452]
        return lengths.enumerated().map { night(daysAgo: $0.offset, asleepMinutes: $0.element) }
    }

    private static func night(daysAgo: Int, asleepMinutes: Int) -> SleepTracker.Night {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now))!
        let bedtime = day.addingTimeInterval(Double(-55 + daysAgo % 3 * 10) * 60)
        let pattern: [(SleepTracker.Stage, Double)] = [
            (.core, 18), (.deep, 48), (.core, 32), (.rem, 18), (.awake, 4),
            (.core, 42), (.deep, 30), (.rem, 26), (.core, 48), (.awake, 3),
            (.rem, 32), (.core, 52), (.deep, 12), (.rem, 36), (.core, 40),
        ]
        let patternSleep = pattern.filter { $0.0 != .awake }.reduce(0) { $0 + $1.1 }
        let scale = Double(asleepMinutes) / patternSleep

        var segments: [SleepTracker.Segment] = []
        var cursor = bedtime
        var totals: [SleepTracker.Stage: TimeInterval] = [:]
        for (stage, minutes) in pattern {
            let length = (stage == .awake ? minutes : minutes * scale) * 60
            segments.append(.init(stage: stage, start: cursor, end: cursor.addingTimeInterval(length)))
            totals[stage, default: 0] += length
            cursor = cursor.addingTimeInterval(length)
        }
        return SleepTracker.Night(
            day: day,
            bedtime: bedtime,
            wakeTime: cursor,
            asleep: Double(asleepMinutes) * 60,
            deep: totals[.deep] ?? 0,
            rem: totals[.rem] ?? 0,
            core: totals[.core] ?? 0,
            awake: totals[.awake] ?? 0,
            interruptions: pattern.filter { $0.0 == .awake }.count,
            segments: segments
        )
    }
}
#endif
