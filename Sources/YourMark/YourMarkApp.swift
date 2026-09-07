import AppKit
import SwiftUI

@main
struct YourMarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear { appDelegate.model = model }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Files…") { model.pickFiles() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Settings") {
                Button("Upgrade MarkItDown") {
                    Task { await model.upgradeEngine() }
                }
                Button("Recheck Engine") {
                    Task { await model.bootstrap() }
                }
            }
            CommandGroup(replacing: .help) {
                Button("yourMark Help") { model.showHelp = true }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }

        Window("yourMark Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 560, height: 620)
        .onChange(of: model.showHelp) { _, show in
            if show { model.showHelp = false }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func application(_ application: NSApplication, open urls: [URL]) {
        model?.openIncoming(urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
