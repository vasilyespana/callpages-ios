import XCTest

/// MVR-VP 4-stage flow on the Xcode Simulator with stub fixtures
/// (-uitest-stub): [1] App Launch & Mock Auth → [2] FTUE Onboarding →
/// [3] Create Object/Page → [4] Navigate/Edit Object.
///
/// Screenshots are saved as XCTAttachments and exported by CI as the
/// `ios-simulator-screenshots` artifact. This is SIMULATOR proof with
/// demo data — never real-device proof (our IPAs are unsigned; see
/// ios/IOS-PARITY.md).
final class FlowScreenshotsUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchStub(emptyAccount: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = emptyAccount
            ? ["-uitest-stub", "-uitest-stub-empty"]
            : ["-uitest-stub"]
        app.launch()
        return app
    }

    /// Stages 2+3: a brand-new account (zero pages) lands in onboarding,
    /// fills the business details, picks a template, and the page is
    /// created natively.
    func testFTUEOnboardingAndCreatePage() {
        let app = launchStub(emptyAccount: true)

        let nameField = app.textFields["Business name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 15))
        snap(app, "stage2-ftue-details")

        nameField.tap()
        nameField.typeText("New Demo Business")
        app.buttons["Continue"].tap()

        let salesTemplate = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "Sales")).firstMatch
        XCTAssertTrue(salesTemplate.waitForExistence(timeout: 10))
        snap(app, "stage3-template-picker")
        salesTemplate.tap()

        let ready = app.staticTexts["Your page is ready!"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15))
        snap(app, "stage3-page-created")
    }

    /// Stages 1+4: mock-auth launch into the signed-in shell, then
    /// navigate the objects: page → products, call → transcript call
    /// log, appointments list.
    func testMainFlowNavigation() {
        let app = launchStub(emptyAccount: false)

        let pagesTab = app.tabBars.buttons["Pages"]
        XCTAssertTrue(pagesTab.waitForExistence(timeout: 15))
        snap(app, "stage1-launch-mock-auth")

        // Pages → page detail with real products from config.
        pagesTab.tap()
        let shopRow = app.staticTexts["Sleep Shop — Demo"]
        XCTAssertTrue(shopRow.waitForExistence(timeout: 10))
        snap(app, "stage4-pages-list")
        shopRow.tap()
        let product = app.staticTexts["Frame Queen"]
        XCTAssertTrue(product.waitForExistence(timeout: 10))
        snap(app, "stage4-page-products")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Calls → call detail with the transcript rendered as call log.
        app.tabBars.buttons["Calls"].tap()
        let callRow = app.staticTexts["María Demo"]
        XCTAssertTrue(callRow.waitForExistence(timeout: 10))
        callRow.tap()
        // Section headers render uppercased ("CALL LOG") in the
        // accessibility tree — match case-insensitively.
        let callLog = app.staticTexts.containing(
            NSPredicate(format: "label ==[c] %@", "Call log")).firstMatch
        XCTAssertTrue(callLog.waitForExistence(timeout: 10))
        let transcriptLine = app.staticTexts["Sí, tenemos el Frame Queen en $110. ¿Desea recogerlo hoy?"]
        XCTAssertTrue(transcriptLine.waitForExistence(timeout: 10))
        snap(app, "stage4-call-log-transcript")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Appointments list.
        app.tabBars.buttons["Appointments"].tap()
        let appointment = app.staticTexts["María Demo"]
        XCTAssertTrue(appointment.waitForExistence(timeout: 10))
        snap(app, "stage4-appointments")
    }
}
