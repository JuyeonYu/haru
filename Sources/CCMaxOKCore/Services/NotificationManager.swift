import Foundation
import UserNotifications

public final class NotificationManager: Sendable {
    private let database: DatabaseManager
    private let cooldownSeconds: Double

    public init(database: DatabaseManager, cooldownSeconds: Double = 3600) {
        self.database = database
        self.cooldownSeconds = cooldownSeconds
    }

    public func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func shouldSend(alert: UsageAlert) throws -> Bool {
        try database.canSendNotification(type: alert.type, cooldownSeconds: cooldownSeconds)
    }

    public func recordSent(alert: UsageAlert) throws {
        try database.logNotification(type: alert.type, message: alert.message)
    }

    public func send(alert: UsageAlert) throws {
        guard try shouldSend(alert: alert) else { return }

        let content = UNMutableNotificationContent()
        content.title = "CCMaxOK"
        content.body = alert.message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(alert.type)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
        try recordSent(alert: alert)
    }

    public func processAlerts(_ alerts: [UsageAlert]) throws {
        for alert in alerts {
            try send(alert: alert)
        }
    }
}
