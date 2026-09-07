import AppKit
import Foundation

/// Running from the installer disk (or Downloads) dies when that folder goes away.
/// Copy into Applications and reopen from there before the user can eject.
enum MoveToApplications {
    /// Returns true if this process is exiting so a copy in Applications can take over.
    @MainActor
    static func relocateIfNeeded(opening files: [URL]) -> Bool {
        let source = Bundle.main.bundleURL.standardizedFileURL
        guard source.pathExtension == "app" else { return false }
        if source.path.contains("/.build/") { return false }
        if isApplicationsInstall(source) { return false }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.orderOut(nil)
        }

        let dest = URL(fileURLWithPath: "/Applications/yourMark.app")
        let fromDisk = isOnRemovableVolume(source)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Put yourMark in Applications"
        if fromDisk {
            alert.informativeText = "This copy is still on the installer disk. If you eject that disk, yourMark will stop.\n\nCopy it to the Applications folder now? Then you can eject the disk."
        } else {
            alert.informativeText = "yourMark should live in the Applications folder so it keeps working after you close this window.\n\nCopy it there now?"
        }
        alert.addButton(withTitle: "Copy to Applications")
        alert.addButton(withTitle: "Quit")
        let pick = alert.runModal()
        if pick != .alertFirstButtonReturn {
            NSApp.terminate(nil)
            return true
        }

        do {
            try install(from: source, to: dest)
            relaunch(at: dest, files: files)
            NSApp.terminate(nil)
            return true
        } catch {
            let fail = NSAlert()
            fail.alertStyle = .warning
            fail.messageText = "Could not copy to Applications"
            fail.informativeText = "Drag yourMark onto the Applications folder (follow the arrow on the disk), then open it from there. Do not run it from the installer disk.\n\n\(error.localizedDescription)"
            fail.addButton(withTitle: "Quit")
            fail.runModal()
            NSApp.terminate(nil)
            return true
        }
    }

    private static func isApplicationsInstall(_ url: URL) -> Bool {
        let path = url.path
        if path == "/Applications/yourMark.app" { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/yourMark.app").path
        return path == home
    }

    private static func isOnRemovableVolume(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [
            .volumeIsReadOnlyKey,
            .volumeIsEjectableKey,
            .volumeIsRemovableKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        if values?.volumeIsReadOnly == true { return true }
        if values?.volumeIsEjectable == true { return true }
        if values?.volumeIsRemovable == true { return true }
        if url.path.hasPrefix("/Volumes/") { return true }
        if url.path.contains("AppTranslocation") { return true }
        return false
    }

    private static func install(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        if dest.standardizedFileURL == source {
            return
        }
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: source, to: dest)
        clearQuarantine(dest)
    }

    private static func clearQuarantine(_ url: URL) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        proc.arguments = ["-cr", url.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
    }

    private static func relaunch(at dest: URL, files: [URL]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        if files.isEmpty {
            proc.arguments = ["-n", dest.path]
        } else {
            proc.arguments = ["-n", "-a", dest.path] + files.map(\.path)
        }
        try? proc.run()
        proc.waitUntilExit()
    }
}
