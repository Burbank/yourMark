import AppKit
import SwiftUI

@main
struct YourMarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("yourMark", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear { appDelegate.attach(model) }
                .onOpenURL { url in model.openIncoming([url]) }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Files…") { model.pickFiles() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Settings") {
                Button("Settings") { model.toggleSettings() }
                    .keyboardShortcut(",", modifiers: .command)
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
        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
        for window in NSApp.windows {
            window.tabbingMode = .disallowed
        }
        if MoveToApplications.relocateIfNeeded(opening: pending) {
            return
        }
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

    func upgradeEngine() {
        Task { await model?.upgradeEngine() }
    }

    func installEngine() {
        Task { await model?.installEngine() }
    }

    func checkUpdates() {
        Task { await model?.checkUpdates(force: true) }
    }
}
