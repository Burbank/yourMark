import SwiftUI

struct HelpView: View {
    @Environment(\.deck) private var deck

    private var cards: [(title: String, body: String)] {
        var list: [(title: String, body: String)] = [
        (
            "Why Markdown",
            "A PDF is a picture of a page. Markdown is the words, in order. A model can read a chapter and quote the words that are there. If that chapter does not have the answer, it can say so — instead of guessing at a scan. Keep the original PDF."
        ),
        ]
        if Distribution.isAppStore {
            list.append((
                "Engine",
                "Microsoft MarkItDown is included. Photographed pages use Apple Live Text. The GitHub disk can still add IBM Docling for tables."
            ))
        } else {
            list.append((
                "Engine",
                "First launch installs Microsoft MarkItDown from PyPI. Convert stays on this Mac. About once a day we check for their updates. Settings → Install or reinstall does that now."
            ))
            list.append((
                "First open",
                "This disk is signed and notarized by Apple. The first open may ask if you want to open it — click Open."
            ))
            list.append((
                "Scanned PDFs",
                "A scan has no text layer. Settings lets you pick Apple Live Text (already on this Mac) or IBM Docling (better tables — a large download). Ordinary digital PDFs still go to MarkItDown."
            ))
        }
        list += [
        (
            "Tables",
            "Real tables become Markdown tables. Colours and merged cells flatten. Drawn “tables” that are only lines often become plain rows. Scans keep a picture plus OCR text."
        ),
        (
            "Pictures",
            "Pictures live in a figures folder next to the Markdown. The file only points at them (Figure 3 · page 2), so it stays small for you and for AI."
        ),
        (
            "Picture links",
            "In the reader, a picture is a blue link — not the photo itself. Rest the pointer on the link: a preview appears in the reader (the photo slider next to text size sets how big). Click the link: Finder opens with that picture file selected. Pictures are not loaded while you scroll."
        ),
        (
            "Bookmarks",
            "The PDF’s own outline — the same tree as Preview — becomes Markdown headings. We keep that tree. If there is no outline, we use large-font lines, then AI only if you tick it."
        ),
        (
            "Library cards",
            "Swipe a card left to delete. Right-click for Open, Show in Finder, and Delete. Drag to rearrange. Edits on disk update the library."
        ),
        (
            "Ask chapter",
            "Paste a Grok or OpenAI key in Settings, then press Enter. We test it once and lock it on this Mac. Ask uses only the current chapter. If the chapter does not have the answer, Search the web is there."
        ),
        (
            "Reading",
            "The right pane is a reader. A / slider / A changes text size. The photo slider next to it changes the hover picture preview (default is large). Settings → Reader picks the font. Rendered vs Plain. Edit opens MarkEdit. Finder shows the file."
        ),
        (
            "MarkEdit",
            "yourMark does not edit files. MarkEdit is a free native Mac editor. Press Edit in the reader, or get it from Settings. Saves there show up here."
        ),
        (
            "Shortcuts and scripts",
            "A Shortcut or Terminal can hand a file to yourMark with a link: yourmark://convert?file=/Users/you/Manual.pdf — put your file’s full path after file=. Dropping a PDF on the window still works."
        ),
        (
            "Translate",
            "Translate sends the open chapter to Google Translate or to your Ask model — whichever you pick in Settings. Convert still stays on this Mac. Pick From and To in the reader, then press Translate. Below each paragraph keeps the original; Replace shows only the translation. Save a copy writes a second file. The original Markdown is not overwritten."
        ),
        (
            "Keep the original",
            "Converted Markdown is for search and study. Keep the original PDF or Word file."
        ),
        (
            "Crash reports",
            "If yourMark closes unexpectedly, we can copy the macOS report. Paste it in a message — no GitHub account needed. Settings can turn the offer off. Nothing is sent in the background."
        ),
        ]
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("yourMark")
                    .font(.system(.largeTitle, design: .rounded).bold())
                Text(Distribution.isAppStore
                     ? "PDFs → Markdown, using Apple PDFKit and Live Text on this Mac."
                     : "PDFs → Markdown, using Microsoft MarkItDown on this Mac.")
                    .foregroundStyle(deck.muted)
                    .frame(maxWidth: 420, alignment: .leading)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(card.title)
                                .font(.headline)
                            Text(card.body)
                                .font(.body)
                                .foregroundStyle(deck.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(deck.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(deck.line, lineWidth: deck.border)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .foregroundStyle(deck.ink)
        }
        .background(deck.page)
        .overlay(alignment: .bottomTrailing) {
            VersionStamp()
        }
    }
}

struct VersionStamp: View {
    @Environment(\.deck) private var deck

    var body: some View {
        Text("yourMark \(AppUpdates.currentVersion)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(deck.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .allowsHitTesting(false)
    }
}
