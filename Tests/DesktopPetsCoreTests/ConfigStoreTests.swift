import CoreGraphics
import Foundation
import Testing
@testable import DesktopPetsCore

/// `.serialized` because every test in here shares one `UserDefaults` suite, which is wiped at the
/// start of each test. Serial execution is what makes that safe, and it is also what keeps a test
/// run from leaving more than one plist behind.
@Suite(.serialized) struct ConfigStoreTests {
    let defaults = EphemeralDefaults(name: "DesktopPetsTests-ConfigStore")

    var store: ConfigStore { defaults.store }

    // MARK: Defaults

    @Test func unsetValuesFallBackToDefaults() {
        #expect(store.skinName == nil)
        #expect(store.petPosition == nil)
        #expect(!store.isMuted)
        #expect(store.walkSpeed == ConfigStore.defaultWalkSpeed)
        #expect(store.sleepAfter == ConfigStore.defaultSleepAfter)
        #expect(store.isSpeechEnabled == ConfigStore.defaultSpeechEnabled)
        #expect(store.isSpeechEnabled, "speech defaults to on")
    }

    // MARK: Round trips

    @Test func skinNameRoundTripsAndCanBeCleared() {
        store.skinName = "shiba"
        #expect(store.skinName == "shiba")

        store.skinName = nil
        #expect(store.skinName == nil)
    }

    @Test func positionRoundTrips() {
        store.petPosition = CGPoint(x: 123.5, y: -40.25)
        #expect(store.petPosition == CGPoint(x: 123.5, y: -40.25))
    }

    @Test func clearingPositionRemovesBothComponents() {
        store.petPosition = CGPoint(x: 10, y: 20)
        store.petPosition = nil

        #expect(store.petPosition == nil, "a half-cleared position must not read back as valid")
    }

    @Test func settingOnlyXDoesNotProduceAPosition() {
        // Simulates an older or partially-written preferences file.
        defaults.raw.set(42.0, forKey: ConfigStore.Key.petX.rawValue)

        #expect(ConfigStore(defaults: defaults.raw).petPosition == nil)
    }

    @Test func flagRoundTripsIncludingExplicitFalse() {
        store.isMuted = true
        #expect(store.isMuted)
        store.isMuted = false
        #expect(!store.isMuted)

        // The important bit: an explicit `false` must survive rather than reverting to the
        // default of `true`.
        store.isSpeechEnabled = false
        #expect(!store.isSpeechEnabled)
        store.isSpeechEnabled = true
        #expect(store.isSpeechEnabled)
    }

    @Test func numericValuesRoundTrip() {
        store.walkSpeed = 88
        store.sleepAfter = 12.5

        #expect(store.walkSpeed == 88)
        #expect(store.sleepAfter == 12.5)
    }

    @Test func aZeroWalkSpeedIsHonouredRatherThanTreatedAsUnset() {
        store.walkSpeed = 0
        #expect(store.walkSpeed == 0)
    }

    // MARK: Derived values

    @Test func walkPlanPicksUpTheStoredSpeedAndKeepsOtherTuning() {
        store.walkSpeed = 100
        let plan = store.walkPlan(base: WalkPlan(edgeInset: 7, minPause: 1, maxPause: 2))

        #expect(plan.speed == 100)
        #expect(plan.edgeInset == 7)
        #expect(plan.minPause == 1)
        #expect(plan.maxPause == 2)
    }

    @Test func resetClearsEverything() {
        store.skinName = "cat"
        store.petPosition = CGPoint(x: 1, y: 2)
        store.isMuted = true
        store.walkSpeed = 7
        store.sleepAfter = 8
        store.isSpeechEnabled = false

        store.reset()

        #expect(store.skinName == nil)
        #expect(store.petPosition == nil)
        #expect(!store.isMuted)
        #expect(store.walkSpeed == ConfigStore.defaultWalkSpeed)
        #expect(store.sleepAfter == ConfigStore.defaultSleepAfter)
        #expect(store.isSpeechEnabled)
    }

    // MARK: Language

    @Test func languageRoundTrips() {
        store.language = .english
        #expect(store.language == .english)

        store.language = .chinese
        #expect(store.language == .chinese)
    }

    @Test func toggleLanguageFlipsAndReturnsTheNewValue() {
        store.language = .chinese

        #expect(store.toggleLanguage() == .english)
        #expect(store.language == .english, "the toggle must persist, not just report")

        #expect(store.toggleLanguage() == .chinese)
        #expect(store.language == .chinese)
    }

    @Test func anUnsetLanguageFallsBackToTheSystemPreference() {
        // Whatever the machine's locale happens to be, the fallback has to be a real language.
        let expected = AppLanguage.matching(preferredLanguages: Locale.preferredLanguages)
        #expect(store.language == expected)
    }

    @Test func anUnrecognisedStoredLanguageIsIgnored() {
        defaults.raw.set("klingon", forKey: ConfigStore.Key.language.rawValue)

        let expected = AppLanguage.matching(preferredLanguages: Locale.preferredLanguages)
        #expect(ConfigStore(defaults: defaults.raw).language == expected)
    }

    @Test func resetClearsTheLanguage() {
        // Pick the language that is *not* the system default, so reverting is observable.
        let systemDefault = AppLanguage.matching(preferredLanguages: Locale.preferredLanguages)
        store.language = systemDefault.toggled
        #expect(store.language == systemDefault.toggled)

        store.reset()

        #expect(store.language == systemDefault, "reset should fall back to the system default")
    }

    // MARK: Sharing

    @Test func valuesAreSharedBetweenStoresOverTheSameSuite() {
        store.skinName = "shared"
        store.petPosition = CGPoint(x: 5, y: 6)
        store.language = .english

        // A second store over the same suite sees the same values, which is what makes relaunching
        // the app restore the pet where it was and in the language it was left in.
        let second = ConfigStore(defaults: defaults.raw)
        #expect(second.skinName == "shared")
        #expect(second.petPosition == CGPoint(x: 5, y: 6))
        #expect(second.language == .english)
    }
}
