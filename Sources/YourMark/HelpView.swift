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
                    Text("Hold a card to rearrange. Swipe a card past the left edge to delete. After you delete Getting started, an i in the header shows the same guide.")
                }

                Group {
                    Text("Ask chapter").font(.headline)
                    Text("Put your own AI key under Engine (xAI, OpenAI, or an OpenAI-compatible URL). It is stored in the Keychain. Ask uses only the current chapter of the converted Markdown — it will not invent facts that are not in that excerpt.")
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
