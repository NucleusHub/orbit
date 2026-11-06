import XCTest

/// Opens every screen on sample data and keeps a screenshot of each (set TEST_RUNNER_SHOT_DIR to save them).
final class ScreenshotTests: XCTestCase {
    private func shoot(_ name: String, args: [String], wait: UInt32 = 3, _ before: ((XCUIApplication) -> Void)? = nil) {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "-sampleData", "-skipWelcome", "-signedIn"] + (args.contains("-appearance") ? [] : ["-appearance", "dark"]) + args
        app.launch()
        sleep(wait)
        before?(app)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        app.terminate()
    }

    func testScreens() {
        shoot("01-root-grid", args: [])
        shoot("02-root-list", args: ["-view", "list"])
        shoot("03-folder", args: ["-route", "folder:Photos"])
        shoot("04-preview", args: ["-route", "preview:Lake at dawn.jpg"])
        shoot("05-pdf", args: ["-route", "preview:Budget 2027.pdf"])
        shoot("06-unlock", args: ["-route", "folder:Work"])
        shoot("07-move", args: ["-route", "move:Notes.md"])
        shoot("08-settings", args: ["-route", "settings"])
        shoot("09-profile", args: ["-route", "profile"])
        shoot("10-search", args: ["-route", "search"]) { app in app.typeText("o"); sleep(1) }
        shoot("11-new-folder", args: ["-route", "newfolder"])
        shoot("12-light", args: ["-appearance", "light"])
        shoot("13-menu", args: ["-view", "list"]) { app in
            app.staticTexts["Notes.md"].press(forDuration: 1.2)
            sleep(1)
        }
    }

    func testWelcomeAndSignIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "-appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.buttons["Sign in with Nucleus ID"].firstMatch.waitForExistence(timeout: 5))
        shoot("14-welcome", args: ["-route", "welcome"])
        shoot("15-signin", args: ["-route", "signin"])
    }

    func testCzech() {
        shoot("16-cs-root", args: ["-AppleLanguages", "(cs)", "-AppleLocale", "cs_CZ", "-view", "list"])
        shoot("17-cs-settings", args: ["-AppleLanguages", "(cs)", "-AppleLocale", "cs_CZ", "-route", "settings"])
    }
}
