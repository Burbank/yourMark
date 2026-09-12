import CoreServices
import Dispatch
import Foundation

/// Watches converted Markdown folders. Editors like MarkEdit and MarkText save by replacing
/// the file (the old vnode is deleted). We re-arm the watch so that does not
/// crash the process.
final class FileWatcher: @unchecked Sendable {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var inboxStream: FSEventStreamRef?
    private var inboxPath = ""
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.burbank.yourmark.watch", qos: .utility)
    var onChange: ((String) -> Void)?

    func replace(paths: [String]) {
        update(paths: paths)
    }

    /// Add or drop watches without tearing down ones that are already correct.
    func update(paths: [String]) {
        let wanted = Set(paths)
        lock.lock()
        let have = Set(sources.keys)
        let gone = have.subtracting(wanted)
        for path in gone {
            sources[path]?.cancel()
            sources[path] = nil
        }
        lock.unlock()
        for path in wanted.subtracting(have) {
            addWatch(path)
        }
    }

    /// Watch the user’s yourMark folder for new Markdown dropped in Finder.
    func watchInbox(_ path: String?) {
        let next = path ?? ""
        lock.lock()
        let same = next == inboxPath && inboxStream != nil
        lock.unlock()
        if same { return }
        stopInbox()
        guard !next.isEmpty, FileManager.default.fileExists(atPath: next) else { return }
        lock.lock()
        inboxPath = next
        lock.unlock()
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let p = watcher.inboxPath
            DispatchQueue.main.async {
                watcher.onChange?(p)
            }
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &ctx,
            [next] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        lock.lock()
        inboxStream = stream
        lock.unlock()
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        stopInbox()
        lock.lock()
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
        lock.unlock()
    }

    private func stopInbox() {
        lock.lock()
        let stream = inboxStream
        inboxStream = nil
        inboxPath = ""
        lock.unlock()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    deinit { stop() }

    private func addWatch(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            let p = path
            // AppModel is @MainActor. Calling its closure on this queue
            // traps on macOS 26 (Swift isolation assert). Hop first.
            DispatchQueue.main.async {
                self.onChange?(p)
            }
            let gone = flags.contains(.delete) || flags.contains(.rename)
            if gone {
                src.cancel()
                self.queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.rearm(p)
                }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        lock.lock()
        sources[path]?.cancel()
        sources[path] = src
        lock.unlock()
    }

    private func rearm(_ path: String) {
        lock.lock()
        sources[path] = nil
        lock.unlock()
        addWatch(path)
    }
}
