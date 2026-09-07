import SwiftUI

struct HelpView: View {
    @Environment(\.deck) private var deck

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("yourMark")
                    .font(.system(.largeTitle, design: .rounded).bold())
                Text("PDFs → Markdown, using Microsoft MarkItDown on this Mac.")
                    .foregroundStyle(deck.muted)

                Group {
                    Text("Why Markdown").font(.headline)
                    Text("A PDF is a picture of a page. Markdown is the words, in order, as plain text you can search and edit. That is why it works so well with AI: a model can read a chapter, quote it, and tell you when the file is silent — instead of guessing at columns or a scan. Paste one heading into Grok or ChatGPT, keep notes in Obsidian, or search a whole course. Tables stay tables. Headings stay an outline. Keep the original PDF; Markdown is the working copy.")
                }

                Group {
                    Text("Engine").font(.headline)
                    Text("yourMark does not ship a frozen converter. First launch installs Microsoft’s official `markitdown` package from PyPI (via uv). About once a day it checks PyPI and upgrades if Microsoft shipped a newer package. Menu → Settings → Upgrade engine does that immediately. The app also looks at GitHub for a newer yourMark and shows a banner when one is there. Drop a PDF anywhere on the window — it switches to Convert and starts. You do not have to hit the dashed box.")
                }

                Group {
                    Text("If macOS blocks the app").font(.headline)
                    Text("Apple has not notarized this build yet, so macOS may say it “could not verify” yourMark and offer Move to Bin. Click Done — not Move to Bin. Then: right-click yourMark → Open, or System Settings → Privacy & Security → Open Anyway. Or double-click “Install yourMark” on the disk image; that clears the quarantine flag and copies the app to Applications.")
                }

                Group {
                    Text("Scanned PDFs / OCR").font(.headline)
                    Text("A scan has no text layer, so MarkItDown (pdfminer) cannot see tables, columns, or figures. yourMark detects that and runs IBM Docling instead — layout, TableFormer tables, reading order, pictures. That takes a little longer; the first run may download models. OCRmyPDF and Apple Live Text only read words; they are the fallback if Docling is missing, and we still keep page pictures. Normal PDFs still go to Microsoft MarkItDown. MuPDF is a renderer, not layout OCR.")
                }

                Group {
                    Text("Tables").font(.headline)
                    Text("Yes — when the PDF has a real table, MarkItDown writes a GitHub-flavored Markdown table (columns and cell text). Cell colours, merged headers, and “tables” that are only drawn lines often flatten into plain rows. Scanned tables are kept as page pictures plus OCR text.")
                }

                Group {
                    Text("Pictures").font(.headline)
                    Text("In reading order, not the original page layout. After MarkItDown, yourMark pulls pictures from the PDF into a figures folder next to the Markdown. Word / PowerPoint already emit figures as images. Scans use Docling. Pictures will not sit at the original two-column x/y position.")
                }

                Group {
                    Text("Outline / bookmarks").font(.headline)
                    Text("Yes, usable like a PDF sidebar. yourMark reads the PDF outline and also builds bookmarks from Markdown headings. Click a bookmark to jump. If a PDF has no outline and no headings (a scan), there is nothing to jump to until OCR.")
                }

                Group {
                    Text("Library cards").font(.headline)
                    Text("Swipe a card left to delete. Right-click for Open, Show in Finder, and Delete. Drag to rearrange. Show in Finder selects the file. If you edit that file, the library updates.")
                }

                Group {
                    Text("Ask chapter").font(.headline)
                    Text("Put your own AI key under Settings (xAI, OpenAI, or an OpenAI-compatible URL). Paste it, then press Enter to lock it in. It is stored in the Keychain. Ask uses only the current chapter of the converted Markdown. If the chapter is silent, Search the web opens a browser tab with the question and context. A model summary of missing terms is optional and off by default.")
                }

                Group {
                    Text("Keep the original").font(.headline)
                    Text("Converted Markdown is for search and study. Keep the original PDF or Word file.")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(deck.ink)
        }
        .background(deck.page)
    }
}
