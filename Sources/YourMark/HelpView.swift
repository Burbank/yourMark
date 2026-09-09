import SwiftUI

struct HelpView: View {
    @Environment(\.deck) private var deck

    private let cards: [(title: String, body: String)] = [
        (
            "Why Markdown",
            "A PDF is a picture of a page. Markdown is the words, in order. AI can quote a chapter and stay quiet when the file is silent. Keep the original PDF."
        ),
        (
            "Engine",
            "First launch installs Microsoft MarkItDown from PyPI. Convert stays on this Mac. About once a day we check for their updates. Settings → Install or reinstall does that now."
        ),
        (
            "If Apple blocks the app",
            "This build is not notarized yet. If macOS says it could not verify: click Done, not Move to Bin. Then right-click yourMark → Open, or Privacy & Security → Open Anyway."
        ),
        (
            "Scanned PDFs",
            "A scan has no text layer. yourMark uses IBM Docling for layout, tables, and figures. That takes longer the first time. Ordinary digital PDFs still go to MarkItDown."
        ),
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
            "In the reader, a picture is a blue link — not the photo itself. Rest the pointer on the link: a small preview appears. Move away and it goes. Click the link: Finder opens with that picture file selected, in the figures folder. Pictures are not loaded while you scroll, so the window should not freeze."
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
            "Paste a Grok or OpenAI key in Settings, then press Enter. We test it once and lock it on this Mac. Ask uses only the current chapter. If it is silent, Search the web is there."
        ),
        (
            "Reading",
            "The right pane is a reader. A / slider / A changes size. Settings → Reader picks the font. Rendered vs Plain. Edit opens MarkEdit. Finder shows the file."
        ),
        (
            "MarkEdit",
            "yourMark does not edit files. MarkEdit is a free native Mac editor. Press Edit in the reader, or get it from Settings. Saves there show up here."
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("yourMark")
                    .font(.system(.largeTitle, design: .rounded).bold())
                Text("PDFs → Markdown, using Microsoft MarkItDown on this Mac.")
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
    }
}
