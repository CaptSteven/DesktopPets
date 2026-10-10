import CoreGraphics
import Foundation
import Testing
@testable import DesktopPetsCore

@Suite struct ConfigStoreTests {
    // A unique suite per test so cases cannot leak into each other or the real preferences.
    let store: ConfigStore

    init() {
        store = ConfigStore.ephemeral(name: "DesktopPetsTests-\(UUID().uuidString)")
    }

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
        let raw = UserDefaults(suiteName: "DesktopPetsTests-partial-\(UUID().uuidString)")!
        raw.set(42.0, forKey: ConfigStore.Key.petX.rawValue)

        #expect(ConfigStore(defaults: raw).petPosition == nil)
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

    @Test func valuesAreSharedBetweenStoresOverTheSameSuite() {
        let name = "DesktopPetsTests-shared-\(UUID().uuidString)"
        let first = ConfigStore.ephemeral(name: name)
        first.skinName = "shared"
        first.petPosition = CGPoint(x: 5, y: 6)

        // A second store over the same suite sees the same values, which is what makes
        // relaunching the app restore the pet where it was.
        let second = ConfigStore(defaults: UserDefaults(suiteName: name)!)
        #expect(second.skinName == "shared")
        #expect(second.petPosition == CGPoint(x: 5, y: 6))
    }
}
