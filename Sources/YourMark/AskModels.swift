import Foundation

enum AskModels {
    static let xai: [(id: String, label: String)] = [
        ("grok-4.6", "Grok 4.6"),
        ("grok-4.5", "Grok 4.5"),
        ("grok-4.3", "Grok 4.3"),
        ("grok-4.20", "Grok 4.20"),
        ("grok-build-0.1", "Grok Build 0.1"),
    ]

    static let openai: [(id: String, label: String)] = [
        ("gpt-5.2", "GPT-5.2"),
        ("gpt-5", "GPT-5"),
        ("gpt-4o", "GPT-4o"),
        ("gpt-4o-mini", "GPT-4o mini"),
    ]

    static func list(for provider: String) -> [(id: String, label: String)] {
        switch provider {
        case "openai": return openai
        case "xai": return xai
        default: return []
        }
    }

    static func defaultID(for provider: String) -> String {
        list(for: provider).first?.id ?? "grok-4.6"
    }
}
