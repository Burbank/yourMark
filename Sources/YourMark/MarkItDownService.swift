import Foundation

/// Thin local wrapper around Microsoft MarkItDown on PyPI.
/// Never vendors the converter — discovers `markitdown` / `uv` on this Mac.
actor MarkItDownService {
    private(set) var enginePath: String?
    private(set) var versionString: String = "unknown"
    private(set) var installHint: String = "uv tool install 'markitdown[all]'"

    func refreshStatus() async -> (path: String?, version: String) {
        do {
            let path = try await resolveEngine()
            return (path, versionString)
        } catch {
            enginePath = nil
            versionString = "not found"
            return (nil, versionString)
        }
    }

    func resolveEngine() async throws -> String {
        if let enginePath, FileManager.default.isExecutableFile(atPath: enginePath) {
            return enginePath
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/markitdown",
            "/opt/homebrew/bin/markitdown",
            "/usr/local/bin/markitdown",
            "\(home)/Library/Python/3.12/bin/markitdown",
            "\(home)/Library/Python/3.11/bin/markitdown",
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            enginePath = path
            versionString = await readVersion(executable: path)
            return path
        }

        if let which = try? await runShell("command -v markitdown").stdout
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !which.isEmpty,
           FileManager.default.isExecutableFile(atPath: which) {
            enginePath = which
            versionString = await readVersion(executable: which)
            return which
        }

        throw YourMarkError.engineNotFound
    }

    func convert(input: URL, output: URL) async throws -> URL {
        let exe = try await resolveEngine()
        // keep-data-uris embeds figures from Word/PPTX as Markdown images.
        // Older markitdown builds may not know the flag — retry plain.
        let attempts: [[String]] = [
            [input.path, "-o", output.path, "--keep-data-uris"],
            [input.path, "-o", output.path],
        ]
        var lastError: Error = YourMarkError.outputMissing(output.path)
        for args in attempts {
            do {
                let result = try await run(executable: exe, arguments: args, captureStdout: true)
                if FileManager.default.fileExists(atPath: output.path) {
                    return output
                }
                let detail = result.stderr.isEmpty ? result.stdout : result.stderr
                lastError = YourMarkError.outputMissing(detail.isEmpty ? output.path : detail)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Install Microsoft’s official MarkItDown from PyPI (uv). Not vendored.
    func installEngine() async throws -> String {
        enginePath = nil
        var log: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let uvPaths = [
            "\(home)/.local/bin/uv",
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
        ]
        var uv = uvPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        if uv == nil {
            log.append("Installing uv (the installer Microsoft’s docs recommend)…")
            let script = "\(NSTemporaryDirectory())uv-install.sh"
            let downloaded = try await run(
                executable: "/usr/bin/curl",
                arguments: ["-LsSf", "https://astral.sh/uv/install.sh", "-o", script],
                captureStdout: true
            )
            log.append(downloaded.stdout)
            log.append(downloaded.stderr)
            let result = try await run(executable: "/bin/zsh", arguments: [script], captureStdout: true)
            log.append(result.stdout)
            log.append(result.stderr)
            uv = uvPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        }
        guard let uv, FileManager.default.isExecutableFile(atPath: uv) else {
            throw YourMarkError.processFailed("Could not install uv. Connect to the internet and try Install converter again.")
        }
        log.append("Installing Microsoft MarkItDown from PyPI…")
        let attempts: [[String]] = [
            ["tool", "install", "--force", "markitdown[all]"],
            ["tool", "upgrade", "markitdown"],
        ]
        var last = ""
        for args in attempts {
            do {
                let installed = try await run(executable: uv, arguments: args, captureStdout: true)
                log.append(installed.stdout)
                log.append(installed.stderr)
                last = ""
                break
            } catch {
                last = error.localizedDescription
                log.append(last)
            }
        }
        enginePath = nil
        do {
            _ = try await resolveEngine()
        } catch {
            if !last.isEmpty {
                throw YourMarkError.processFailed(last)
            }
            throw error
        }
        log.append("Ready · \(versionString)")
        return log.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
    }

    /// Upgrade the PyPI package — this is how Microsoft updates reach the GUI.
    func upgradeEngine() async throws -> String {
        let commands = [
            "uv tool upgrade markitdown",
            "uv pip install -U 'markitdown[all]'",
            "pip3 install -U 'markitdown[all]'",
        ]
        var lastError = "No uv/pip found"
        for command in commands {
            do {
                let result = try await runShell(command)
                _ = try await resolveEngine()
                versionString = await readVersion(executable: enginePath ?? "")
                return result.stdout.isEmpty ? "Upgraded via \(command)" : result.stdout
            } catch {
                lastError = error.localizedDescription
            }
        }
        throw YourMarkError.processFailed(lastError)
    }

    func suggestedOutput(for input: URL) -> URL {
        let parent = input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        return parent.appendingPathComponent("\(stem).md")
    }

    private func readVersion(executable: String) async -> String {
        guard !executable.isEmpty else { return "unknown" }
        let out = (try? await run(executable: executable, arguments: ["--version"], captureStdout: true).stdout)
            ?? ""
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    @discardableResult
    private func run(
        executable: String,
        arguments: [String],
        captureStdout: Bool = false
    ) async throws -> (stdout: String, stderr: String) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outPipe
        process.standardError = errPipe

        var env = ProcessInfo.processInfo.environment
        let extra = [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        let path = env["PATH"] ?? ""
        env["PATH"] = extra.joined(separator: ":") + ":" + path
        process.environment = env

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: (stdout, stderr))
                } else {
                    let detail = stderr.isEmpty ? stdout : stderr
                    continuation.resume(throwing: YourMarkError.processFailed(
                        detail.isEmpty
                            ? "markitdown exited \(proc.terminationStatus)"
                            : detail
                    ))
                }
            }
        }
    }

    func runShell(_ command: String) async throws -> (stdout: String, stderr: String) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        var env = ProcessInfo.processInfo.environment
        let extra = [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        env["PATH"] = extra.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        process.environment = env
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: (stdout, stderr))
                } else {
                    continuation.resume(throwing: YourMarkError.processFailed(
                        stderr.isEmpty ? stdout : stderr
                    ))
                }
            }
        }
    }
}
