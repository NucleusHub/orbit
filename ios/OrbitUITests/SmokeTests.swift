import XCTest

/// The main flows, end to end on sample data.
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetAll", "-sampleData", "-skipWelcome", "-signedIn", "-appearance", "dark", "-view", "list"]
        app.launch()
    }

    private func tapText(_ text: String, timeout: TimeInterval = 8) {
        let element = app.staticTexts[text].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(text) never showed")
        element.tap()
    }

    func testOpenFolderPreviewAndBack() {
        tapText("Photos")
        tapText("Beach.png")
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(app.staticTexts["Summer 2026"].waitForExistence(timeout: 3))
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Orbit"].waitForExistence(timeout: 3))
    }

    func testProtectedFolderRejectsWrongPassword() {
        tapText("Work")
        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("nope")
        app.buttons["Unlock"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Wrong password"].waitForExistence(timeout: 3))
        XCTAssertTrue(field.exists, "the prompt stays open")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "orbit")
        app.buttons["Unlock"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Contract.pdf"].waitForExistence(timeout: 5))
    }

    func testSelectTwoFiles() {
        XCTAssertTrue(app.staticTexts["Notes.md"].waitForExistence(timeout: 8))
        app.buttons["More"].tap()
        app.buttons["Select"].tap()
        app.staticTexts["Notes.md"].tap()
        app.staticTexts["Backup.zip"].tap()
        XCTAssertTrue(app.staticTexts["2 selected"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertFalse(app.staticTexts["2 selected"].exists)
    }

    func testNewFolderAppears() {
        XCTAssertTrue(app.staticTexts["Notes.md"].waitForExistence(timeout: 8))
        app.buttons["Add"].tap()
        app.buttons["New folder"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("Receipts\n")
        XCTAssertTrue(app.staticTexts["Receipts"].waitForExistence(timeout: 5))
    }

    func testSettingsHasSyncNow() {
        app.buttons["Settings"].firstMatch.tap()
        let sync = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sync now'")).firstMatch
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        sync.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Synced'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testSearchHitInProtectedFolderAsksToUnlock() {
        app.buttons["Search"].firstMatch.tap()
        app.typeText("contract")
        tapText("Contract.pdf")
        let unlock = app.buttons["Unlock"].firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
        unlock.tap()
        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("orbit")
        app.buttons["Unlock"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Share or save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["This file is in a protected folder."].exists)
    }

    func testDragFileOntoFolder() {
        app.terminate()
        app.launchArguments = ["-resetAll", "-sampleData", "-skipWelcome", "-signedIn", "-appearance", "dark", "-view", "grid"]
        app.launch()
        let notes = app.buttons["Notes.md"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 8))
        // A short lift starts the drag; a longer press opens the menu, which synthetic touches can't turn into a drag.
        notes.press(forDuration: 0.5, thenDragTo: app.buttons["Music"].firstMatch, withVelocity: .slow, thenHoldForDuration: 1.0)
        XCTAssertTrue(app.staticTexts["Moved “Notes.md” to Music"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Notes.md"].exists)
        app.buttons["Music"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Notes.md"].waitForExistence(timeout: 5))
    }

    // Preview pager and zoom

    func testSwipeBetweenFiles() {
        tapText("Lake at dawn.jpg")
        XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["2 of 5"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Team offsite.mov"].exists)
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 3))
    }

    func testZoomedImagePansInsteadOfPaging() {
        tapText("Lake at dawn.jpg")
        let photo = app.scrollViews["Lake at dawn.jpg"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        photo.doubleTap()
        sleep(1)
        photo.swipeLeft()
        XCTAssertTrue(app.staticTexts["1 of 5"].exists, "a zoomed photo pans, it doesn't change the file")
        photo.doubleTap()
        sleep(1)
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["2 of 5"].waitForExistence(timeout: 3))
    }
}

/// Face ID locks with a scripted Face ID (the simulator has no face).
final class FaceIDTests: XCTestCase {
    private func launch(faceID: String, lock: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "-sampleData", "-skipWelcome", "-signedIn", "-view", "list", "-faceID", faceID]
            + (lock.map { ["-faceIDLock", $0] } ?? [])
        app.launch()
        return app
    }

    func testFailedFaceIDKeepsStrictFolderClosed() {
        let app = launch(faceID: "fail", lock: "Photos:strict")
        let photos = app.staticTexts["Photos"].firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout: 8))
        photos.tap()
        XCTAssertTrue(app.staticTexts["Face ID didn't recognize you."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Summer 2026"].exists)
        XCTAssertFalse(app.secureTextFields.firstMatch.exists, "a strict lock offers no password")
    }

    func testPassingFaceIDOpensFolder() {
        let app = launch(faceID: "pass", lock: "Photos")
        let photos = app.staticTexts["Photos"].firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout: 8))
        photos.tap()
        XCTAssertTrue(app.staticTexts["Summer 2026"].waitForExistence(timeout: 5))
    }

    func testFaceIDFillsInSavedPasswordAfterBackground() {
        let app = launch(faceID: "pass", lock: "Work:strict")
        let work = app.staticTexts["Work"].firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 8))
        work.tap()
        // The first time on this device the server still needs the password once.
        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("orbit")
        app.buttons["Unlock"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Contract.pdf"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        let unlock = app.buttons["Unlock with Face ID"].firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), "relocked after the background")
        unlock.tap()
        XCTAssertTrue(app.staticTexts["Contract.pdf"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields.firstMatch.exists, "Face ID stood in for the password")
    }

    func testLockFromMenu() {
        let app = launch(faceID: "pass")
        let docs = app.staticTexts["Documents"].firstMatch
        XCTAssertTrue(docs.waitForExistence(timeout: 8))
        docs.press(forDuration: 1.2)
        app.buttons["Lock with Face ID"].tap()
        app.buttons["Face ID only"].tap()
        XCTAssertTrue(app.staticTexts["Locked with Face ID"].waitForExistence(timeout: 3))
    }
}
