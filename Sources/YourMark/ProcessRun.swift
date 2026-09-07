import Foundation

/// Run a helper without filling the stdout/stderr pipe (that deadlock looks like a freeze
/// after MarkItDown has already written the Markdown file).
enum ProcessRun {
    struct Result {
        var stdout: String
        var stderr: String
        var status: Int32
    }

    static func run(
        executable: String,
        arguments: [String],
        extraPATH: [String] = [],
        extraEnv: [String: String] = [:],
        captureStdout: Bool = true
    ) throws -> Result {
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
        process.waitUntilExit()
        _ = group.wait(timeout: .now() + 8)

        return Result(
            stdout: String(data: box.stdout, encoding: .utf8) ?? "",
            stderr: String(data: box.stderr, encoding: .utf8) ?? "",
            status: process.terminationStatus
        )
    }
}

private final class DrainBox: @unchecked Sendable {
    var stdout = Data()
    var stderr = Data()
}
