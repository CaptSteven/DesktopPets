import CoreGraphics
import Foundation

/// Persisted settings, backed by `UserDefaults`.
///
/// The `UserDefaults` instance is injected so tests can use a throwaway suite instead of
/// scribbling on the real preferences domain.
public final class ConfigStore {
    public enum Key: String {
        case skinName = "skinName"
        case petX = "petX"
        case petY = "petY"
        case muted = "muted"
        case walkSpeed = "walkSpeed"
        case sleepAfter = "sleepAfter"
        case speechEnabled = "speechEnabled"
        case language = "language"
    }

    /// Points per second. Slow enough to look like ambling rather than sliding.
    public static let defaultWalkSpeed: Double = 42
    /// Seconds of no interaction before the pet lies down.
    public static let defaultSleepAfter: Double = 30
    public static let defaultSpeechEnabled = true
    public static let defaultSkinName = "placeholder"

    private let defaults: UserDefaults

    /// A fixed suite name, so the app behaves identically whether it runs from a bundle or from
    /// `swift run`.
    ///
    /// `UserDefaults.standard` resolves its domain from the main bundle's identifier. A bundle has
    /// one; a plain `swift run` executable does not, and silently lands somewhere else. That means
    /// the skin, position and language you set while developing would not carry over to the built
    /// `.app` — a confusing way to lose an afternoon.
    public static let suiteName = "com.desktoppets.DesktopPets"

    public init(defaults: UserDefaults = UserDefaults(suiteName: ConfigStore.suiteName) ?? .standard) {
        self.defaults = defaults
    }

    /// A store backed by an isolated, in-memory-ish suite. Used by tests.
    public static func ephemeral(name: String = "DesktopPetsTests") -> ConfigStore {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return ConfigStore(defaults: defaults)
    }

    // MARK: Accessors

    public var skinName: String? {
        get { defaults.string(forKey: Key.skinName.rawValue) }
        set { defaults.set(newValue, forKey: Key.skinName.rawValue) }
    }

    /// The pet's hotspot in screen coordinates, or `nil` if it has never been placed.
    public var petPosition: CGPoint? {
        get {
            guard defaults.object(forKey: Key.petX.rawValue) != nil,
                  defaults.object(forKey: Key.petY.rawValue) != nil
            else { return nil }
            return CGPoint(
                x: defaults.double(forKey: Key.petX.rawValue),
                y: defaults.double(forKey: Key.petY.rawValue)
            )
        }
        set {
            guard let position = newValue else {
                defaults.removeObject(forKey: Key.petX.rawValue)
                defaults.removeObject(forKey: Key.petY.rawValue)
                return
            }
            defaults.set(position.x, forKey: Key.petX.rawValue)
            defaults.set(position.y, forKey: Key.petY.rawValue)
        }
    }

    public var isMuted: Bool {
        get { defaults.bool(forKey: Key.muted.rawValue) }
        set { defaults.set(newValue, forKey: Key.muted.rawValue) }
    }

    public var walkSpeed: Double {
        get { double(forKey: Key.walkSpeed, default: Self.defaultWalkSpeed) }
        set { defaults.set(newValue, forKey: Key.walkSpeed.rawValue) }
    }

    public var sleepAfter: Double {
        get { double(forKey: Key.sleepAfter, default: Self.defaultSleepAfter) }
        set { defaults.set(newValue, forKey: Key.sleepAfter.rawValue) }
    }

    public var isSpeechEnabled: Bool {
        get { bool(forKey: Key.speechEnabled, default: Self.defaultSpeechEnabled) }
        set { defaults.set(newValue, forKey: Key.speechEnabled.rawValue) }
    }

    /// Menu language. Falls back to the system's preferred language until the user toggles it.
    public var language: AppLanguage {
        get {
            guard let raw = defaults.string(forKey: Key.language.rawValue),
                  let stored = AppLanguage(rawValue: raw)
            else {
                return AppLanguage.matching(preferredLanguages: Locale.preferredLanguages)
            }
            return stored
        }
        set { defaults.set(newValue.rawValue, forKey: Key.language.rawValue) }
    }

    /// Flips the menu language and returns the new value.
    @discardableResult
    public func toggleLanguage() -> AppLanguage {
        let next = language.toggled
        language = next
        return next
    }

    /// A `WalkPlan` built from the stored speed, with everything else at its default.
    public func walkPlan(base: WalkPlan = WalkPlan()) -> WalkPlan {
        var plan = base
        plan.speed = walkSpeed
        return plan
    }

    public func reset() {
        for key in [Key.skinName, Key.petX, Key.petY, Key.muted, Key.walkSpeed,
                    Key.sleepAfter, Key.speechEnabled, Key.language] {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    // MARK: Defaulted reads

    /// `UserDefaults.bool(forKey:)` returns `false` for a missing key, which is not the same as
    /// "unset". These helpers preserve the default until the user actually chooses something.
    private func bool(forKey key: Key, default fallback: Bool) -> Bool {
        guard defaults.object(forKey: key.rawValue) != nil else { return fallback }
        return defaults.bool(forKey: key.rawValue)
    }

    private func double(forKey key: Key, default fallback: Double) -> Double {
        guard let stored = defaults.object(forKey: key.rawValue) as? Double else { return fallback }
        return stored
    }
}
