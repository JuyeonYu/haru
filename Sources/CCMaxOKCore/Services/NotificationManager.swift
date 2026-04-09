import Foundation
import UserNotifications
import os

public final class NotificationManager: NSObject, Sendable, UNUserNotificationCenterDelegate {
    private let database: DatabaseManager
    private let cooldownSeconds: Double

    public init(database: DatabaseManager, cooldownSeconds: Double = 3600) {
        self.database = database
        self.cooldownSeconds = cooldownSeconds
        super.init()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    public func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                CCMaxOKCore.logger.error("Notification permission error: \(error.localizedDescription)")
            }
            CCMaxOKCore.logger.info("Notification permission granted: \(granted)")
        }
    }

    // 앱이 포그라운드일 때도 배너 표시
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
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
        content.title = String(localized: "haru", bundle: .module)
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
