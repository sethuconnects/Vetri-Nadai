import SwiftUI

struct SettingsView: View {
    @AppStorage(StepReminders.minuteKey) private var reminderMinute = StepReminders.defaultMinute
    @AppStorage(StepCounter.targetKey) private var dailyTarget = StepCounter.defaultTarget
    @AppStorage(StepCounter.monthlyTargetKey) private var monthlyTarget = StepCounter.defaultTarget
    @AppStorage(UsageLimit.minutesKey) private var usageLimitMinutes = UsageLimit.defaultMinutes
    @AppStorage(SleepTracker.historyKey) private var sleepHistoryNights = SleepTracker.defaultHistory
    @AppStorage(StepCounter.recentWorkoutsKey) private var recentWorkouts = StepCounter.defaultRecentWorkouts
    @Environment(\.dismiss) private var dismiss
    var onChange: () -> Void = {}

    private static let targetRange = 1_000...50_000
    private static let targetStep = 500

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Minute past the hour", selection: $reminderMinute) {
                        ForEach(0..<60, id: \.self) { minute in
                            Text(String(format: ":%02d", minute)).tag(minute)
                        }
                    }
                } header: {
                    Text("Step reminders")
                } footer: {
                    Text("You'll be reminded every hour from \(timeLabel(StepReminders.reminderHours.lowerBound)) to \(timeLabel(StepReminders.reminderHours.upperBound)).")
                }

                Section {
                    targetStepper("Daily target", value: $dailyTarget)
                    targetStepper("Monthly average target", value: $monthlyTarget)
                } header: {
                    Text("Step targets")
                } footer: {
                    Text("Daily target is today's goal. Monthly average target is the steps per day you want to average this month.")
                }

                Section {
                    Stepper(value: $recentWorkouts, in: StepCounter.recentWorkoutsRange) {
                        LabeledContent("Recent workouts", value: "\(recentWorkouts)")
                    }
                    Stepper(value: $sleepHistoryNights, in: SleepTracker.historyRange) {
                        LabeledContent("Sleep history", value: sleepHistoryNights == 1 ? "1 night" : "\(sleepHistoryNights) nights")
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("How many workouts to show in the home page carousel, and how many earlier nights to list on the sleep page.")
                }

                Section {
                    Stepper(value: $usageLimitMinutes, in: UsageLimit.range) {
                        LabeledContent("Lock after", value: usageLimitMinutes == 0 ? "Off" : "\(usageLimitMinutes) min")
                    }
                } header: {
                    Text("Screen time limit")
                } footer: {
                    Text("After this many minutes of continuous use, the app locks with a scary screen and sound. Leaving the app for \(Int(UsageLimit.breakDuration / 60)) minutes resets the clock. To unlock, press and hold the scary screen for 5 seconds.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: reminderMinute) { onChange() }
            .onChange(of: dailyTarget) { onChange() }
            .onChange(of: monthlyTarget) { onChange() }
            .onChange(of: recentWorkouts) { onChange() }
        }
    }

    private func targetStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: Self.targetRange, step: Self.targetStep) {
            LabeledContent(title, value: "\(value.wrappedValue.formatted()) steps")
        }
    }

    private func timeLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: reminderMinute, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    SettingsView()
}
