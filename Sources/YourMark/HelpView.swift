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
                    Text("Apple has not notarized this build yet, so macOS may say it “could not verify” yourMark and offer Move to Bin. Click Done — not Move to Bin. Then: right-click yourMark → Open, or System Settings → Privacy & Security → Open Anyway. The disk image has “If Apple blocks it” — that is a web page, not a program, so Apple will not treat it as malware.")
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
                    Text("After MarkItDown, yourMark walks every PDF page: it saves embedded photos and, when a page is a vector diagram with no photo, draws that page. Every picture is linked in the Markdown next to its page (a figures folder sits beside the file). Word / PowerPoint already emit figures via --keep-data-uris. Scans use Docling. Pictures will not sit at the original two-column x/y position — they appear in reading order. The in-app preview shows a sample so the window stays responsive; open the Markdown in Finder to see them all.")
                }

                Group {
                    Text("Outline / bookmarks").font(.headline)
                    Text("Microsoft MarkItDown (pdfminer) does not emit PDF bookmarks or headings — only words and tables. yourMark reads the outline Preview.app shows and writes those titles as Markdown headings at the matching pages. That tree is kept; it is not replaced by guessed headings. If the PDF has no outline, large-font lines are used, then AI chapters only if you tick that option.")
                }

                Group {
                    Text("Library cards").font(.headline)
                    Text("Swipe a card left to delete. Right-click for Open, Show in Finder, and Delete. Drag to rearrange. Show in Finder selects the file. If you edit that file, the library updates.")
                }

                Group {
                    Text("Ask chapter").font(.headline)
                    Text("Put your own AI key under Settings (xAI or OpenAI). Paste it, then press Enter. yourMark sends one short test question first; if the model answers, the key is locked in the Keychain. It also switches Provider if the key is for the other service (xai- → Grok, sk- → OpenAI). Ask uses only the current chapter of the converted Markdown. If the chapter is silent, Search the web opens a browser tab with the question and context. A model summary of missing terms is optional and off by default.")
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
