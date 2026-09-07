import Foundation

enum AskModels {
    static let xai: [(id: String, label: String, note: String)] = [
        ("grok-4.6", "Grok 4.6", "Flagship · $2 / $6 per 1M"),
        ("grok-4.5", "Grok 4.5", "Same class as 4.6 · $2 / $6 per 1M"),
        ("grok-4.3", "Grok 4.3", "Everyday · 1M context · $1.25 / $2.50 per 1M"),
        ("grok-4.20", "Grok 4.20", "Long context · $1.25 / $2.50 per 1M"),
        ("grok-build-0.1", "Grok Build 0.1", "Budget / code · $1 / $2 per 1M"),
    ]

    static let openai: [(id: String, label: String, note: String)] = [
        ("gpt-5.2", "GPT-5.2", "Current flagship · $1.75 / $14 per 1M"),
        ("gpt-5", "GPT-5", "Strong general · $1.25 / $10 per 1M"),
        ("gpt-4o", "GPT-4o", "Vision, older · $2.50 / $10 per 1M"),
        ("gpt-4o-mini", "GPT-4o mini", "Cheap and fast · $0.15 / $0.60 per 1M"),
    ]

    static func list(for provider: String) -> [(id: String, label: String, note: String)] {
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
