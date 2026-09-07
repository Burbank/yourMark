import Dispatch
import Foundation

/// Watches converted Markdown and original PDFs; fires when the user saves in Finder.
final class FileWatcher: @unchecked Sendable {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private let lock = NSLock()
    var onChange: ((String) -> Void)?

    func replace(paths: [String]) {
        lock.lock()
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
        lock.unlock()

        for path in Set(paths) where FileManager.default.fileExists(atPath: path) {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .rename, .delete, .attrib],
                queue: DispatchQueue.main
            )
            src.setEventHandler { [weak self] in
                self?.onChange?(path)
            }
            src.setCancelHandler { close(fd) }
            src.resume()
            lock.lock()
            sources[path] = src
            lock.unlock()
        }
    }

    func stop() {
        lock.lock()
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
        lock.unlock()
    }

    deinit { stop() }
}
