import Foundation

/// Run a helper without filling the stdout/stderr pipe (that deadlock looks like a freeze
/// after MarkItDown has already written the Markdown file).
enum ProcessRun {
    struct Result {
        var stdout: String
        var stderr: String
        var status: Int32
    }

    enum ConvertCancel: Error, LocalizedError {
        case stopped
        var errorDescription: String? { "Stopped" }
    }

    enum Timeout: Error, LocalizedError {
        case expired
        var errorDescription: String? { "That step took too long and was stopped." }
    }

    private static let convertGate = ConvertGate()

    static var convertWasCancelled: Bool { convertGate.isCancelled }

    static func cancelConvert() {
        convertGate.cancel()
    }

    static func resetConvertCancel() {
        convertGate.reset()
    }

    static func run(
        executable: String,
        arguments: [String],
        extraPATH: [String] = [],
        extraEnv: [String: String] = [:],
        captureStdout: Bool = true,
        cancellable: Bool = false,
        timeout: TimeInterval? = nil
    ) throws -> Result {
        if cancellable, convertGate.isCancelled {
            throw ConvertCancel.stopped
        }
        let limit = timeout ?? (cancellable ? 45 * 60 : 90)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = captureStdout ? outPipe : FileHandle.nullDevice
        process.standardError = errPipe

        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = extraPATH + [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        env["PATH"] = extra.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        for (k, v) in extraEnv { env[k] = v }
        process.environment = env

        let box = DrainBox()
        let group = DispatchGroup()
        if captureStdout {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                box.stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            box.stderr = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        try process.run()
        if cancellable {
            do {
                try convertGate.attach(process)
            } catch {
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
                throw error
            }
        }
        let deadline = Date().addingTimeInterval(limit)
        while process.isRunning {
            if Date() > deadline {
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
                if cancellable { convertGate.detach(process) }
                throw Timeout.expired
            }
            if cancellable, convertGate.isCancelled {
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
                convertGate.detach(process)
                throw ConvertCancel.stopped
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        if cancellable { convertGate.detach(process) }
        _ = group.wait(timeout: .now() + 8)

        if cancellable, convertGate.isCancelled {
            throw ConvertCancel.stopped
        }

        return Result(
            stdout: String(data: box.stdout, encoding: .utf8) ?? "",
            stderr: String(data: box.stderr, encoding: .utf8) ?? "",
            status: process.terminationStatus
        )
    }
}

private final class ConvertGate: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func reset() {
        lock.lock()
        cancelled = false
        process = nil
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        process = nil
        lock.unlock()
        if let running, running.isRunning {
            running.terminate()
        }
    }

    func attach(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw ProcessRun.ConvertCancel.stopped }
        self.process = process
    }

    func detach(_ process: Process) {
        lock.lock()
        if self.process === process { self.process = nil }
        lock.unlock()
    }
}

private final class DrainBox: @unchecked Sendable {
    var stdout = Data()
    var stderr = Data()
}
