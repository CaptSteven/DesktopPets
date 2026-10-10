import Foundation

/// Something the pet's menu can do.
///
/// Not `RawRepresentable`, because `selectSkin` carries a payload. Use `identifier` when a flat
/// string is needed (logging, or keying a menu item).
public enum MenuCommand: Equatable, Hashable {
    case toggleSpeech
    case switchLanguage
    case reload
    case resetPosition
    case quit
    /// Load a different skin. The payload is a skin identifier such as `cat` or `cat/v1`.
    case selectSkin(String)

    /// Every command that is not parameterised, in the order the menu presents them.
    ///
    /// Kept as an explicit list rather than `CaseIterable`, which cannot be synthesised for an enum
    /// with a payload.
    public static let core: [MenuCommand] = [
        .toggleSpeech,
        .switchLanguage,
        .reload,
        .resetPosition,
        .quit,
    ]

    public var identifier: String {
        switch self {
        case .toggleSpeech: return "toggleSpeech"
        case .switchLanguage: return "switchLanguage"
        case .reload: return "reload"
        case .resetPosition: return "resetPosition"
        case .quit: return "quit"
        case .selectSkin(let name): return "selectSkin:\(name)"
        }
    }
}

/// One row of the menu.
///
/// Both the pet's own panel and the menu-bar item are rendered from the same `[MenuItem]`, so the
/// two can never drift apart as features are added.
public enum MenuItem: Equatable {
    /// A non-selectable label, used for the "which skin is loaded" row.
    case header(String)
    case separator
    case action(MenuCommand, title: String)
    /// A row with a checkmark. Used both for on/off settings and for "which one is selected".
    case toggle(MenuCommand, title: String, isOn: Bool)

    public var title: String? {
        switch self {
        case .header(let title): return title
        case .action(_, let title): return title
        case .toggle(_, let title, _): return title
        case .separator: return nil
        }
    }

    public var command: MenuCommand? {
        switch self {
        case .action(let command, _): return command
        case .toggle(let command, _, _): return command
        case .header, .separator: return nil
        }
    }

    /// Headers and separators are decoration; only actions and toggles can be chosen.
    public var isSelectable: Bool { command != nil }

    /// True when this row should be drawn with a checkmark.
    public var isOn: Bool {
        if case .toggle(_, _, let isOn) = self { return isOn }
        return false
    }
}

/// Builds the pet's menu, and the skin picker behind it.
public enum PetMenuModel {
    /// The pet's actions. Picking a skin lives in its own picker, so this stays short no matter how
    /// many skins are installed.
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

    /// Rows a user can actually pick, in order. Used by `MenuPanelMetrics` to map a click to a row.
    public static func selectableItems(in items: [MenuItem]) -> [MenuItem] {
        items.filter(\.isSelectable)
    }

    /// The list of installed skins, with a checkmark on the active one.
    ///
    /// Rendered as a toggle row so the current skin is visible without a second look.
    public static func skinPickerItems(
        strings: MenuStrings,
        skins: [String],
        currentSkin: String
    ) -> [MenuItem] {
        var items: [MenuItem] = [.header(strings.skinPickerTitle)]

        if skins.isEmpty {
            // Better than an empty panel: say why there is nothing to choose.
            items.append(.header(strings.noSkinsFound))
            return items
        }

        items.append(.separator)
        for skin in skins {
            items.append(.toggle(.selectSkin(skin), title: skin, isOn: skin == currentSkin))
        }
        return items
    }

    /// What the menu-bar item shows: the pet's actions, then the skin list.
    ///
    /// The menu bar has no free right-click to hang the picker on, so it carries both.
    public static func menuBarItems(
        strings: MenuStrings,
        skinName: String,
        skins: [String],
        speechEnabled: Bool
    ) -> [MenuItem] {
        var items = items(strings: strings, skinName: skinName, speechEnabled: speechEnabled)

        guard !skins.isEmpty else { return items }

        items.append(.separator)
        items.append(contentsOf: skinPickerItems(
            strings: strings,
            skins: skins,
            currentSkin: skinName
        ))
        return items
    }
}
