import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let photoManager = PhotoManager()
        let statsManager = StatsManager()
        let pipeline     = SmilePipeline(photoManager: photoManager, statsManager: statsManager)

        statusBar = StatusBarController(pipeline: pipeline,
                                        photoManager: photoManager,
                                        statsManager: statsManager)

        // UNUserNotificationCenter & WeeklyReport require a real app bundle.
        // Skip gracefully when running via `swift run` (no bundle identifier).
        if Bundle.main.bundleIdentifier != nil {
            requestNotificationPermission()
            WeeklyReportScheduler.shared.schedule(photoManager: photoManager, statsManager: statsManager)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}



