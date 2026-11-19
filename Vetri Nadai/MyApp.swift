import SwiftUI

@main struct MyApp: App {
    init() {
        StepReminders.shared.activate()
        StepCounter.shared.startBackgroundUpdates()
    }

    var body: some Scene {

       WindowGroup {
            ContentView()
        }
    }
}
