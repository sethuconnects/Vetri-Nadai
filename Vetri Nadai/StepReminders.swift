import Foundation
import UserNotifications

/// Hourly "keep walking" reminders at a configurable minute (default :19) from 12 PM to 11 PM.
/// Notification content is fixed when scheduled, so every step refresh reschedules
/// the pending slots with the latest numbers.
final class StepReminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = StepReminders()
    static let minuteKey = "reminderMinute"
    static let defaultMinute = 19
    static let reminderHours = 12...23

    private static let idPrefix = "stepReminder."
    private static var reminderMinute: Int {
        let stored = UserDefaults.standard.object(forKey: minuteKey) as? Int ?? defaultMinute
        return min(max(stored, 0), 59)
    }
    private let center = UNUserNotificationCenter.current()

    func activate() {
        center.delegate = self
    }

    func reschedule(todaySteps: Int, monthSteps: Int, daysSoFar: Int, now: Date = .now) async {
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        )

        let calendar = Calendar.current
        let dailyTarget = StepCounter.dailyTarget
        let monthlyTarget = StepCounter.monthlyTarget
        let name = UserDefaults.standard.string(forKey: "userName") ?? ""
        let startOfToday = calendar.startOfDay(for: now)
        let minute = Self.reminderMinute

        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            let todayRemaining: Int
            let monthRemaining: Int
            if dayOffset == 0 {
                todayRemaining = dailyTarget - todaySteps
                monthRemaining = monthlyTarget * daysSoFar - monthSteps
            } else {
                // Tomorrow's slots are a fallback in case no refresh happens before then.
                let sameMonth = calendar.isDate(day, equalTo: startOfToday, toGranularity: .month)
                todayRemaining = dailyTarget
                monthRemaining = sameMonth ? monthlyTarget * (daysSoFar + 1) - monthSteps : monthlyTarget
            }
            guard todayRemaining > 0 || monthRemaining > 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Time to move! 🚶"
            content.body = Self.message(
                name: name, dailyTarget: dailyTarget,
                todayRemaining: todayRemaining, monthRemaining: monthRemaining
            )
            content.sound = .default

            for hour in Self.reminderHours {
                guard let fireDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                      fireDate > now else { continue }
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let request = UNNotificationRequest(
                    identifier: Self.idPrefix + ISO8601DateFormatter().string(from: fireDate),
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
                try? await center.add(request)
            }
        }
    }

    static func message(name: String, dailyTarget: Int, todayRemaining: Int, monthRemaining: Int) -> String {
        let greeting = name.isEmpty ? "Hey" : "Hey \(name)"
        let goal = dailyTarget.formatted()
        let today = max(0, todayRemaining).formatted()
        let month = max(0, monthRemaining).formatted()
        switch (todayRemaining > 0, monthRemaining > 0) {
        case (true, true):
            return "\(greeting), you need \(today) more steps today to hit your \(goal) target, and \(month) more steps to get your monthly average on track. Come on, you've got this! 💪"
        case (true, false):
            return "\(greeting), you need \(today) more steps today to hit your \(goal) target. Your monthly average is on track, keep it that way! 💪"
        default:
            return "\(greeting), \(goal) steps done today! 🎉 Just \(month) more steps to get your monthly average on track. Come on, keep going!"
        }
    }

    // Show the banner even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
