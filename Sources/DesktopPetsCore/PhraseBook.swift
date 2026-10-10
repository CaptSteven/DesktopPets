import Foundation

public enum PhraseBookError: Error, CustomStringConvertible, Equatable {
    case invalidJSON(path: String, detail: String)

    public var description: String {
        switch self {
        case .invalidJSON(let path, let detail):
            return "Phrase file \(path) is not a valid JSON object of [category: [phrase]]: \(detail)"
        }
    }
}

/// Category-keyed phrase lists, with the one bit of state that matters: what was said last.
///
/// Phrases live in `Resources/Phrases/*.json` as a flat object, e.g.
/// `{ "click": ["hey!"], "idle": ["..."] }`.
public struct PhraseBook {
    /// Category name to phrases, in file order, with blanks and duplicates removed.
    public private(set) var categories: [String: [String]]
    /// Last phrase spoken per category, so the pet does not repeat itself twice in a row.
    private var lastPicked: [String: String]

    public init(categories: [String: [String]] = [:]) {
        self.categories = categories.mapValues(Self.sanitize)
        self.lastPicked = [:]
    }

    /// Trims, drops empties and de-duplicates while preserving author order.
    static func sanitize(_ phrases: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for phrase in phrases {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    // MARK: Loading

    public static func decode(from data: Data, path: String = "<memory>") throws -> PhraseBook {
        do {
            let raw = try JSONDecoder().decode([String: [String]].self, from: data)
            return PhraseBook(categories: raw)
        } catch {
            throw PhraseBookError.invalidJSON(path: path, detail: String(describing: error))
        }
    }

    public static func load(from url: URL) throws -> PhraseBook {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PhraseBookError.invalidJSON(path: url.path, detail: "could not read file")
        }
        return try decode(from: data, path: url.path)
    }

    /// Merges every `*.json` in a directory. Files are read in sorted order so the result is
    /// deterministic, and categories present in several files are concatenated.
    public static func loadDirectory(at url: URL, fileManager: FileManager = .default) throws -> PhraseBook {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } catch {
            // A missing Phrases directory just means the pet stays quiet.
            return PhraseBook()
        }

        var merged: PhraseBook = PhraseBook()
        for file in entries.filter({ $0.pathExtension.lowercased() == "json" }).sorted(by: { $0.path < $1.path }) {
            let book = try load(from: file)
            for (category, phrases) in book.categories {
                merged.categories[category] = sanitize((merged.categories[category] ?? []) + phrases)
            }
        }
        return merged
    }

    // MARK: Lookup

    public var allCategories: [String] { categories.keys.sorted() }

    public func phrases(for category: String) -> [String] { categories[category] ?? [] }

    public func isEmpty(for category: String) -> Bool { phrases(for: category).isEmpty }

    public var isEmpty: Bool { categories.values.allSatisfy(\.isEmpty) }

    /// Picks a phrase, avoiding an immediate repeat when there is any alternative.
    public mutating func pick<R: RandomNumberGenerator>(
        for category: String,
        using rng: inout R
    ) -> String? {
        let pool = phrases(for: category)
        guard !pool.isEmpty else { return nil }

        var candidates = pool
        if pool.count > 1, let previous = lastPicked[category] {
            let filtered = pool.filter { $0 != previous }
            if !filtered.isEmpty { candidates = filtered }
        }

        guard let choice = candidates.randomElement(using: &rng) else { return nil }
        lastPicked[category] = choice
        return choice
    }

    public mutating func pick(for category: String) -> String? {
        var rng = SystemRandomNumberGenerator()
        return pick(for: category, using: &rng)
    }

    /// The category the pet should speak from, given what it is doing.
    /// Falls back through `idle` so a book with only `click` phrases still says something.
    public func speechCategory(forPetState state: String, event: SpeechEvent) -> String? {
        let preferred: [String]
        switch event {
        case .click: preferred = ["click", "idle"]
        case .idle: preferred = ["idle"]
        case .sleep: preferred = ["sleep", "idle"]
        case .drag: preferred = ["drag", "idle"]
        }
        for category in preferred where !isEmpty(for: category) {
            return category
        }
        // Nothing matched by name; use whatever the skin's state is called, if it has phrases.
        return isEmpty(for: state) ? nil : state
    }
}

/// What happened, from the phrase book's point of view.
public enum SpeechEvent: String, Equatable, CaseIterable {
    case click
    case idle
    case sleep
    case drag
}

extension PhraseBook: Equatable {
    /// Equality intentionally ignores `lastPicked`: two books holding the same words are the
    /// same book, regardless of what has been said so far.
    public static func == (lhs: PhraseBook, rhs: PhraseBook) -> Bool {
        lhs.categories == rhs.categories
    }
}
