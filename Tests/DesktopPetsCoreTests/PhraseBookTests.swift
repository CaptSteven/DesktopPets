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

    @Test func loadDirectoryMergesEveryJSONFileInSortedOrder() throws {
        let temp = try TempDirectory()
        try temp.write("b-more.json", #"{ "idle": ["second"], "click": ["from-b"] }"#)
        try temp.write("a-first.json", #"{ "idle": ["first"], "click": ["from-a"] }"#)
        // Non-JSON files are ignored rather than choking the loader.
        try temp.write("notes.txt", "not json at all")

        let book = try PhraseBook.loadDirectory(at: temp.url)

        #expect(book.phrases(for: "idle") == ["first", "second"])
        #expect(book.phrases(for: "click") == ["from-a", "from-b"])
    }

    @Test func loadDirectoryOnAMissingDirectoryYieldsAnEmptyBook() throws {
        let missing = URL(fileURLWithPath: "/definitely/not/a/phrases/dir")
        #expect(try PhraseBook.loadDirectory(at: missing).isEmpty)
    }

    @Test func loadDirectoryPropagatesABrokenFileSoTyposAreNotSilent() throws {
        let temp = try TempDirectory()
        try temp.write("broken.json", "{ oops")

        #expect(throws: PhraseBookError.self) {
            try PhraseBook.loadDirectory(at: temp.url)
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
