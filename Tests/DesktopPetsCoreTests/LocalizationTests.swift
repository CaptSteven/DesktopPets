import Testing
@testable import DesktopPetsCore

@Suite struct LocalizationTests {
    // MARK: Language selection

    @Test func toggledFlipsBetweenTheTwoLanguages() {
        #expect(AppLanguage.chinese.toggled == .english)
        #expect(AppLanguage.english.toggled == .chinese)
        // Toggling twice is a round trip.
        #expect(AppLanguage.chinese.toggled.toggled == .chinese)
    }

    @Test func systemPreferencePicksChineseForChineseLocales() {
        #expect(AppLanguage.matching(preferredLanguages: ["zh-Hans-CN"]) == .chinese)
        #expect(AppLanguage.matching(preferredLanguages: ["zh"]) == .chinese)
        #expect(AppLanguage.matching(preferredLanguages: ["zh-TW"]) == .chinese)
        #expect(AppLanguage.matching(preferredLanguages: ["ZH-hans"]) == .chinese, "case should not matter")
    }

    @Test func systemPreferenceFallsBackToEnglish() {
        #expect(AppLanguage.matching(preferredLanguages: ["en-US"]) == .english)
        #expect(AppLanguage.matching(preferredLanguages: ["fr-FR", "zh-Hans"]) == .english,
                "only the first preference counts")
        #expect(AppLanguage.matching(preferredLanguages: []) == .english)
    }

    @Test func switchAnnouncementSpeaksTheLanguageBeingSwitchedTo() {
        // Each announcement has to be readable to someone who just chose that language.
        #expect(AppLanguage.chinese.switchAnnouncement == "已切换到中文")
        #expect(AppLanguage.english.switchAnnouncement == "Switched to English")
    }

    // MARK: Menu strings

    @Test func everyLanguageHasStringsForEveryItem() {
        // Written as a coverage loop so adding a language cannot silently leave a menu item blank.
        for language in AppLanguage.allCases {
            let strings = MenuStrings.forLanguage(language)

            for (label, value) in [
                ("skinFormat", strings.skinFormat),
                ("speak", strings.speak),
                ("switchLanguage", strings.switchLanguage),
                ("reload", strings.reload),
                ("resetPosition", strings.resetPosition),
                ("quit", strings.quit),
            ] {
                #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty,
                        "\(language.rawValue) is missing \(label)")
            }
        }
    }

    @Test func languagesAreActuallyDifferent() {
        let chinese = MenuStrings.forLanguage(.chinese)
        let english = MenuStrings.forLanguage(.english)

        #expect(chinese != english, "the two languages produced identical labels")
        #expect(chinese.speak != english.speak)
        #expect(chinese.quit != english.quit)
    }

    @Test func skinHeaderSubstitutesTheSkinName() {
        let chinese = MenuStrings.forLanguage(.chinese)
        let english = MenuStrings.forLanguage(.english)

        #expect(english.skinHeader(name: "placeholder") == "Skin: placeholder")
        #expect(chinese.skinHeader(name: "placeholder") == "皮肤：placeholder")
    }

    @Test func skinHeaderSurvivesANameWithFormatCharacters() {
        // A skin directory could legitimately contain a percent sign; that must not corrupt the row.
        let strings = MenuStrings.forLanguage(.english)
        #expect(strings.skinHeader(name: "100%cat") == "Skin: 100%cat")
    }

    @Test func switchAnnouncementsDifferPerLanguage() {
        let announcements = Set(AppLanguage.allCases.map(\.switchAnnouncement))
        #expect(announcements.count == AppLanguage.allCases.count,
                "two languages share an announcement, so the toggle would look like it did nothing")
    }
}
