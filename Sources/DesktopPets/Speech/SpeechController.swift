import AppKit
import DesktopPetsCore

/// Decides when the pet talks, and keeps the bubble glued to it.
///
/// Driven from the pet's existing 30Hz tick rather than its own timer, so there is one clock in
/// the app and the bubble cannot drift away from the sprite.
final class SpeechController {
    /// How long a line stays fully visible.
    private static let holdDuration: Double = 2.6
    /// Length of the fade-out ramp at the end of the hold.
    private static let fadeDuration: Double = 0.45
    /// Quiet time between unprompted remarks, so the pet is not a chatterbox.
    private static let idleInterval: ClosedRange<Double> = 22...55

    private let config: ConfigStore
    private let bubble = SpeechBubbleWindow()
    private var book: PhraseBook
    private var rng = SystemRandomNumberGenerator()
    private var visibleFor: Double = 0
    private var currentText: String?
    private var timeUntilIdleLine: Double

    init(config: ConfigStore, book: PhraseBook) {
        self.config = config
        self.book = book
        self.timeUntilIdleLine = Double.random(in: Self.idleInterval)
        if !config.isSpeechEnabled { bubble.dismiss() }
    }

    var isEnabled: Bool { config.isSpeechEnabled }

    /// Hides the bubble immediately. Used when the controller is torn down.
    func stop() {
        dismiss()
    }

    func setEnabled(_ enabled: Bool) {
        config.isSpeechEnabled = enabled
        if !enabled { dismiss() }
    }

    /// Swaps in the phrase book for a newly selected language.
    ///
    /// Called on every language switch: the menu and the pet's lines have to change together, or
    /// you get an English menu with a pet still speaking Chinese.
    func usePhraseBook(_ book: PhraseBook) {
        self.book = book
        dismiss()
        timeUntilIdleLine = Double.random(in: Self.idleInterval)
    }

    /// Reacts to something that happened to the pet. Silent when speech is off, or when the phrase
    /// book has nothing usable.
    func react(
        to event: SpeechEvent,
        petState: String,
        petFrame: CGRect,
        visibleFrame: CGRect
    ) {
        guard isEnabled else { return }
        guard let category = book.speechCategory(forPetState: petState, event: event) else { return }
        guard let phrase = book.pick(for: category, using: &rng) else { return }

        currentText = phrase
        visibleFor = Self.holdDuration + Self.fadeDuration
        present(petFrame: petFrame, visibleFrame: visibleFrame)
    }

    /// Keeps the bubble positioned and counts down to the next idle remark.
    func tick(dt: Double, petState: String, petFrame: CGRect, visibleFrame: CGRect) {
        // A visible bubble always ticks down, whatever the Speak setting is: an announcement made
        // while speech is off must still disappear on its own.
        if visibleFor > 0 {
            visibleFor -= dt
            if visibleFor <= 0 {
                dismiss()
            } else {
                present(petFrame: petFrame, visibleFrame: visibleFrame)
            }
            return
        }

        guard isEnabled else { return }

        // Unprompted remarks only while the pet is actually idle; asleep or mid-reaction it has
        // nothing to add.
        guard petState == "idle" else { return }
        timeUntilIdleLine -= dt
        if timeUntilIdleLine <= 0 {
            timeUntilIdleLine = Double.random(in: Self.idleInterval)
            react(to: .idle, petState: petState, petFrame: petFrame, visibleFrame: visibleFrame)
        }
    }

    /// Shows a line regardless of the Speak setting.
    ///
    /// Used for UI confirmation — a language switch — rather than pet chatter. It is feedback for
    /// an action the user just took, so it must appear even with speech turned off, otherwise
    /// right-clicking would silently change something invisible.
    func announce(_ text: String, petFrame: CGRect, visibleFrame: CGRect) {
        currentText = text
        visibleFor = Self.holdDuration + Self.fadeDuration
        present(petFrame: petFrame, visibleFrame: visibleFrame)
    }

    private func present(petFrame: CGRect, visibleFrame: CGRect) {
        guard let currentText else { return }
        bubble.present(
            text: currentText,
            above: petFrame,
            within: visibleFrame,
            alpha: alpha
        )
    }

    /// 1 while holding, ramping to 0 across the fade window.
    private var alpha: CGFloat {
        guard visibleFor > 0 else { return 0 }
        let remaining = min(visibleFor, Self.fadeDuration)
        return CGFloat(max(0, min(1, remaining / Self.fadeDuration)))
    }

    private func dismiss() {
        visibleFor = 0
        currentText = nil
        bubble.dismiss()
    }
}
