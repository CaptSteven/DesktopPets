import Foundation
import Testing
@testable import DesktopPetsCore

@Suite struct PhraseBookTests {
    let sampleJSON = """
    {
      "click": ["hey!", "ouch", "hey!"],
      "idle": ["...", "  ", "just sitting here"],
      "sleep": ["zzz"]
    }
    """

    // MARK: Loading

    @Test func decodeTrimsBlanksAndDuplicates() throws {
        let book = try PhraseBook.decode(from: Data(sampleJSON.utf8))

        #expect(book.phrases(for: "click") == ["hey!", "ouch"], "duplicates removed, order kept")
        #expect(book.phrases(for: "idle") == ["...", "just sitting here"], "blank entries dropped")
        #expect(book.allCategories == ["click", "idle", "sleep"])
    }

    @Test func missingCategoryYieldsNoPhrases() throws {
        let book = try PhraseBook.decode(from: Data(sampleJSON.utf8))
        #expect(book.isEmpty(for: "drag"))
        #expect(book.phrases(for: "drag") == [])
    }

    @Test func malformedJSONReportsThePath() {
        let error = #expect(throws: PhraseBookError.self) {
            try PhraseBook.decode(from: Data("[]".utf8), path: "/tmp/phrases.json")
        }
        guard case .invalidJSON(let path, _) = error else {
            Issue.record("expected invalidJSON, got \(String(describing: error))")
            return
        }
        #expect(path == "/tmp/phrases.json")
    }

    @Test func loadsOnlyTheRequestedLanguage() throws {
        let temp = try TempDirectory()
        try temp.write("zh.json", #"{ "idle": ["你好"], "click": ["别戳我"] }"#)
        try temp.write("en.json", #"{ "idle": ["hello"], "click": ["stop poking me"] }"#)
        // A stray file must not be merged in: one file per language is the whole point.
        try temp.write("notes.txt", "not json at all")

        let zh = try PhraseBook.load(language: .chinese, from: temp.url)
        let en = try PhraseBook.load(language: .english, from: temp.url)

        #expect(zh.phrases(for: "idle") == ["你好"])
        #expect(en.phrases(for: "idle") == ["hello"])
    }

    @Test func aMissingLanguageFileYieldsAnEmptyBookRatherThanFailing() throws {
        let temp = try TempDirectory()
        try temp.write("zh.json", #"{ "idle": ["你好"] }"#)

        // English was never authored: the pet should just be quiet in English, not refuse to start.
        #expect(try PhraseBook.load(language: .english, from: temp.url).isEmpty)
    }

    @Test func aMissingDirectoryYieldsAnEmptyBook() throws {
        let missing = URL(fileURLWithPath: "/definitely/not/a/phrases/dir")
        #expect(try PhraseBook.load(language: .chinese, from: missing).isEmpty)
    }

    @Test func aBrokenLanguageFileIsNotSilentlyIgnored() throws {
        let temp = try TempDirectory()
        try temp.write("zh.json", "{ oops")

        // A malformed file is a typo to fix, not something to paper over.
        #expect(throws: PhraseBookError.self) {
            try PhraseBook.load(language: .chinese, from: temp.url)
        }
    }

    @Test func fileURLUsesTheLanguageCode() {
        let directory = URL(fileURLWithPath: "/r/Phrases")
        #expect(PhraseBook.fileURL(for: .chinese, in: directory).path == "/r/Phrases/zh.json")
        #expect(PhraseBook.fileURL(for: .english, in: directory).path == "/r/Phrases/en.json")
    }

    @Test func availableLanguagesReportsOnlyTheFilesThatExist() throws {
        let temp = try TempDirectory()

        // Nothing authored yet.
        #expect(PhraseBook.availableLanguages(in: temp.url).isEmpty)

        try temp.write("zh.json", "{}")
        #expect(PhraseBook.availableLanguages(in: temp.url) == [.chinese])

        try temp.write("en.json", "{}")
        #expect(PhraseBook.availableLanguages(in: temp.url) == [.chinese, .english])
    }

    @Test func everyLanguageHasTheSameCategoriesInTheShippedFiles() throws {
        // Both languages ship with the app, so they have to stay in step. If one is missing a
        // category, those reactions silently fall back to idle *in that language only* — the kind
        // of gap nobody notices until someone switches.
        let root = try #require(
            AssetLocator.sourceTreeResourcesRoot(),
            "Resources is missing from the source tree"
        )
        let directory = root.appendingPathComponent("Phrases", isDirectory: true)

        let present = PhraseBook.availableLanguages(in: directory)
        #expect(Set(present) == Set(AppLanguage.allCases),
                "every language needs a phrase file; found \(present.map(\.rawValue))")

        let books = try present.map { try PhraseBook.load(language: $0, from: directory) }

        for (language, book) in zip(present, books) {
            let categories = Set(book.allCategories)
            #expect(categories == Set(books[0].allCategories),
                    "\(language.rawValue) has different categories from \(present[0].rawValue)")

            // And every category the pet can actually ask for must be present.
            for event in SpeechEvent.allCases {
                #expect(!book.isEmpty(for: event.rawValue),
                        "\(language.rawValue) has no \(event.rawValue) phrases")
            }
        }
    }

    @Test func emptyBookIsDetected() {
        #expect(PhraseBook().isEmpty)
        #expect(PhraseBook(categories: ["idle": ["  ", ""]]).isEmpty)
        #expect(!PhraseBook(categories: ["idle": ["hi"]]).isEmpty)
    }

    // MARK: Picking

    @Test func pickAvoidsImmediateRepetition() throws {
        var book = try PhraseBook.decode(from: Data(sampleJSON.utf8))
        var rng = SeededGenerator(seed: 99)

        var last: String?
        for _ in 0..<50 {
            let picked = try #require(book.pick(for: "click", using: &rng))
            if let last { #expect(picked != last, "repeated itself twice in a row") }
            last = picked
        }
    }

    @Test func pickReturnsTheOnlyPhraseWhenThereIsOne() {
        var book = PhraseBook(categories: ["sleep": ["zzz"]])
        var rng = SeededGenerator(seed: 5)

        for _ in 0..<10 {
            #expect(book.pick(for: "sleep", using: &rng) == "zzz")
        }
    }

    @Test func pickOnAnEmptyCategoryReturnsNil() {
        var book = PhraseBook(categories: ["idle": ["hi"]])
        #expect(book.pick(for: "drag") == nil)
    }

    @Test func pickReachesEveryPhraseEventually() {
        var book = PhraseBook(categories: ["click": ["a", "b", "c"]])
        var rng = SeededGenerator(seed: 1234)
        var seen = Set<String>()

        for _ in 0..<200 {
            if let picked = book.pick(for: "click", using: &rng) { seen.insert(picked) }
        }
        #expect(seen == ["a", "b", "c"])
    }

    @Test func pickIsReproducibleForTheSameSeed() {
        let book = PhraseBook(categories: ["click": ["a", "b", "c", "d"]])

        var first = book
        var second = book
        var rngA = SeededGenerator(seed: 77)
        var rngB = SeededGenerator(seed: 77)

        let picksA = (0..<20).map { _ in first.pick(for: "click", using: &rngA) }
        let picksB = (0..<20).map { _ in second.pick(for: "click", using: &rngB) }

        #expect(picksA == picksB)
    }

    // MARK: Speech category routing

    @Test func speechCategoryPrefersTheEventSpecificList() throws {
        let book = try PhraseBook.decode(from: Data(sampleJSON.utf8))

        #expect(book.speechCategory(forPetState: "idle", event: .click) == "click")
        #expect(book.speechCategory(forPetState: "idle", event: .idle) == "idle")
        #expect(book.speechCategory(forPetState: "sleep", event: .sleep) == "sleep")
    }

    @Test func speechCategoryFallsBackToIdleWhenTheEventListIsMissing() throws {
        let book = try PhraseBook.decode(from: Data(#"{ "idle": ["hi"], "click": ["hey"] }"#.utf8))

        #expect(book.speechCategory(forPetState: "idle", event: .sleep) == "idle")
        #expect(book.speechCategory(forPetState: "idle", event: .drag) == "idle")
    }

    @Test func speechCategoryIsNilWhenNothingMatches() {
        let book = PhraseBook(categories: ["unrelated": ["..."]])
        #expect(book.speechCategory(forPetState: "idle", event: .click) == nil)
    }

    @Test func speechCategoryFallsBackToTheSkinStateName() {
        // A skin with a custom state that has phrases of the same name.
        let book = PhraseBook(categories: ["sneeze": ["achoo"]])
        #expect(book.speechCategory(forPetState: "sneeze", event: .click) == "sneeze")
    }

    @Test func equalityIgnoresWhatHasAlreadyBeenSaid() {
        var spoken = PhraseBook(categories: ["idle": ["hi"]])
        _ = spoken.pick(for: "idle")

        #expect(spoken == PhraseBook(categories: ["idle": ["hi"]]))
        #expect(spoken != PhraseBook(categories: ["idle": ["bye"]]))
    }
}
