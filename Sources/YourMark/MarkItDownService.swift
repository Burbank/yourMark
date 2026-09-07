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

    func convert(
        input: URL,
        output: URL,
        script: URL? = nil,
        llmKey: String = "",
        llmBase: String = "",
        llmModel: String = ""
    ) async throws -> URL {
        let exe = try await resolveEngine()
        let ext = input.pathExtension.lowercased()
        let keepUris = ["docx", "pptx", "xlsx", "ppt", "xls", "html", "htm",
                        "jpg", "jpeg", "png", "gif", "webp", "tif", "tiff"].contains(ext)

        if let script, FileManager.default.isReadableFile(atPath: script.path),
           let py = await pythonForEngine() {
            var extra: [String: String] = [:]
            if !llmKey.isEmpty {
                extra["YOURMARK_LLM_KEY"] = llmKey
                extra["YOURMARK_LLM_BASE"] = llmBase
                extra["YOURMARK_LLM_MODEL"] = llmModel
            }
            do {
                _ = try await run(
                    executable: py,
                    arguments: [script.path, input.path, output.path],
                    captureStdout: false,
                    extraEnv: extra
                )
                if FileManager.default.fileExists(atPath: output.path) {
                    return output
                }
            } catch {
                // Fall through to the CLI.
            }
        }

        var attempts: [[String]] = [
            [input.path, "-o", output.path, "--use-plugins"],
        ]
        if keepUris {
            attempts.insert([input.path, "-o", output.path, "--keep-data-uris", "--use-plugins"], at: 0)
        }
        var lastError: Error = YourMarkError.outputMissing(output.path)
        for args in attempts {
            do {
                _ = try await run(executable: exe, arguments: args, captureStdout: false)
                if FileManager.default.fileExists(atPath: output.path) {
                    return output
                }
                lastError = YourMarkError.outputMissing(output.path)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// pdfplumber lives in the same uv tool env as markitdown. Best-effort.
    func enrichPDF(markdown: URL, pdf: URL, script: URL?) async {
        guard pdf.pathExtension.lowercased() == "pdf" else { return }
        guard let script, FileManager.default.isReadableFile(atPath: script.path) else { return }
        guard let py = await pythonForEngine() else { return }
        _ = try? await run(
            executable: py,
            arguments: [script.path, pdf.path, markdown.path],
            captureStdout: false
        )
    }

    private func pythonForEngine() async -> String? {
        let exe = (try? await resolveEngine()) ?? enginePath
        guard let exe else { return nil }
        if let data = FileManager.default.contents(atPath: exe),
           let head = String(data: data.prefix(240), encoding: .utf8),
           head.hasPrefix("#!") {
            let line = head.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            var path = line.replacingOccurrences(of: "#!", with: "")
                .trimmingCharacters(in: .whitespaces)
            if path.hasPrefix("/usr/bin/env ") {
                path = String(path.dropFirst("/usr/bin/env ".count))
            }
            if path.hasSuffix("/python") || path.hasSuffix("/python3"),
               FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
            // uv shim: exec …/markitdown/bin/markitdown
            if let match = path.range(of: "/bin/markitdown") {
                let python = String(path[..<match.lowerBound]) + "/bin/python"
                if FileManager.default.isExecutableFile(atPath: python) { return python }
            }
        }
        if let data = FileManager.default.contents(atPath: exe),
           let text = String(data: data.prefix(2000), encoding: .utf8),
           let range = text.range(of: #"(/[^\s]+/markitdown/bin/)"#, options: .regularExpression) {
            let python = String(text[range]) + "python"
            if FileManager.default.isExecutableFile(atPath: python) { return python }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let guessed = [
            "\(home)/.local/share/uv/tools/markitdown/bin/python",
            "\(home)/.local/share/uv/tools/markitdown/bin/python3",
        ]
        return guessed.first { FileManager.default.isExecutableFile(atPath: $0) }
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
        if let py = await pythonForEngine() {
            log.append("Installing Microsoft’s official plugins (OCR + RTF) into the same converter…")
            _ = try? await run(
                executable: uv,
                arguments: ["pip", "install", "--python", py, "-U", "markitdown-ocr", "markitdown-sample-plugin"],
                captureStdout: true
            )
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
                if let py = await pythonForEngine() {
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    let uvBin = [
                        "\(home)/.local/bin/uv",
                        "/opt/homebrew/bin/uv",
                        "/usr/local/bin/uv",
                    ].first { FileManager.default.isExecutableFile(atPath: $0) }
                    if let uvBin {
                        _ = try? await run(
                            executable: uvBin,
                            arguments: ["pip", "install", "--python", py, "-U", "markitdown-ocr", "markitdown-sample-plugin"],
                            captureStdout: true
                        )
                    }
                }
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
        captureStdout: Bool = false,
        extraEnv: [String: String] = [:]
    ) async throws -> (stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try ProcessRun.run(
                        executable: executable,
                        arguments: arguments,
                        extraEnv: extraEnv,
                        captureStdout: captureStdout
                    )
                    if result.status == 0 {
                        continuation.resume(returning: (result.stdout, result.stderr))
                    } else {
                        let detail = result.stderr.isEmpty ? result.stdout : result.stderr
                        continuation.resume(throwing: YourMarkError.processFailed(
                            detail.isEmpty
                                ? "markitdown exited \(result.status)"
                                : detail
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func runShell(_ command: String) async throws -> (stdout: String, stderr: String) {
        try await run(
            executable: "/bin/zsh",
            arguments: ["-lc", command],
            captureStdout: true
        )
    }
}
