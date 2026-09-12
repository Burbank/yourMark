import Foundation
import UserNotifications

/// Banner when a PDF (or other file) finishes converting to Markdown.
enum ConvertNotice {
    static let markdownKey = "markdownPath"

    static func requestAccess() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func fileReady(markdown: URL) {
        let content = UNMutableNotificationContent()
        content.title = "yourMark"
        content.body = markdown.lastPathComponent
        content.sound = .default
        content.userInfo = [markdownKey: markdown.path]
        let req = UNNotificationRequest(
            identifier: "convert-\(markdown.path.hashValue)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
