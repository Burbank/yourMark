import AppKit
import SwiftUI
import UserNotifications

@main
struct YourMarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("yourMark", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 780, minHeight: 620)
                .onAppear { appDelegate.attach(model) }
                .onOpenURL { url in model.openIncoming([url]) }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Files…") { model.pickFiles() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            if !Distribution.isAppStore {
                CommandGroup(after: .windowSize) {
                    Button("Size window for App Store screenshot") {
                        appDelegate.sizeWindowForAppStoreShot()
                    }
                }
            }
            CommandMenu("Settings") {
                Button("Settings") { model.toggleSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                if !Distribution.isAppStore {
                    Button("Check for update of the processing engine") {
                        appDelegate.upgradeEngine()
                    }
                    Button("Install converter") {
                        appDelegate.installEngine()
                    }
                    Divider()
                    Button("Check for update of the main app") {
                        appDelegate.checkUpdates()
                    }
                }
            }
            CommandGroup(replacing: .help) {
                Button("yourMark Help") { model.showHelp = true }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var pending: [URL] = []

    func attach(_ model: AppModel) {
        self.model = model
        let extra = pending
        pending.removeAll()
        if !extra.isEmpty {
            model.openIncoming(extra)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReports.installHandler()
        UNUserNotificationCenter.current().delegate = self
        ConvertNotice.requestAccess()
        NSApp.setActivationPolicy(.regular)
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        NSWindow.allowsAutomaticWindowTabbing = false
        for window in NSApp.windows {
            window.tabbingMode = .disallowed
        }
        if MoveToApplications.relocateIfNeeded(opening: pending) {
            return
        }
    }

    @objc func convertWithYourMark(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        var urls: [URL] = []
        if let paths = pboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] {
            urls = paths.map { URL(fileURLWithPath: $0) }
        } else if let items = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            urls = items.filter(\.isFileURL)
        }
        guard !urls.isEmpty else { return }
        if let model {
            model.openIncoming(urls)
        } else {
            pending.append(contentsOf: urls)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let model {
            model.openIncoming(urls)
        } else {
            pending.append(contentsOf: urls)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        application(sender, open: [URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        application(sender, open: filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stopHunterMonitor()
        model?.cancelForageAutosave()
        if model?.hunterOn == true || model?.harvestOpen == true {
            model?.writeForageFile()
            model?.hunterOn = false
        }
    }

    func upgradeEngine() {
        Task { await model?.upgradeEngine() }
    }

    func installEngine() {
        Task { await model?.installEngine() }
    }

    func checkUpdates() {
        Task { await model?.checkUpdates(force: true) }
    }

    /// Full window 1280×800. On this Mac that saves as 1280×800. On a 2× display it saves as 2560×1600. Both are valid for App Store Connect.
    func sizeWindowForAppStoreShot() {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
                ?? NSApp.mainWindow
                ?? NSApp.windows.first
        else { return }
        var frame = window.frame
        frame.size = NSSize(width: 1280, height: 800)
        if let screen = window.screen ?? NSScreen.main {
            let vis = screen.visibleFrame
            frame.origin.x = vis.midX - 640
            frame.origin.y = vis.midY - 400
            if frame.maxX > vis.maxX { frame.origin.x = vis.maxX - frame.width }
            if frame.maxY > vis.maxY { frame.origin.y = vis.maxY - frame.height }
            if frame.minX < vis.minX { frame.origin.x = vis.minX }
            if frame.minY < vis.minY { frame.origin.y = vis.minY }
        }
        window.setFrame(frame, display: true, animate: false)
    }
}

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let path = response.notification.request.content.userInfo[ConvertNotice.markdownKey] as? String
        model?.openConvertedFromNotice(path)
        NSApp.activate(ignoringOtherApps: true)
        completionHandler()
    }
}
