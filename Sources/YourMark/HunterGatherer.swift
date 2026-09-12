import AppKit
import Foundation
import SwiftUI

extension AppModel {
    func L(_ english: String) -> String {
        _ = interfaceStamp
        return InterfaceStore.look(english)
    }

    func setInterfaceLang(_ code: String) {
        InterfaceStore.apply(code, markPending: code != "en")
        interfaceStamp += 1
        if code != "en" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                InterfaceStore.markHealthy()
            }
        }
    }

    func addInterfaceLanguage() {
        let code = interfaceAddCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard askHasKey, !code.isEmpty, code != "en" else { return }
        if code == InterfaceStore.code { return }
        interfaceAddBusy = true
        interfaceAddHint = L("Translating the interface…")
        let keys = InterfaceStore.catalogKeys()
        let settings = AskService.Settings(
            provider: askProvider,
            model: askModel,
            baseURL: askBaseURL,
            apiKey: AskSecrets.load()
        )
        let label = TranslateLang.spoken.first(where: { $0.id == code })?.label ?? code
        Task {
            do {
                let table = try await askService.translateInterface(
                    keys: keys,
                    languageLabel: label,
                    languageCode: code,
                    settings: settings
                ) { [interfaceHint = L("Translating the interface…")] done, total in
                    Task { @MainActor in
                        self.interfaceAddHint = "\(interfaceHint) \(done)/\(total)"
                    }
                }
                guard !table.isEmpty else {
                    await MainActor.run {
                        self.interfaceAddBusy = false
                        self.interfaceAddHint = self.L("Could not add that language.")
                    }
                    return
                }
                await MainActor.run {
                    InterfaceStore.saveExtra(code: code, table: table)
                    self.setInterfaceLang(code)
                    self.interfaceAddBusy = false
                    self.interfaceAddHint = self.L("Added this interface language.")
                }
            } catch {
                await MainActor.run {
                    self.interfaceAddBusy = false
                    let why = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.interfaceAddHint = why.isEmpty
                        ? self.L("Could not add that language.")
                        : "\(self.L("Could not add that language.")) \(why)"
                }
            }
        }
    }

    func toggleHunterGatherer() {
        if hunterOn {
            hunterOn = false
            stopHunterMonitor()
            cancelForageAutosave()
            persistForageMarks()
            hunterGatheredByPath = [:]
            hunterGatheredRanges = []
            hunterMarkStamp += 1
            forageLinkUserOff = false
            if harvestOpen {
                refreshHarvest()
            } else {
                writeForageFile()
            }
            updateForageSync(autoOn: true)
        } else {
            stopForageLink()
            hunterOn = true
            hunterSnippets = []
            hunterTextMemo.removeAll(keepingCapacity: true)
            let continueOpen = harvestOpen && existingHarvestURL() != nil
            if continueOpen {
                forageSessionIsNew = false
                forageSessionStamp = stampFromForagePath(hunterSavedPath)
                forageBaseBody = harvestSavedBody()
                hunterGatheredByPath = [:]
                hunterGatheredRanges = []
                applyForageCardMarks(for: currentReaderPath)
            } else {
                forageSessionIsNew = true
                forageSessionStamp = ""
                forageBaseBody = ""
                hunterGatheredByPath = [:]
                hunterGatheredRanges = []
            }
            hunterMarkStamp += 1
            harvestOpen = true
            startHunterMonitor()
            statusText = continueOpen
                ? L("HUNTER-GATHERER is on. New pieces go into the same FORAGE file.")
                : L("HUNTER-GATHERER is on. Click and drag to select, then press Enter.")
            refreshHarvest()
            if !fileSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               fileHitsInReader.indices.contains(fileHitIndex) {
                revealReaderLine(fileHitsInReader[fileHitIndex])
            } else if askHitsInReader.indices.contains(askHitIndex) {
                revealReaderLine(askHitsInReader[askHitIndex])
            }
        }
    }

    func continueForageGather() {
        guard !hunterOn else { return }
        toggleHunterGatherer()
    }

    func closeForagePanel() {
        writeForageFile()
        cancelForageAutosave()
        harvestOpen = false
        stopForageLink()
    }

    func toggleHarvest() {
        harvestOpen.toggle()
        if harvestOpen {
            refreshHarvest()
            updateForageSync(autoOn: !forageLinkUserOff)
        } else {
            stopForageLink()
        }
    }

    var canAppendHarvest: Bool {
        harvestOpen && existingHarvestURL() != nil
    }

    func refreshHarvest() {
        if hunterOn {
            applyHarvestWorkingText()
            return
        }
        let path = hunterSavedPath
        guard !path.isEmpty else {
            harvestTitle = L("FORAGE")
            harvestLines = [PreviewLine(id: 0, text: L("Nothing foraged yet."))]
            harvestHeadings = []
            return
        }
        harvestGen += 1
        let gen = harvestGen
        harvestTitle = Self.foragePrettyTitle(path: path)
        Task.detached(priority: .utility) {
            let pack = AppModel.buildPreview(path: path, scanHeadings: true)
            await MainActor.run {
                guard gen == self.harvestGen, self.harvestOpen, !self.hunterOn else { return }
                self.harvestLines = pack.lines
                self.harvestHeadings = pack.headings
                self.scrollHarvestToLatest()
                self.updateForageSync(autoOn: !self.forageLinkUserOff)
            }
        }
    }

    private func applyHarvestWorkingText() {
        if !hunterSavedPath.isEmpty {
            harvestTitle = Self.foragePrettyTitle(path: hunterSavedPath)
        } else {
            harvestTitle = L("FORAGE")
        }
        let raw = harvestWorkingText()
        if raw.isEmpty {
            harvestLines = [PreviewLine(id: 0, text: L("Nothing foraged yet."))]
            harvestHeadings = []
            return
        }
        let pack = Self.packFromText(raw, base: FileManager.default.temporaryDirectory, scanHeadings: true)
        harvestLines = pack.lines
        harvestHeadings = pack.headings
        scrollHarvestToLatest()
    }

    func scrollHarvestToLatest() {
        guard harvestOpen, let last = harvestLines.last?.id else { return }
        if harvestLines.count == 1, harvestLines[0].text == L("Nothing foraged yet.") { return }
        if harvestScrollLine == last { harvestScrollLine = nil }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard self.harvestOpen else { return }
            self.harvestScrollLine = last
        }
    }

    private func harvestWorkingText() -> String {
        let live = hunterBoardText.trimmingCharacters(in: .whitespacesAndNewlines)
        if forageBaseBody.isEmpty { return live }
        if live.isEmpty { return forageBaseBody }
        return forageBaseBody + "\n\n---\n\n" + live
    }

    private func harvestSavedBody() -> String {
        guard let url = existingHarvestURL() else { return "" }
        let raw = AppModel.readMarkdownPrefix(path: url.path, maxBytes: 280_000)?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Self.stripForageChrome(raw)
    }

    private func existingHarvestURL() -> URL? {
        guard !hunterSavedPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: hunterSavedPath)
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return url
    }

    var forageEditURL: URL? {
        guard harvestOpen else { return nil }
        return existingHarvestURL()
    }

    static func sameFilePath(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return URL(fileURLWithPath: a).standardizedFileURL.path
            == URL(fileURLWithPath: b).standardizedFileURL.path
    }

    private func forageCard() -> LibraryItem? {
        if let id = hunterSavedID, let card = library.first(where: { $0.id == id }) {
            return card
        }
        if !hunterSavedPath.isEmpty {
            return library.first(where: { Self.sameFilePath($0.markdownPath, hunterSavedPath) })
        }
        return nil
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func isForageItem(_ item: LibraryItem) -> Bool {
        Self.isForagePath(item.markdownPath) || item.sourceName == "FORAGE"
    }

    func forageSourcePaths() -> Set<String> {
        var paths = Set<String>()
        for path in hunterGatheredByPath.keys where !path.isEmpty {
            paths.insert(standardizedPath(path))
        }
        if let card = forageCard() {
            for mark in card.forageMarks where !mark.sourcePath.isEmpty {
                paths.insert(standardizedPath(mark.sourcePath))
            }
        }
        for title in forageCitedSourceTitles() {
            if let path = libraryPath(matchingTitle: title) {
                paths.insert(standardizedPath(path))
            }
        }
        return paths
    }

    func forageHasMultipleSources() -> Bool {
        forageSourcePaths().count > 1
    }

    func soleForageSourcePath() -> String? {
        let paths = forageSourcePaths()
        if paths.count == 1 { return paths.first }
        if !paths.isEmpty { return nil }
        let titles = Set(forageCitedSourceTitles().map { $0.lowercased() })
        guard titles.count == 1,
              let current = library.first(where: { $0.id == selectedLibraryID }),
              !isForageItem(current),
              titles.contains(current.title.lowercased())
        else { return nil }
        return current.markdownPath
    }

    private func libraryPath(matchingTitle title: String) -> String? {
        let hits = library.filter {
            !isForageItem($0) && $0.title.caseInsensitiveCompare(title) == .orderedSame
        }
        let unique = Set(hits.map { standardizedPath($0.markdownPath) })
        return unique.count == 1 ? unique.first : nil
    }

    private func forageCitedSourceTitles() -> [String] {
        var titles: [String] = []
        for row in harvestLines {
            let t = row.text.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("*"), t.hasSuffix("*"), t.count > 2 else { continue }
            var inner = String(t.dropFirst().dropLast())
            var hasPage = false
            if let cut = inner.range(of: " · Page ", options: .caseInsensitive) {
                inner = String(inner[..<cut.lowerBound])
                hasPage = true
            }
            inner = inner.trimmingCharacters(in: .whitespaces)
            guard !inner.isEmpty else { continue }
            if hasPage || library.contains(where: {
                !isForageItem($0) && $0.title.caseInsensitiveCompare(inner) == .orderedSame
            }) {
                titles.append(inner)
            }
        }
        return titles
    }

    func canForageLink() -> Bool {
        guard harvestOpen, !hunterOn, !sideBySide else { return false }
        guard let source = soleForageSourcePath() else { return false }
        return Self.sameFilePath(source, currentReaderPath)
    }

    func updateForageSync(autoOn: Bool) {
        guard canForageLink() else {
            stopForageLink()
            return
        }
        let wasOff = !forageLinkActive
        forageLinkActive = true
        refreshLinkedTitles()
        if autoOn, !forageLinkUserOff {
            linkScroll = true
            if linkMaster != .main && linkMaster != .harvest {
                linkMaster = .main
            }
            if wasOff {
                ignoreHarvestLead(for: 1.5)
                statusText = L("SyncScroll is on — reader and FORAGE")
            }
        }
    }

    func stopForageLink() {
        guard forageLinkActive else { return }
        forageLinkActive = false
        if !sideBySide {
            linkedHeading = ""
            clearHarvestHeading()
            if linkMaster == .harvest { linkMaster = .main }
        }
    }

    var hunterBoardText: String {
        hunterSnippets.joined(separator: "\n\n---\n\n")
    }

    func hunterReaderText(from lines: [PreviewLine]) -> String {
        let key = lines.count
            &+ (lines.first?.id ?? 0)
            &+ ((lines.last?.id ?? 0) &* 1_009)
            &+ (lines.first?.text.hashValue ?? 0)
        if let hit = hunterTextMemo[key] { return hit }
        var parts: [String] = []
        parts.reserveCapacity(lines.count)
        for row in lines {
            if let page = Self.pageToken(row.text) { parts.append("Page \(page)") }
            else {
                let t = row.text.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("<!--") { continue }
                parts.append(row.text)
            }
        }
        let text = parts.joined(separator: "\n")
        if hunterTextMemo.count > 4 { hunterTextMemo.removeAll(keepingCapacity: true) }
        hunterTextMemo[key] = text
        return text
    }

    func startHunterMonitor() {
        stopHunterMonitor()
        hunterMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.hunterOn else { return event }
            if event.keyCode == 36 || event.keyCode == 76 {
                if self.gatherSelectedText() { return nil }
            }
            return event
        }
    }

    func stopHunterMonitor() {
        if let hunterMonitor {
            NSEvent.removeMonitor(hunterMonitor)
        }
        hunterMonitor = nil
    }

    func startAskNavMonitor() {
        guard askNavMonitor == nil else { return }
        askNavMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleAskNavKey(event) ?? event
        }
    }

    private func handleAskNavKey(_ event: NSEvent) -> NSEvent? {
        guard askHitsInReader.count > 1, !askAnswer.isEmpty else { return event }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        guard mods.isEmpty else { return event }
        if event.specialKey == .leftArrow || event.keyCode == 123 {
            prevAskHit()
            return nil
        }
        if event.specialKey == .rightArrow || event.keyCode == 124 {
            nextAskHit()
            return nil
        }
        return event
    }

    @discardableResult
    func gatherSelectedText() -> Bool {
        guard hunterOn else { return false }
        guard let hit = selectedHunterHit() else {
            statusText = L("Select text in the reader, then press Enter.")
            return false
        }
        let snippet = formatHunterSnippet(hit.text)
        hunterSnippets.append(snippet)
        let path = currentReaderPath
        if !path.isEmpty {
            hunterGatheredByPath[path, default: []].append(hit.range)
            hunterGatheredRanges = hunterGatheredByPath[path] ?? []
        } else {
            hunterGatheredRanges.append(hit.range)
        }
        hit.view.setSelectedRange(NSRange(location: hit.range.location + hit.range.length, length: 0))
        paintHunterReader(hit.view)
        hunterMarkStamp += 1
        if harvestOpen { refreshHarvest() }
        Task { @MainActor in
            self.writeForageFile()
            self.scheduleForageAutosave()
            self.syncHunterPasteboard()
        }
        if existingHarvestURL() != nil {
            statusText = L("Added — will save into this FORAGE file.")
        } else {
            let n = hunterSnippets.count
            statusText = n == 1
                ? L("Added 1 piece to HUNTER-GATHERER.")
                : "HUNTER-GATHERER: \(n) " + L("pieces on the board.")
        }
        return true
    }

    func gatherPassage(_ passage: String, question: String = "") {
        guard !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var snippet = formatHunterSnippet(passage)
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            if let r = snippet.range(of: "\n\n") {
                snippet.insert(contentsOf: "**Q:** \(q)\n\n", at: r.upperBound)
            } else {
                snippet = "**Q:** \(q)\n\n" + snippet
            }
        }
        hunterSnippets.append(snippet)
        hunterMarkStamp += 1
        if harvestOpen { refreshHarvest() }
        Task { @MainActor in
            self.writeForageFile()
            self.scheduleForageAutosave()
            self.syncHunterPasteboard()
        }
        if existingHarvestURL() != nil {
            statusText = L("Added — will save into this FORAGE file.")
        } else {
            statusText = L("Added 1 piece to HUNTER-GATHERER.")
        }
    }

    private func selectedHunterHit() -> (view: NSTextView, range: NSRange, text: String)? {
        var views: [NSTextView] = []
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView {
            views.append(tv)
        }
        if let root = NSApp.keyWindow?.contentView {
            collectTextViews(root, into: &views)
        }
        for tv in views {
            let range = tv.selectedRange()
            guard range.length > 0, range.location != NSNotFound else { continue }
            let raw = (tv.string as NSString).substring(with: range)
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if tv.isFieldEditor, (tv.string as NSString).length < 160 { continue }
            return (tv, range, text)
        }
        return nil
    }

    func paintHunterReader(_ tv: NSTextView) {
        let plan = hunterHighlightPlan(in: previewLines)
        Self.paintHunterMarks(tv, ranges: hunterGatheredRanges, search: plan.all, current: plan.current)
    }

    static func paintHunterMarks(_ tv: NSTextView, ranges: [NSRange], search: [NSRange] = [], current: [NSRange] = []) {
        let len = (tv.string as NSString).length
        guard len > 0, let storage = tv.textStorage else { return }
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: len))
        let dark = tv.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            || NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let searchColor = NSColor(calibratedRed: 1, green: 0.93, blue: 0.2, alpha: dark ? 0.38 : 0.45)
        let currentColor = NSColor(calibratedRed: 1, green: 0.93, blue: 0.2, alpha: dark ? 0.62 : 0.72)
        let gatheredColor = NSColor.systemGreen.withAlphaComponent(dark ? 0.080 : 0.308)
        func paint(_ marks: [NSRange], color: NSColor) {
            for r in marks {
                let end = min(r.location + r.length, len)
                guard r.location >= 0, r.location < end else { continue }
                storage.addAttribute(.backgroundColor, value: color, range: NSRange(location: r.location, length: end - r.location))
            }
        }
        paint(search, color: searchColor)
        paint(current, color: currentColor)
        paint(ranges, color: gatheredColor)
        storage.endEditing()
    }

    private func collectTextViews(_ view: NSView, into bag: inout [NSTextView]) {
        if let tv = view as? NSTextView, !bag.contains(where: { $0 === tv }) {
            bag.append(tv)
        }
        for child in view.subviews {
            collectTextViews(child, into: &bag)
        }
    }

    func syncHunterPasteboard() {
        let body = harvestWorkingText()
        guard !body.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
    }

    func formatHunterSnippet(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let chapter = activeHeading(for: .main)
        let page = pageNearSelection(cleaned)
        let source = library.first(where: { $0.id == selectedLibraryID })?.title ?? ""
        var parts: [String] = []
        if !chapter.isEmpty {
            parts.append("### \(chapter)")
            parts.append("")
        }
        parts.append(cleaned)
        var cite: [String] = []
        if !source.isEmpty { cite.append(source) }
        if let page, !page.isEmpty { cite.append("Page \(page)") }
        if !cite.isEmpty {
            parts.append("")
            parts.append("*\(cite.joined(separator: " · "))*")
        }
        return parts.joined(separator: "\n")
    }

    private func pageNearSelection(_ selected: String) -> String? {
        let needle = String(selected.prefix(48))
        let idx = previewLines.firstIndex(where: { $0.text.contains(needle) })
            ?? previewLines.firstIndex(where: { selected.contains($0.text) && $0.text.count > 12 })
        guard let idx else { return nil }
        for i in stride(from: idx, through: 0, by: -1) {
            if let page = Self.pageToken(previewLines[i].text) { return page }
        }
        return nil
    }

    private static func pageToken(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("<!-- page "), t.hasSuffix("-->") else { return nil }
        let inner = t.dropFirst(10).dropLast(3).trimmingCharacters(in: .whitespaces)
        return inner.isEmpty ? nil : inner
    }

    func finishHunterGatherer(showSheet: Bool = false) {
        writeForageFile()
        if showSheet, existingHarvestURL() != nil {
            showHunterSaved = true
        }
    }

    func writeForageFile() {
        let body = harvestWorkingText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let creating = forageSessionIsNew || existingHarvestURL() == nil
        if creating {
            forageSessionStamp = forageSessionStamp.isEmpty ? Self.forageFileStamp() : forageSessionStamp
        } else if forageSessionStamp.isEmpty {
            forageSessionStamp = stampFromForagePath(hunterSavedPath)
        }
        var stamp = forageSessionStamp
        let url: URL
        if creating {
            try? FileManager.default.createDirectory(at: forageHome, withIntermediateDirectories: true)
            var candidate = forageHome.appendingPathComponent("\(stamp)_forage.md")
            if isDeletedForage(candidate.path) {
                stamp = Self.forageFileStamp()
                forageSessionStamp = stamp
                candidate = forageHome.appendingPathComponent("\(stamp)_forage.md")
            }
            url = candidate
        } else if let existing = existingHarvestURL() {
            if isDeletedForage(existing.path) { return }
            url = existing
        } else {
            return
        }
        let title = Self.foragePrettyTitle(stamp: stamp)
        let markdown = """
        \(Self.forageMarker)

        # \(title)

        \(body)
        """
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            statusText = error.localizedDescription
            return
        }
        quietWatch(6)
        rememberDiskFingerprint(path: url.path, text: markdown)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        if creating {
            let item = insertLibraryItem(
                source: url,
                markdown: url,
                bookmarks: [],
                title: title
            )
            if let idx = library.firstIndex(where: { $0.id == item.id }) {
                library[idx].sourceName = "FORAGE"
            }
            rememberForageFile(id: item.id, path: url.path)
            forageSessionIsNew = false
            forageVaultOpen = true
            persistForageMarks()
        } else {
            if let idx = library.firstIndex(where: { $0.markdownPath == url.path }) {
                library[idx].byteCount = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        statusText = creating
            ? L("Saved your gathered notes")
            : L("Added to the same FORAGE file.")
    }

    var currentReaderPath: String {
        library.first(where: { $0.id == selectedLibraryID })?.markdownPath ?? ""
    }

    func stampFromForagePath(_ path: String) -> String {
        var stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        if stem.lowercased().hasSuffix("_forage") {
            stem = String(stem.dropLast(7))
        }
        return stem
    }

    static func stripForageChrome(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix(forageMarker) {
            t = String(t.dropFirst(forageMarker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if t.hasPrefix("# ") {
            if let nl = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: nl)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                t = ""
            }
        }
        return t
    }

    func persistForageMarks() {
        guard let id = hunterSavedID, let idx = library.firstIndex(where: { $0.id == id }) else { return }
        library[idx].forageMarks = hunterGatheredByPath.flatMap { path, ranges in
            ranges.map { ForageMarkSpan(sourcePath: path, location: $0.location, length: $0.length) }
        }
        saveLibrary()
    }

    func applyForageCardMarks(for sourcePath: String) {
        guard !sourcePath.isEmpty else { return }
        let card = hunterSavedID.flatMap { id in library.first(where: { $0.id == id }) }
            ?? library.first(where: { $0.markdownPath == hunterSavedPath })
        guard let card else { return }
        let extra = card.forageMarks
            .filter { $0.sourcePath == sourcePath }
            .map { NSRange(location: max(0, $0.location), length: max(0, $0.length)) }
        guard !extra.isEmpty else { return }
        var have = hunterGatheredByPath[sourcePath] ?? []
        for r in extra where !have.contains(where: { $0.location == r.location && $0.length == r.length }) {
            have.append(r)
        }
        hunterGatheredByPath[sourcePath] = have
        if currentReaderPath == sourcePath {
            hunterGatheredRanges = have
            hunterMarkStamp += 1
        }
    }

    func scheduleForageAutosave() {
        guard forageAutosaveTask == nil else { return }
        forageAutosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            self.writeForageFile()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000_000)
                guard !Task.isCancelled, self.hunterOn else { break }
                self.writeForageFile()
            }
            self.forageAutosaveTask = nil
        }
    }

    func cancelForageAutosave() {
        forageAutosaveTask?.cancel()
        forageAutosaveTask = nil
    }

    func hunterCharOffset(forLine line: Int, in lines: [PreviewLine]) -> Int {
        hunterLineMap(from: lines).first(where: { $0.id == line })?.offset ?? 0
    }

    func hunterLineMap(from lines: [PreviewLine]) -> [(id: Int, offset: Int)] {
        let key = lines.count
            &+ (lines.first?.id ?? 0)
            &+ ((lines.last?.id ?? 0) &* 1_009)
            &+ (lines.first?.text.hashValue ?? 0)
        if hunterLineMemo?.key == key { return hunterLineMemo!.map }
        var map: [(id: Int, offset: Int)] = []
        map.reserveCapacity(lines.count)
        var offset = 0
        for row in lines {
            if let page = Self.pageToken(row.text) {
                map.append((row.id, offset))
                offset += (("Page \(page)" as NSString).length + 1)
            } else {
                let t = row.text.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("<!--") { continue }
                map.append((row.id, offset))
                offset += ((row.text as NSString).length + 1)
            }
        }
        hunterLineMemo = (key, map)
        return map
    }

    func rememberForageFile(id: UUID?, path: String) {
        hunterSavedID = id
        hunterSavedPath = path
        UserDefaults.standard.set(path, forKey: "hunterSavedPath")
        UserDefaults.standard.set(id?.uuidString ?? "", forKey: "hunterSavedID")
    }

    func isOpenForage(_ item: LibraryItem) -> Bool {
        if let id = hunterSavedID, id == item.id { return true }
        if Self.sameFilePath(hunterSavedPath, item.markdownPath) { return true }
        if !forageSessionStamp.isEmpty, stampFromForagePath(item.markdownPath) == forageSessionStamp {
            return true
        }
        return false
    }

    func forgetOpenForageSession(keepLiveBoard: Bool) {
        cancelForageAutosave()
        rememberForageFile(id: nil, path: "")
        forageSessionStamp = ""
        forageSessionIsNew = true
        forageBaseBody = ""
        if !keepLiveBoard {
            hunterSnippets = []
            hunterGatheredByPath = [:]
            hunterGatheredRanges = []
            hunterMarkStamp += 1
        }
        if harvestOpen { refreshHarvest() }
    }

    private func standardizedForagePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func isDeletedForage(_ path: String) -> Bool {
        let key = standardizedForagePath(path)
        return deletedForagePaths.contains { standardizedForagePath($0) == key }
    }

    func rememberDeletedForage(_ path: String) {
        let key = standardizedForagePath(path)
        guard !key.isEmpty else { return }
        deletedForagePaths.removeAll { standardizedForagePath($0) == key }
        deletedForagePaths.append(key)
        if deletedForagePaths.count > 200 {
            deletedForagePaths.removeFirst(deletedForagePaths.count - 200)
        }
        UserDefaults.standard.set(deletedForagePaths, forKey: "deletedForagePaths")
    }

    var hasLastForage: Bool {
        existingHarvestURL() != nil
    }

    func openLastForage() {
        guard hasLastForage else {
            statusText = L("No FORAGE file yet.")
            return
        }
        harvestOpen = true
        refreshHarvest()
        updateForageSync(autoOn: !forageLinkUserOff)
        statusText = L("Opened the last FORAGE file.")
    }

    func openForageInPanel(_ item: LibraryItem) {
        rememberForageFile(id: item.id, path: item.markdownPath)
        forageSessionIsNew = false
        forageSessionStamp = stampFromForagePath(item.markdownPath)
        forageBaseBody = harvestSavedBody()
        harvestOpen = true
        if hunterOn {
            applyForageCardMarks(for: currentReaderPath)
        } else if !currentReaderPath.isEmpty {
            applyForageCardMarks(for: currentReaderPath)
        }
        refreshHarvest()
        updateForageSync(autoOn: !forageLinkUserOff)
        statusText = L("Opened a FORAGE note.")
    }

    func openHunterSavedFile() {
        showHunterSaved = false
        if let id = hunterSavedID, let item = library.first(where: { $0.id == id }) {
            selectLibrary(item)
        } else if !hunterSavedPath.isEmpty {
            reveal(URL(fileURLWithPath: hunterSavedPath))
        }
    }

    func dismissHunterSaved() {
        showHunterSaved = false
    }

    static let forageMarker = "<!-- yourmark forage -->"

    static func forageFileStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH_mm_ss"
        return f.string(from: Date())
    }

    static func foragePrettyTitle(stamp: String) -> String {
        let parts = stamp.split(separator: "_")
        if parts.count >= 4 {
            return "\(parts[0]) \(parts[1]).\(parts[2]).\(parts[3])"
        }
        return stamp.replacingOccurrences(of: "_", with: " ")
    }

    static func foragePrettyTitle(path: String) -> String {
        var stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        if stem.lowercased().hasSuffix("_forage") {
            stem = String(stem.dropLast(7))
        }
        return foragePrettyTitle(stamp: stem)
    }

    static func isForagePath(_ path: String) -> Bool {
        path.lowercased().hasSuffix("_forage.md")
    }

    var forageVaultItems: [LibraryItem] {
        library
            .filter { Self.isForagePath($0.markdownPath) || $0.sourceName == "FORAGE" }
            .sorted { $0.addedAt > $1.addedAt }
    }

    func scanForageVault() {
        let urls = forageScanRoots().flatMap { root in
            (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }
        var added = false
        for url in urls where url.pathExtension.lowercased() == "md" {
            guard Self.looksLikeForage(url: url) else { continue }
            if isDeletedForage(url.path) { continue }
            if library.contains(where: { $0.markdownPath == url.path }) { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            library.append(LibraryItem(
                id: UUID(),
                title: Self.foragePrettyTitle(path: url.path),
                sourceName: "FORAGE",
                markdownPath: url.path,
                addedAt: values?.contentModificationDate ?? Date(),
                byteCount: Int64(values?.fileSize ?? 0),
                bookmarks: [],
                sourcePath: url.path
            ))
            added = true
        }
        if added {
            saveLibrary()
        }
    }

    static func looksLikeForage(url: URL) -> Bool {
        if url.lastPathComponent.lowercased().hasSuffix("_forage.md") { return true }
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return false }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 96)
        return String(data: data, encoding: .utf8)?.contains("yourmark forage") == true
    }
}

/// One selectable reader so click-and-drag can cover as much text as you like.
struct HunterSelectView: NSViewRepresentable {
    var text: String
    var pointSize: Double
    var ink: NSColor
    var paper: NSColor
    var gathered: [NSRange]
    var markStamp: Int
    var searchMarks: [NSRange] = []
    var currentMarks: [NSRange] = []
    var searchStamp: Int = 0
    var scrollChar: Int?
    var scrollStamp: Int
    var lineMap: [(id: Int, offset: Int)]
    var onTopLine: (Int) -> Void
    var selectChar: Int? = nil
    var selectLength: Int = 0
    var selectStamp: Int = 0

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = paper
        scroll.contentView.postsBoundsChangedNotifications = true
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.importsGraphics = false
        tv.drawsBackground = true
        tv.backgroundColor = paper
        tv.textColor = ink
        tv.font = NSFont.systemFont(ofSize: pointSize)
        tv.string = text
        context.coordinator.appliedLength = (text as NSString).length
        AppModel.paintHunterMarks(tv, ranges: gathered, search: searchMarks, current: currentMarks)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainerInset = NSSize(width: 16, height: 14)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 6
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width]
        tv.usesFindBar = false
        scroll.documentView = tv
        context.coordinator.observe(scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        scroll.backgroundColor = paper
        guard let tv = scroll.documentView as? NSTextView else { return }
        tv.backgroundColor = paper
        tv.textColor = ink
        tv.font = NSFont.systemFont(ofSize: pointSize)
        context.coordinator.lineMap = lineMap
        context.coordinator.onTopLine = onTopLine
        let next = (text as NSString).length
        if context.coordinator.appliedLength != next {
            tv.string = text
            context.coordinator.appliedLength = next
            AppModel.paintHunterMarks(tv, ranges: gathered, search: searchMarks, current: currentMarks)
        }
        if context.coordinator.paintedStamp != markStamp || context.coordinator.searchStamp != searchStamp {
            context.coordinator.paintedStamp = markStamp
            context.coordinator.searchStamp = searchStamp
            AppModel.paintHunterMarks(tv, ranges: gathered, search: searchMarks, current: currentMarks)
        }
        if context.coordinator.scrollStamp != scrollStamp, let scrollChar {
            context.coordinator.scrollStamp = scrollStamp
            let maxLen = (tv.string as NSString).length
            if maxLen > 0 {
                let loc = min(max(0, scrollChar), maxLen - 1)
                tv.scrollRangeToVisible(NSRange(location: loc, length: 1))
            }
        }
        if context.coordinator.selectStamp != selectStamp, let selectChar {
            context.coordinator.selectStamp = selectStamp
            let maxLen = (tv.string as NSString).length
            if maxLen > 0, selectChar >= 0, selectChar < maxLen {
                let loc = selectChar
                tv.scrollRangeToVisible(NSRange(location: loc, length: 1))
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var appliedLength = -1
        var scrollStamp = -1
        var paintedStamp = -1
        var searchStamp = -1
        var selectStamp = -1
        var lastTopLine: Int?
        var lineMap: [(id: Int, offset: Int)] = []
        var onTopLine: ((Int) -> Void)?
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        func observe(_ scroll: NSScrollView) {
            guard observer == nil else { return }
            scroll.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView,
                queue: .main
            ) { [weak self, weak scroll] _ in
                guard let self, let scroll else { return }
                self.reportTop(scroll)
            }
        }

        func reportTop(_ scroll: NSScrollView) {
            guard let tv = scroll.documentView as? NSTextView else { return }
            let visible = tv.visibleRect
            var char = 0
            if let lm = tv.layoutManager, let container = tv.textContainer {
                let point = NSPoint(x: visible.minX + 8, y: visible.minY + 8)
                let glyph = lm.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: nil)
                char = lm.characterIndexForGlyph(at: glyph)
            }
            if let line = lineMap.last(where: { $0.offset <= char })?.id, line != lastTopLine {
                lastTopLine = line
                onTopLine?(line)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
