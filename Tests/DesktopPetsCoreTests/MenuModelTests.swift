import CoreGraphics
import Testing
@testable import DesktopPetsCore

@Suite struct MenuModelTests {
    let chinese = MenuStrings.forLanguage(.chinese)
    let english = MenuStrings.forLanguage(.english)

    // MARK: Structure

    @Test func menuHasAHeaderAndEveryAction() {
        let items = PetMenuModel.items(strings: english, skinName: "placeholder", speechEnabled: true)

        #expect(items.first == .header("Skin: placeholder"))
        #expect(items.contains(.separator))

        let actions = items.compactMap(\.action)
        #expect(Set(actions) == Set(MenuAction.allCases),
                "every action must be reachable from the menu")
    }

    @Test func bothLanguagesProduceTheSameStructure() {
        // The two menus must differ only in wording. If one language is missing a row, users of
        // that language silently lose a feature.
        let zh = PetMenuModel.items(strings: chinese, skinName: "cat", speechEnabled: true)
        let en = PetMenuModel.items(strings: english, skinName: "cat", speechEnabled: true)

        #expect(zh.count == en.count)

        for (lhs, rhs) in zip(zh, en) {
            #expect(lhs.action == rhs.action, "row order diverged: \(lhs) vs \(rhs)")
            #expect((lhs.title == nil) == (rhs.title == nil))
            #expect(lhs.isOn == rhs.isOn)
            #expect(lhs.isSelectable == rhs.isSelectable)
        }
    }

    @Test func everyTitledRowHasNonEmptyTextInBothLanguages() {
        for strings in [chinese, english] {
            let items = PetMenuModel.items(strings: strings, skinName: "cat", speechEnabled: false)
            for item in items {
                if let title = item.title {
                    #expect(!title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @Test func headerCarriesTheSkinName() {
        let zh = PetMenuModel.items(strings: chinese, skinName: "mypet", speechEnabled: true)
        #expect(zh.first == .header("皮肤：mypet"))
    }

    // MARK: Speech toggle

    @Test func speechToggleReflectsTheSetting() throws {
        let on = PetMenuModel.items(strings: english, skinName: "cat", speechEnabled: true)
        let off = PetMenuModel.items(strings: english, skinName: "cat", speechEnabled: false)

        let onToggle = try #require(on.first { $0.action == .toggleSpeech })
        let offToggle = try #require(off.first { $0.action == .toggleSpeech })

        #expect(onToggle.isOn)
        #expect(!offToggle.isOn)
        // Only the checkbox differs; the row itself stays in place.
        #expect(onToggle.title == offToggle.title)
    }

    // MARK: Selectability

    @Test func headersAndSeparatorsAreNotSelectable() {
        #expect(!MenuItem.header("x").isSelectable)
        #expect(!MenuItem.separator.isSelectable)
        #expect(MenuItem.action(.quit, title: "q").isSelectable)
        #expect(MenuItem.toggle(.toggleSpeech, title: "s", isOn: true).isSelectable)
    }

    @Test func onlyTogglesReportBeingOn() {
        #expect(MenuItem.toggle(.toggleSpeech, title: "s", isOn: true).isOn)
        #expect(!MenuItem.toggle(.toggleSpeech, title: "s", isOn: false).isOn)
        #expect(!MenuItem.action(.quit, title: "q").isOn)
        #expect(!MenuItem.header("h").isOn)
        #expect(!MenuItem.separator.isOn)
    }

    @Test func selectableItemsKeepsOnlyChoosableRows() {
        let items = PetMenuModel.items(strings: english, skinName: "cat", speechEnabled: true)
        let selectable = PetMenuModel.selectableItems(in: items)

        #expect(selectable.count == MenuAction.allCases.count)
        #expect(selectable.allSatisfy { $0.isSelectable })
    }

    @Test func quitIsPresentInEveryLanguage() {
        // The single most important row: without it there is no way out of the app.
        for strings in [chinese, english] {
            let items = PetMenuModel.items(strings: strings, skinName: "cat", speechEnabled: true)
            #expect(items.contains { $0.action == .quit })

            let quit = items.first { $0.action == .quit }
            #expect(quit?.title?.isEmpty == false)
        }
    }
}

@Suite struct MenuPanelLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let panel = CGSize(width: 180, height: 200)

    // MARK: Placement

    @Test func opensDownwardsWithItsTopEdgeAtTheClick() {
        let point = CGPoint(x: 400, y: 500)
        let origin = MenuPanelLayout.origin(size: panel, at: point, within: screen)

        #expect(origin.x == 400)
        // Origin is the bottom-left, so bottom + height lands on the click.
        #expect(origin.y == 300)
        #expect(origin.y + panel.height == point.y)
    }

    @Test func flipsUpwardsWhenThereIsNoRoomBelow() {
        let point = CGPoint(x: 400, y: 50)
        let origin = MenuPanelLayout.origin(size: panel, at: point, within: screen)

        // Now the *bottom* edge sits at the click, so the panel opens upwards instead of off-screen.
        #expect(origin.y == 50)
        #expect(origin.y >= screen.minY)
    }

    @Test func isPulledInsideTheRightEdge() {
        let origin = MenuPanelLayout.origin(
            size: panel,
            at: CGPoint(x: 1439, y: 500),
            within: screen
        )
        // Typed explicitly: inline arithmetic on the right of == infers Int and compares unequal
        // for equal numbers. See the note at the top of TestSupport.swift.
        let expectedX: CGFloat = 1440 - 180 - 4
        #expect(origin.x == expectedX)
    }

    @Test func isPulledInsideTheLeftEdge() {
        let origin = MenuPanelLayout.origin(
            size: panel,
            at: CGPoint(x: -50, y: 500),
            within: screen
        )
        #expect(origin.x == 4)
    }

    @Test func staysInsideTheScreenForEveryClickPoint() {
        for x in stride(from: -100.0, through: 1600.0, by: 50) {
            for y in stride(from: -100.0, through: 1000.0, by: 50) {
                let origin = MenuPanelLayout.origin(
                    size: panel,
                    at: CGPoint(x: x, y: y),
                    within: screen
                )
                #expect(origin.x >= screen.minX, "x escaped at (\(x), \(y))")
                #expect(origin.x + panel.width <= screen.maxX, "x overflowed at (\(x), \(y))")
                #expect(origin.y >= screen.minY, "y escaped at (\(x), \(y))")
                #expect(origin.y + panel.height <= screen.maxY, "y overflowed at (\(x), \(y))")
            }
        }
    }

    @Test func handlesAScreenWithANegativeOrigin() {
        let leftScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let origin = MenuPanelLayout.origin(
            size: panel,
            at: CGPoint(x: -1920, y: 500),
            within: leftScreen
        )

        let expectedX: CGFloat = -1920 + 4
        #expect(origin.x == expectedX)
    }

    @Test func collapsesGracefullyWhenThePanelIsLargerThanTheScreen() {
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
        let huge = CGSize(width: 400, height: 400)

        let origin = MenuPanelLayout.origin(size: huge, at: CGPoint(x: 50, y: 50), within: tiny)

        // Pinned to the margin rather than producing an inverted range or a NaN.
        #expect(origin.x == 4)
        #expect(origin.y == 4)
    }

    // MARK: Row hit testing

    @Test func heightAddsUpEveryRowPlusPadding() {
        let metrics = MenuPanelMetrics(rowHeight: 26, headerRowHeight: 20, separatorHeight: 9, padding: 5)
        let items = PetMenuModel.items(strings: .forLanguage(.english), skinName: "cat", speechEnabled: true)

        let expected = 10 + items.reduce(0.0) { $0 + metrics.height(of: $1) }
        #expect(metrics.height(for: items) == expected)
    }

    @Test func clickingARowResolvesToThatRow() {
        let metrics = MenuPanelMetrics()
        let items = PetMenuModel.items(strings: .forLanguage(.english), skinName: "cat", speechEnabled: true)

        for (index, item) in items.enumerated() where item.isSelectable {
            let top = metrics.offsetFromTop(ofItemAt: index, in: items)
            let middle = top + metrics.height(of: item) / 2

            #expect(metrics.itemIndex(atOffsetFromTop: middle, in: items) == index,
                    "row \(index) did not resolve; item = \(item)")
        }
    }

    @Test func clickingDecorationResolvesToNothing() {
        let metrics = MenuPanelMetrics()
        let items = PetMenuModel.items(strings: .forLanguage(.english), skinName: "cat", speechEnabled: true)

        // The header is index 0, and the first separator is index 1.
        let headerMiddle = metrics.offsetFromTop(ofItemAt: 0, in: items) + metrics.headerRowHeight / 2
        #expect(metrics.itemIndex(atOffsetFromTop: headerMiddle, in: items) == nil)

        let separatorMiddle = metrics.offsetFromTop(ofItemAt: 1, in: items) + metrics.separatorHeight / 2
        #expect(metrics.itemIndex(atOffsetFromTop: separatorMiddle, in: items) == nil)
    }

    @Test func clickingPaddingOrBeyondThePanelResolvesToNothing() {
        let metrics = MenuPanelMetrics()
        let items = PetMenuModel.items(strings: .forLanguage(.english), skinName: "cat", speechEnabled: true)
        let total = metrics.height(for: items)

        // Inside the top padding.
        #expect(metrics.itemIndex(atOffsetFromTop: 1, in: items) == nil)
        // Past the last row.
        #expect(metrics.itemIndex(atOffsetFromTop: total + 10, in: items) == nil)
        // Exactly at the bottom edge.
        #expect(metrics.itemIndex(atOffsetFromTop: total, in: items) == nil)
    }

    @Test func rowOffsetsAreMonotonic() {
        let metrics = MenuPanelMetrics()
        let items = PetMenuModel.items(strings: .forLanguage(.english), skinName: "cat", speechEnabled: true)

        var previous = -1.0
        for index in items.indices {
            let offset = metrics.offsetFromTop(ofItemAt: index, in: items)
            #expect(offset > previous, "offsets must increase; row \(index)")
            previous = offset
        }
    }
}
