import Foundation

/// Something the pet's menu can do. Deliberately an enum rather than a `Selector`, so the menu
/// structure is pure data that Core can build, describe and unit test.
public enum MenuAction: String, Equatable, CaseIterable {
    case toggleSpeech
    case switchLanguage
    case reload
    case resetPosition
    case quit
}

/// One row of the menu.
///
/// Both the pet's own panel and the menu-bar item are rendered from the same `[MenuItem]`, so the
/// two can never drift apart as features are added.
public enum MenuItem: Equatable {
    /// A non-selectable label, used for the "which skin is loaded" row.
    case header(String)
    case separator
    case action(MenuAction, title: String)
    /// A row with a checkmark that reflects a boolean setting.
    case toggle(MenuAction, title: String, isOn: Bool)

    public var title: String? {
        switch self {
        case .header(let title): return title
        case .action(_, let title): return title
        case .toggle(_, let title, _): return title
        case .separator: return nil
        }
    }

    public var action: MenuAction? {
        switch self {
        case .action(let action, _): return action
        case .toggle(let action, _, _): return action
        case .header, .separator: return nil
        }
    }

    /// Headers and separators are decoration; only actions and toggles can be chosen.
    public var isSelectable: Bool { action != nil }

    /// True when this row should be drawn with a checkmark.
    public var isOn: Bool {
        if case .toggle(_, _, let isOn) = self { return isOn }
        return false
    }
}

/// Builds the pet's menu.
public enum PetMenuModel {
    public static func items(
        strings: MenuStrings,
        skinName: String,
        speechEnabled: Bool
    ) -> [MenuItem] {
        [
            .header(strings.skinHeader(name: skinName)),
            .separator,
            .toggle(.toggleSpeech, title: strings.speak, isOn: speechEnabled),
            .action(.switchLanguage, title: strings.switchLanguage),
            .separator,
            .action(.reload, title: strings.reload),
            .action(.resetPosition, title: strings.resetPosition),
            .separator,
            .action(.quit, title: strings.quit),
        ]
    }

    /// Rows a user can actually pick, in order. Used by `MenuPanelLayout` to map a click to a row.
    public static func selectableItems(in items: [MenuItem]) -> [MenuItem] {
        items.filter(\.isSelectable)
    }
}
