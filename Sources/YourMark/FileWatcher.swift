import Dispatch
import Foundation

/// Watches converted Markdown folders. Editors like MarkEdit save by replacing
/// the file (the old vnode is deleted). We re-arm the watch so that does not
/// crash the process.
final class FileWatcher: @unchecked Sendable {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.burbank.yourmark.watch", qos: .utility)
    var onChange: ((String) -> Void)?

    func replace(paths: [String]) {
        lock.lock()
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
        lock.unlock()
        for path in Set(paths) {
            addWatch(path)
        }
    }

    func stop() {
        lock.lock()
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
        lock.unlock()
    }

    deinit { stop() }

    private func addWatch(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            self.onChange?(path)
            let gone = flags.contains(.delete) || flags.contains(.rename)
            if gone {
                src.cancel()
                self.queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.rearm(path)
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
