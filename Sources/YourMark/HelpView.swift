import AppKit
import SwiftUI

struct HelpView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.deck) private var deck

    private struct Topic: Identifiable {
        let title: String
        let cards: [(title: String, body: String)]
        var id: String { title }
    }

    private var topics: [Topic] {
        var start: [(String, String)] = [
            (
                "Why Markdown",
                "A PDF is a picture of a page.\nMarkdown is the words, in order.\nA model can quote a chapter — or admit the answer is not there, instead of guessing at a scan.\nKeep the original PDF."
            ),
        ]
        // GitHub disk only. App Store users never open a notarized disk image.
        if !Distribution.isAppStore {
            start.append((
                "First open",
                "This disk is signed and notarized by Apple.\nThe first open may ask — click Open."
            ))
        }
        start.append((
            "Keep the original",
            "Converted Markdown is for search and study.\nKeep the original PDF or Word file."
        ))
        start.append((
            "yourMark folder",
            "Where should yourMark keep your files?\nConverted Markdown and forage notes go in the folder you pick. That can be on this Mac, in iCloud, or anywhere you like. iCloud is safer if this Mac dies. The author is not responsible for lost data.\nThen You’re ready: Ask AI keys and extra tools are in Settings.\nYou only see this once. Change the folder later in Settings → Converted files."
        ))
        start.append((
            "Interface",
            "Settings → Interface: US English, Spanish, or Dutch.\nAn Ask AI key can add more languages.\nA missing phrase stays English, so a bad translation cannot brick the window.\nIf a new language crashes, the next launch is US English.\nSpanish and Dutch are fully integrated."
        ))

        var convert: [(String, String)] = []
        if Distribution.isAppStore {
            convert.append((
                "Engine",
                "This copy includes a converter that turns PDFs into Markdown.\nThat makes the words easier to read, search, and edit in a Markdown editor.\nWord and PowerPoint convert the same way.\nPhotographed pages use Apple Live Text, already on this Mac.\nNothing extra is downloaded.\nKeep the original file."
            ))
        } else {
            convert.append((
                "Engine",
                "First launch installs Microsoft MarkItDown from PyPI.\nConvert stays on this Mac.\nAbout once a day we check for their updates."
            ))
            convert.append((
                "Scanned PDFs",
                "A scan has no text layer.\nSettings: Apple Live Text, or IBM Docling for better tables (a large download).\nKeep a searchable PDF writes Manual.searchable.pdf next to the Markdown — the original pages with words underneath.\nOrdinary digital PDFs still go to MarkItDown."
            ))
            convert.append((
                "Searchable PDF",
                "Settings → Keep a searchable PDF, or SAVE OCR PDF in the bar, writes Manual.searchable.pdf next to the Markdown.\nA long scan can take minutes. It does not use Ask AI credits.\nIt uses OCRmyPDF (Tesseract), the optional backup scanner in Settings.\nOriginal pages with words underneath — not a new PDF from edited or translated Markdown."
            ))
        }
        convert += [
            (
                "Tables",
                "Real tables become Markdown tables.\nColours and merged cells flatten.\nDrawn “tables” that are only lines often become plain rows."
            ),
            (
                "Pictures",
                "Pictures live in a figures folder next to the Markdown.\nThe file only points at them, so it stays small for you and for AI."
            ),
            (
                "Picture links",
                "In the reader a picture is a blue link, not the photo.\nRest the pointer on it for a preview (the photo slider sets how big).\nClick opens Finder on that file.\nRight-click opens Preview so you can rotate it — the hover updates.\nPictures are not loaded while you scroll."
            ),
            (
                "Bookmarks",
                "The PDF’s own outline becomes Markdown headings — we keep that tree.\nThe item at the top of the page lights, including sub-chapters.\nA large tree starts collapsed.\nNo outline: large-font lines, then AI only if you tick it.\nTo change the tree, press Edit and open the Markdown in MarkEdit (or the editor you picked).\nThe bookmarks are the heading lines — #, ##, ###.\nRename, add, or delete those. More # marks means a lower level."
            ),
        ]

        let library: [(String, String)] = [
            (
                "Add existing Markdown",
                "A .md file skips the converter.\nFile → Open… adds it.\nA drop on the yourMark window adds it.\nIn Finder, put the file in the watched folder — Settings → Converted files → Choose a folder…. That folder is watched: a new .md there appears in the library at once.\nThe file stays in that folder as itself. No convert little-folder.\nIf it is already there, we only add the card.\nIf you use On this Mac only, that hidden Application Support folder is the one watched."
            ),
            (
                "Library cards",
                "Translations sit under the original — they do not use a new slot.\nDrag the grip on a group to rearrange, or right-click Move group up / down. A translation cannot leave its original.\nThe list holds 100 groups; the one you have not opened for longest leaves the list, files stay on disk.\nSearch title filters cards on this Mac — titles, and #tags on the card. With an Ask AI key it can also take what you mean (titles only).\nAsk answers from the open file, or from cards with the tags you pick.\nManual sort is your drag order.\nThe double chevron on the sort bar hides the card list; a thin strip brings it back. Each launch starts Library open, sorted Date newest.\nRight-click Delete on a translation removes only that card. On the original, you choose that card only or the original and its translations."
            ),
            (
                "Tags",
                "Tags sit on the library card, not in the Markdown. Headings already use #.\nRight-click a card → Add tag…. Type a name or click one you already made.\nCards show #aviation next to new.\nThe tag button on the sort bar filters the list. Several tags at once means all of them.\nTag sort is A–Z by first tag.\nSearch title finds #tags. Search in files still only reads the words in the file."
            ),
            (
                "Share with AI",
                "Right-click a card → Show in Finder.\nIf the file has pictures, Finder highlights the little folder — the one that contains the Markdown and a figures folder. Right-click that folder → Compress. Do not compress only the .md file, or the pictures stay behind.\nIf there are no pictures, Finder highlights the Markdown itself — compress that file.\nUpload the zip to ChatGPT, Grok, or another model. The original PDF stays where it is."
            ),
            (
                "Shortcuts and scripts",
                "A Shortcut or Terminal can convert with yourmark://convert?file=/Users/you/Manual.pdf — full path after file=."
            ),
        ]

        let reading: [(String, String)] = [
            (
                "Reading",
                "The photo slider sets hover preview size.\nSearch in files stays on this Mac — not sent to Ask.\nBoolean search: AND, OR, NOT must be capitals — same in Search in files and in Ask. Words must sit in the same sentence or paragraph, not anywhere in the chapter. Quotes keep a phrase together. Example: flaps AND landing NOT ice, or \"landing gear\" OR slats.\nMatching cards stay in the list. The first matching card opens on the first hit in that Markdown.\nA large file loads up to about 40,000 lines (2 MB). Ask and Translate still use a shorter prefix so a whole-file send does not surprise you.\nSettings → Reader: font, and whether Bright is paper or plain white.\nWe recommend Atkinson Hyperlegible. Use Apple Font Book to install this free font."
            ),
            (
                "Hunter-Gatherer",
                "Select text and press Enter.\nEach piece keeps its chapter and page.\nThe first Enter creates a dated note and copies it.\nIt also writes after about a minute while you gather.\nClose writes and shuts the panel.\nAdd more keeps going into the open note.\nNotes are date_forage.md in your folder, with a hidden mark so they can be found if you rename them.\nForage Vault lists older notes — a click opens FORAGE, not the reader.\nPicture links leave the reader while you gather.\nWhen Hunter-Gatherer is off, SyncScroll turns on if every clip came from one file.\nClips from several files leave it off.\nAfter Ask, Add displayed Search Result to Forage keeps the line you found — and your question — on today’s note."
            ),
            (
                "Editors",
                "yourMark does not edit files.\nEdit opens one file beside the window — original or translation, never both.\nSIDE BY SIDE turns off so you can see the file you picked.\nMarkEdit is the Mac default.\nMarkText is the free one we like on Windows."
            ),
            (
                "App Management",
                "Apple may ask for App Management when you press Edit.\nThat only opens the file in the editor you picked.\nIf Edit does nothing, turn yourMark on in System Settings → Privacy & Security → App Management."
            ),
            (
                "Ask chapter",
                "Paste a Grok or OpenAI key in Settings.\nWe test it once and lock it on this Mac.\nAsk answers from the open file — the chapter you pick, or Entire file.\nEntire file still only sends the start of that file, not every library card.\nAsk uses the same boolean search as Search in files. AND, OR, and NOT must be capitals. Words must sit in the same sentence or paragraph, not anywhere in the chapter. Quotes keep a phrase together. Example: flaps AND landing NOT ice.\nThose operators find matching paragraphs (or tagged cards). Those are the hits you step through. Matching passages are what Ask sends.\nSearch in files finds words in all cards on this Mac and is never sent to Ask.\nSearch title can use Ask AI on titles only.\nIf this file does not have the answer, Search the web is there.\nRecent Asks stay on this Mac. Open them from the clock next to the model name.\nClear searches next to that clock empties that list. Clear only empties the current pane.\nDrag the Ask header up or down to change its height. The double chevron folds Ask to the bottom.\nShow in file jumps to the line the answer came from.\nAdd displayed Search Result to Forage puts that passage and your question on today’s note.\nPick #tags next to the chapter to ask across those cards only. That still sends short excerpts, not every file."
            ),
        ]

        let translate: [(String, String)] = [
            (
                "Translate",
                "Translate appears when you lock an Ask AI key or a Google Translate key.\nEngine in Settings picks which one.\nThis chapter is the cheap way.\nEntire file on a large manual can cost a lot — the reader only shows the start, so a file can look short.\nBelow each paragraph keeps the original; Replace shows only the translation.\nBookmarks stay the original PDF tree — titles are translated; Translate does not invent a new outline.\nSave a copy writes a second file.\nThe original is not overwritten."
            ),
            (
                "SIDE BY SIDE",
                "Press SIDE BY SIDE. A translation under the card opens beside it.\nSeveral languages: click one. A toast tells you. No OK box.\nIf the window is too narrow, drag it wider, turn the text slider down (A … A), or hide Library with the double chevron.\n⌘-click two cards that share an origin still works.\nSyncScroll starts on so headings stay together. Click it to scroll each file on its own.\nClick a pane or a bookmark to pick who leads — hovering does not steal the lead.\nEdit is one language at a time.\nFORAGE can SyncScroll with its source when Hunter-Gatherer is off and every clip came from one file."
            ),
        ]

        let support: [(String, String)] = [
            (
                "Your files",
                "Converted Markdown and forage notes live in the folder you chose.\nOn this Mac only is a hidden Application Support folder — it should not grow if you picked iCloud.\niCloud keeps a copy off this Mac.\nThe author is not responsible for lost data."
            ),
            (
                "Crash reports",
                Distribution.isAppStore
                    ? "Apple already collects crashes for this App Store copy.\nYou do not need to send anything.\nSettings can email a report if you want to add a note."
                    : "If yourMark closes unexpectedly, we can copy the macOS report.\nPaste it in a message if you want. Nothing is sent in the background.\nSettings can turn the offer off."
            ),
            (
                "yourmark://",
                "Finder Share or Services can hand a PDF to yourMark — the app opens if it is closed.\nA Shortcut or Terminal can do the same: yourmark://convert?file=/Users/you/Manual.pdf\nFull path after file=. Dropping a PDF on the window still works."
            ),
            (
                "Support page",
                Distribution.isAppStore
                    ? "The same page as Settings → Support."
                    : "Questions and contact."
            ),
        ]

        return [
            Topic(title: "Start", cards: start),
            Topic(title: "Convert", cards: convert),
            Topic(title: "Library", cards: library),
            Topic(title: "READER, HUNTER GATHERING AND FORAGE", cards: reading),
            Topic(title: "Translate", cards: translate),
            Topic(title: "Support", cards: support),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(topics) { topic in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.L(topic.title))
                            .font(.system(.title2, design: .rounded).bold())
                            .foregroundStyle(deck.cyan)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)],
                            spacing: 12
                        ) {
                            ForEach(Array(topic.cards.enumerated()), id: \.offset) { _, card in
                                helpCard(
                                    model.L(card.title),
                                    model.L(card.body),
                                    linkLabel: card.title == "Support page"
                                        ? model.L("Open support page")
                                        : nil,
                                    linkURL: card.title == "Support page"
                                        ? Distribution.supportURL
                                        : nil,
                                    folderLink: card.title == "Add existing Markdown"
                                        ? watchedFolderLink()
                                        : nil
                                )
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(deck.ink)
        }
        .background(deck.page)
        .overlay(alignment: .bottomTrailing) {
            VersionStamp()
        }
    }

    private func watchedFolderLink() -> (name: String, url: URL)? {
        guard model.filePlace == "custom", !model.customFolderPath.isEmpty else { return nil }
        let url = FolderAccess.accessPath(model.customFolderPath)
            ?? URL(fileURLWithPath: model.customFolderPath, isDirectory: true)
        return (url.lastPathComponent, url)
    }

    private func helpCard(
        _ title: String,
        _ body: String,
        linkLabel: String? = nil,
        linkURL: URL? = nil,
        folderLink: (name: String, url: URL)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(deck.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let folderLink {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(model.L("On this Mac the watched folder is named") + " ")
                    Button(folderLink.name) {
                        _ = folderLink.url.startAccessingSecurityScopedResource()
                        NSWorkspace.shared.open(folderLink.url)
                    }
                    .buttonStyle(.plain)
                    .underline()
                    .foregroundStyle(deck.cyan)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    Text(".")
                }
                .font(.body)
                .foregroundStyle(deck.ink)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let linkLabel, let linkURL {
                Button {
                    NSWorkspace.shared.open(linkURL)
                } label: {
                    HStack(spacing: 5) {
                        Text(linkLabel)
                            .underline()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(deck.cyan)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(deck.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(deck.line, lineWidth: deck.border)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct VersionStamp: View {
    @Environment(\.deck) private var deck

    var body: some View {
        if Distribution.isAppStore {
            EmptyView()
        } else {
            Text("yourMark \(AppUpdates.currentVersion)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(deck.muted)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .allowsHitTesting(false)
        }
    }
}
