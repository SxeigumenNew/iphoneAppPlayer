import XCTest

@MainActor
final class ImportPickerTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFolderAndFilePickersOpenAfterCancellationOnBothTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // Opening the folder picker first reproduces the original broken path.
        openAndCancel("importFolders", in: app)
        openAndCancel("importAudioFiles", in: app)
        openAndCancel("importFolders", in: app)

        app.tabBars.buttons["Папки"].tap()
        openAndCancel("importFolders", in: app)
        openAndCancel("importAudioFiles", in: app)
    }

    private func openAndCancel(_ action: String, in app: XCUIApplication) {
        let addMusic = app.buttons["addMusic"]
        XCTAssertTrue(addMusic.waitForExistence(timeout: 10))
        // SwiftUI toolbar menus can lack the AX scroll action used by tap().
        // Tap the visible centre as a finger would; still assert the actual
        // menu item and system picker below.
        addMusic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let title = action == "importFolders" ? "Выбрать папки" : "Выбрать файлы"
        let menuItem = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", action, title)).firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), app.debugDescription)
        menuItem.tap()

        // This is the system document picker's Cancel button, rather than a
        // Pulse state flag: the test must observe an actually presented picker.
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Отменить", "Отмена"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "System picker did not open for \(action).\n\(app.debugDescription)")
        cancel.tap()
        let returned = NSPredicate(format: "exists == false")
        expectation(for: returned, evaluatedWith: cancel)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Cancelling import must not present an error")
    }
}
