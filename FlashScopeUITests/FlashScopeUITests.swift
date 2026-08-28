import XCTest

final class FlashScopeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEmptyState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--simulate-empty"]
        app.launch()

        let exists = app.otherElements["empty-state"].waitForExistence(timeout: 3)
        XCTAssertTrue(exists)
    }

    @MainActor
    func testDriveSelectionAndHealthCheckConfirmation() throws {
        let app = simulatedApp()
        app.launch()

        let firstDrive = app.descendants(matching: .any)["sidebar-drive-sim-disk-0"]
        let driveExists = firstDrive.waitForExistence(timeout: 3)
        XCTAssertTrue(driveExists)
        firstDrive.click()

        let overviewExists = app.otherElements["overview-card"].waitForExistence(timeout: 3)
        XCTAssertTrue(overviewExists)
        app.buttons["health-check-button"].click()

        let sheetExists = app.otherElements["health-check-sheet"].waitForExistence(timeout: 2)
        let confirmExists = app.buttons["confirm-start-benchmark-button"].exists
        XCTAssertTrue(sheetExists)
        XCTAssertTrue(confirmExists)
    }

    @MainActor
    func testProgressAndCancellation() throws {
        let app = simulatedApp()
        app.launch()
        app.descendants(matching: .any)["sidebar-drive-sim-disk-0"].click()
        app.buttons["health-check-button"].click()
        app.buttons["confirm-start-benchmark-button"].click()

        let progressExists = app.descendants(matching: .any)["benchmark-progress"].waitForExistence(timeout: 2)
        XCTAssertTrue(progressExists)

        let cancelButton = app.buttons["cancel-benchmark-button"]
        if cancelButton.exists {
            cancelButton.click()
        }
    }

    @MainActor
    func testDriveRemovalFixturePresentsStorageError() throws {
        let app = simulatedApp()
        app.launch()

        let removed = app.descendants(matching: .any)["sidebar-drive-sim-disk-9"]
        let removedExists = removed.waitForExistence(timeout: 3)
        XCTAssertTrue(removedExists)
        removed.click()
        app.buttons["health-check-button"].click()
        app.buttons["confirm-start-benchmark-button"].click()

        let alertExists = app.alerts.firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(alertExists)
    }

    @MainActor
    func testFindingsAndAccessibilityIdentifiers() throws {
        let app = simulatedApp()
        app.launch()
        app.descendants(matching: .any)["sidebar-drive-sim-disk-4"].click()

        let findingsExists = app.otherElements["findings-card"].waitForExistence(timeout: 3)
        let connectionExists = app.otherElements["connection-card"].exists
        let filesystemExists = app.otherElements["filesystem-card"].exists
        XCTAssertTrue(findingsExists)
        XCTAssertTrue(connectionExists)
        XCTAssertTrue(filesystemExists)
    }

    @MainActor
    func testExportFlowOpensSavePanel() throws {
        let app = simulatedApp()
        app.launch()
        app.descendants(matching: .any)["sidebar-drive-sim-disk-0"].click()

        let menu = app.buttons["export-menu"]
        let menuExists = menu.waitForExistence(timeout: 3)
        XCTAssertTrue(menuExists)
        menu.click()
        app.menuItems["JSON Report…"].click()

        let sheetExists = app.sheets.firstMatch.waitForExistence(timeout: 2)
        let dialogExists = app.dialogs.firstMatch.waitForExistence(timeout: 2)
        XCTAssertTrue(sheetExists || dialogExists)
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    private func simulatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--simulate"]
        return app
    }
}
