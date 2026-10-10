import Foundation

/// UI language.
///
/// Only the menu is localised. The pet's lines come from `Resources/Phrases/*.json`, which you
/// edit directly — there is no reason to route those through a string table.
public enum AppLanguage: String, Codable, CaseIterable, Equatable {
    case chinese = "zh"
    case english = "en"

    public var toggled: AppLanguage {
        self == .chinese ? .english : .chinese
    }

    /// The language to fall back to when the user has never chosen one.
    ///
    /// Takes the preference list as an argument instead of reading it, so this stays a pure
    /// function that tests can pin down regardless of the machine's locale.
    public static func matching(preferredLanguages: [String]) -> AppLanguage {
        guard let first = preferredLanguages.first?.lowercased() else { return .english }
        return first.hasPrefix("zh") ? .chinese : .english
    }

    /// Shown in the bubble right after a switch, so the toggle is not silent — right-clicking
    /// otherwise changes something you cannot see until you next open the menu.
    public var switchAnnouncement: String {
        switch self {
        case .chinese: return "已切换到中文"
        case .english: return "Switched to English"
        }
    }
}

/// Every piece of menu text, for one language.
public struct MenuStrings: Equatable {
    /// Format for the disabled header row. `%@` is the skin name.
    public let skinFormat: String
    /// Heading above the list of installed skins.
    public let skinPickerTitle: String
    /// Shown in the picker when `Resources/Skins` has nothing usable in it.
    public let noSkinsFound: String
    public let speak: String
    /// Names the language it switches *to*, so the row is unambiguous without needing a checkmark.
    public let switchLanguage: String
    public let reload: String
    public let resetPosition: String
    public let quit: String

    public func skinHeader(name: String) -> String {
        String(format: skinFormat, name)
    }

    public static func forLanguage(_ language: AppLanguage) -> MenuStrings {
        switch language {
        case .chinese:
            return MenuStrings(
                skinFormat: "皮肤：%@",
                skinPickerTitle: "选择皮肤",
                noSkinsFound: "没有找到皮肤",
                speak: "说话",
                switchLanguage: "切换语言：English",
                reload: "重新载入皮肤与台词",
                resetPosition: "回到默认位置",
                quit: "退出 DesktopPets"
            )
        case .english:
            return MenuStrings(
                skinFormat: "Skin: %@",
                skinPickerTitle: "Choose Skin",
                noSkinsFound: "No skins found",
                speak: "Speak",
                switchLanguage: "Switch language: 中文",
                reload: "Reload Skin and Phrases",
                resetPosition: "Reset Position",
                quit: "Quit DesktopPets"
            )
        }
    }
}
