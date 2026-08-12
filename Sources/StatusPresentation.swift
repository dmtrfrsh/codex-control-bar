import Foundation

enum StatusPresentation {
    // Mirrors the original app's behaviour: choose once when a session enters
    // thinking, hold the word steady, then choose a different one after the
    // next tool round-trip. The list is deliberately shorter for menu-bar use.
    static let thinkingWords = [
        "Thinking", "Pondering", "Working", "Computing", "Brewing",
        "Crafting", "Deciphering", "Generating", "Hashing", "Imagining",
        "Manifesting", "Noodling", "Orbiting", "Processing", "Puzzling",
        "Ruminating", "Simmering", "Synthesizing", "Tinkering", "Wrangling",
        "Struggling",
    ]

    static func nextThinkingWord(previous: String?) -> String {
        let candidates = thinkingWords.filter { $0 != previous }
        return candidates.randomElement() ?? "Thinking"
    }

    static func progressDots(second: Int) -> String {
        String(repeating: ".", count: ((second % 3) + 3) % 3 + 1)
    }

    static func eventIsNewer(timestamp: String, thanUnix updatedAt: Int) -> Bool {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractional.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
        return date.map { Int($0.timeIntervalSince1970) > updatedAt } ?? false
    }
}
