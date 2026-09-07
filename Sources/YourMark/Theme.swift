import SwiftUI

struct DeckTheme {
    let page: Color
    let panel: Color
    let field: Color
    let ink: Color
    let muted: Color
    let line: Color
    let navy: Color
    let cyan: Color
    let btn: Color
    let btnText: Color
    let border: CGFloat

    static func resolve(_ appearance: String, _ scheme: ColorScheme) -> DeckTheme {
        switch appearance {
        case "bright": return .bright
        case "dim": return .dim
        default: return scheme == .dark ? .dim : .systemLight
        }
    }

    /// Indoor paper — not a blast of white.
    static let bright = DeckTheme(
        page: Color(hex: "d6c8b0"),
        panel: Color(hex: "e6dac4"),
        field: Color(hex: "eee3cf"),
        ink: Color(hex: "2c261d"),
        muted: Color(hex: "5f564a"),
        line: Color(hex: "c0ae92"),
        navy: Color(hex: "1e4a73"),
        cyan: Color(hex: "1e4a73"),
        btn: Color(hex: "1e4a73"),
        btnText: Color(hex: "f4ead8"),
        border: 1
    )

    /// Dark deck.
    static let dim = DeckTheme(
        page: Color(hex: "1a2332"),
        panel: Color(hex: "243044"),
        field: Color(hex: "15202e"),
        ink: Color(hex: "e8eef6"),
        muted: Color(hex: "9aadc2"),
        line: Color(hex: "3d4f66"),
        navy: Color(hex: "0080b5"),
        cyan: Color(hex: "00a1e4"),
        btn: Color(hex: "0080b5"),
        btnText: .white,
        border: 1
    )

    static let systemLight = DeckTheme(
        page: Color(hex: "f3efe6"),
        panel: Color(hex: "fffaf2"),
        field: Color(hex: "fffdf8"),
        ink: Color(hex: "1a1a1a"),
        muted: Color(hex: "4a4a4a"),
        line: Color(hex: "c9c1b3"),
        navy: Color(hex: "003d7a"),
        cyan: Color(hex: "003d7a"),
        btn: Color(hex: "003d7a"),
        btnText: .white,
        border: 2
    )
}

private struct DeckKey: EnvironmentKey {
    static let defaultValue = DeckTheme.bright
}

extension EnvironmentValues {
    var deck: DeckTheme {
        get { self[DeckKey.self] }
        set { self[DeckKey.self] = newValue }
    }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var n: UInt64 = 0
        Scanner(string: h).scanHexInt64(&n)
        self.init(
            red: Double((n >> 16) & 0xFF) / 255,
            green: Double((n >> 8) & 0xFF) / 255,
            blue: Double(n & 0xFF) / 255
        )
    }
}
