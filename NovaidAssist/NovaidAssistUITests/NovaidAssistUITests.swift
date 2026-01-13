import XCTest

final class NovaidAssistUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Splash Screen Tests

    func testSplashScreenAppears() throws {
        // App should show splash screen on launch
        let splashLogo = app.staticTexts["Novaid"]
        XCTAssertTrue(splashLogo.waitForExistence(timeout: 2))
    }

    // MARK: - Role Selection Tests

    func testRoleSelectionScreenAppears() throws {
        // Wait for splash to disappear
        sleep(3)

        // Role selection should appear
        let selectRoleText = app.staticTexts["Select your role"]
        XCTAssertTrue(selectRoleText.waitForExistence(timeout: 5))
    }

    func testUserRoleButtonExists() throws {
        sleep(3)

        let userButton = app.buttons["User"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 5))
    }

    func testProfessionalRoleButtonExists() throws {
        sleep(3)

        let professionalButton = app.buttons["Professional"]
        XCTAssertTrue(professionalButton.waitForExistence(timeout: 5))
    }

    // MARK: - User Flow Tests

    func testUserHomeScreenNavigation() throws {
        sleep(3)

        // Tap User role
        let userButton = app.buttons["User"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 5))
        userButton.tap()

        // Verify user home screen
        let startCallButton = app.buttons["Start Call"]
        XCTAssertTrue(startCallButton.waitForExistence(timeout: 5))
    }

    func testDemoButtonExists() throws {
        sleep(3)

        let userButton = app.buttons["User"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 5))
        userButton.tap()

        let demoButton = app.buttons["Try Demo"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
    }

    func testUserIdDisplayed() throws {
        sleep(3)

        let userButton = app.buttons["User"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 5))
        userButton.tap()

        let yourIdLabel = app.staticTexts["Your ID"]
        XCTAssertTrue(yourIdLabel.waitForExistence(timeout: 5))
    }

    // MARK: - Professional Flow Tests

    func testProfessionalHomeScreenNavigation() throws {
        sleep(3)

        // Tap Professional role
        let professionalButton = app.buttons["Professional"]
        XCTAssertTrue(professionalButton.waitForExistence(timeout: 5))
        professionalButton.tap()

        // Verify professional home screen
        let waitingText = app.staticTexts["Waiting for calls..."]
        XCTAssertTrue(waitingText.waitForExistence(timeout: 5))
    }

    func testProfessionalIdDisplayed() throws {
        sleep(3)

        let professionalButton = app.buttons["Professional"]
        XCTAssertTrue(professionalButton.waitForExistence(timeout: 5))
        professionalButton.tap()

        let professionalIdLabel = app.staticTexts["Professional ID"]
        XCTAssertTrue(professionalIdLabel.waitForExistence(timeout: 5))
    }

    // MARK: - Demo Mode Tests

    func testDemoModeNavigation() throws {
        sleep(3)

        // Navigate to user home
        let userButton = app.buttons["User"]
        XCTAssertTrue(userButton.waitForExistence(timeout: 5))
        userButton.tap()

        // Tap demo button
        let demoButton = app.buttons["Try Demo"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        demoButton.tap()

        // Should navigate to video call
        // In demo mode, we show the video call UI
        sleep(2)
    }

    // MARK: - Launch Performance

    func testLaunchPerformance() throws {
        if #available(iOS 13.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
