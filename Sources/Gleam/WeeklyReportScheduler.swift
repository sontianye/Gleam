import Foundation
import UserNotifications
import AppKit

/// Schedules a weekly report notification every Sunday at 20:00.
final class WeeklyReportScheduler: @unchecked Sendable {

    static let shared = WeeklyReportScheduler()
    private init() {}

    private let generator = WeeklyReportGenerator()

    func schedule(photoManager: PhotoManager, statsManager: StatsManager) {
        // Register notification category
        let openAction = UNNotificationAction(identifier: "OPEN_REPORT",
                                             title: "See your week",
                                             options: .foreground)
        let category = UNNotificationCategory(identifier: "WEEKLY_REPORT",
                                             actions: [openAction],
                                             intentIdentifiers: [],
                                             options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])

        // Schedule weekly trigger: Sunday 20:00
        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour    = 20
        components.minute  = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "✨ Your week in smiles"
        content.body  = "See how many happy moments Gleam captured this week."
        content.sound = .default
        content.categoryIdentifier = "WEEKLY_REPORT"

        let request = UNNotificationRequest(identifier: "gleam.weekly", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)

        // Also generate & save the report in background on schedule
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let photos      = await photoManager.photos(inWeekOf: Date())
            let count       = await statsManager.weeklyCount()
            let peakHour    = await statsManager.peakHourThisWeek()
            let peak        = peakHour.map { Self.formatHour($0) } ?? "—"
            if let url = try? await self.generator.generate(photos: photos, weekStats: (count, peak)) {
                print("[Gleam] Weekly report saved: \(url.path)")
            }
        }
    }

    private static func formatHour(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\(hour < 12 ? "am" : "pm")"
    }
}
