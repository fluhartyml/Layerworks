//
//  LayerworksUITests.swift
//  LayerworksUITests
//
//  Created by Michael Fluharty on 11/25/26.
//

import XCTest

// REM: His rule — drive every app through the accessibility tree and keyboard shortcuts, not
// screenshots and clicks. His word 2026-11-25: "run your robot tests while you are building."
// Each build step adds its own tests here; every control is found by its accessibility label.

final class LayerworksUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Build step 1: ⌘N makes a new Untitled picture with a canvas (Blueprint 019/021).
    @MainActor
    func testNewImageOpensUntitledCanvas() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        let canvas = app.descendants(matching: .any)["Canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "⌘N should open a window with a canvas")
        XCTAssertTrue(app.windows.firstMatch.title.hasPrefix("Untitled"),
                      "a new picture is Untitled until the first Save, got \(app.windows.firstMatch.title)")
        // Blueprint 027: Save As… is in plain sight and Duplicate is off the File menu.
        let file = app.menuBars.menuBarItems["File"]
        file.click()
        XCTAssertTrue(app.menuItems["Save As…"].exists, "Save As… should be in the File menu")
        XCTAssertFalse(app.menuItems["Duplicate"].exists, "Duplicate should be off the File menu")
        app.typeKey(.escape, modifierFlags: [])
        #endif
    }
}
