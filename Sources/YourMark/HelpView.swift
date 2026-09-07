import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("yourMark")
                    .font(.largeTitle.bold())
                Text("Aviation manuals → Markdown, using Microsoft MarkItDown on this Mac.")
                    .foregroundStyle(.secondary)

                Group {
                    Text("Engine").font(.headline)
                    Text("yourMark does not ship a frozen converter. It runs the `markitdown` CLI from uv or Homebrew Python. Menu → Engine → Upgrade MarkItDown runs `uv tool upgrade markitdown` so Microsoft’s PyPI releases show up without a new .app.")
                }

                Group {
                    Text("Install the engine").font(.headline)
                    Text("uv tool install 'markitdown[all]'\nmarkitdown --version")
                        .font(.body.monospaced())
                }

                Group {
                    Text("Not for operations").font(.headline)
                    Text("Converted Markdown is a study overlay. Keep the approved PDF/EFB as the source of truth. Same posture as GearUp4U: education and situational awareness only.")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
