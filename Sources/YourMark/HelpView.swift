import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("yourMark")
                    .font(.largeTitle.bold())
                Text("PDFs → Markdown, using Microsoft MarkItDown on this Mac.")
                    .foregroundStyle(.secondary)

                Group {
                    Text("Why Markdown").font(.headline)
                    Text("A PDF is a picture of a page. Markdown is the words, in order, as plain text you can search and edit. That is why it works so well with AI: a model can read a chapter, quote it, and tell you when the file is silent — instead of guessing at columns or a scan. Paste one heading into Grok or ChatGPT, keep notes in Obsidian, or search a whole course. Tables stay tables. Headings stay an outline. Keep the original PDF; Markdown is the working copy.")
                }

                Group {
                    Text("Engine").font(.headline)
                    Text("yourMark does not ship a frozen converter. It runs the `markitdown` CLI from uv or Homebrew Python. Menu → Engine → Upgrade MarkItDown runs `uv tool upgrade markitdown` so Microsoft’s PyPI releases show up without a new .app.")
                }

                Group {
                    Text("Tables").font(.headline)
                    Text("Yes — when the PDF has a real table, MarkItDown writes a GitHub-flavored Markdown table (columns and cell text). Lecture handouts and spreadsheets usually survive. Cell colours, merged headers, and “tables” that are only drawn lines often flatten into plain rows.")
                }

                Group {
                    Text("Pictures").font(.headline)
                    Text("In reading order, not the original page layout. Word / PowerPoint usually emit figures as Markdown images (`![ ]()`). Microsoft’s default PDF path is text + tables; scans and drawings need extras (OCR / image plugin) and will not sit in the original two-column x/y position.")
                }

                Group {
                    Text("Outline / bookmarks").font(.headline)
                    Text("Yes, usable like a PDF sidebar. yourMark reads the PDF outline (the same tree Preview.app shows) and also builds bookmarks from Markdown headings. Click a bookmark in the Library pane to jump to that chapter. If a PDF has no outline and no headings (a scan), there is nothing to jump to until OCR.")
                }

                Group {
                    Text("Library cards").font(.headline)
                    Text("Hold a card to rearrange. Swipe a card past the left edge to delete. Show in Finder selects the file. If you edit that file, the library updates.")
                }

                Group {
                    Text("Ask chapter").font(.headline)
                    Text("Put your own AI key under Engine (xAI, OpenAI, or an OpenAI-compatible URL). It is stored in the Keychain. Ask uses only the current chapter of the converted Markdown — it will not invent facts that are not in that excerpt. If the chapter is silent, Search the web opens a browser tab with the question and context. A model summary of missing terms is optional and off by default.")
                }

                Group {
                    Text("Install the engine").font(.headline)
                    Text("uv tool install 'markitdown[all]'\nmarkitdown --version")
                        .font(.body.monospaced())
                }

                Group {
                    Text("Keep the original").font(.headline)
                    Text("Converted Markdown is for search and study. Keep the original PDF or Word file.")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
