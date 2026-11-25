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

    /// Build step 2 (Blueprint 029): View-menu zoom shortcuts, the tappable zoom level, the
    /// status line, canvas focus and the inspector's canvas size.
    @MainActor
    func testZoomFocusStatusAndInspector() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        let level = app.descendants(matching: .any)["Zoom level"].firstMatch
        XCTAssertTrue(level.waitForExistence(timeout: 10), "the Zoom panel shows the zoom level")
        let status = app.descendants(matching: .any)["Status"].firstMatch
        XCTAssertTrue(status.exists, "the status line is on screen")

        app.typeKey("0", modifierFlags: .command)
        XCTAssertEqual(level.value as? String, "100%", "⌘0 is Actual Size")
        XCTAssertEqual(status.value as? String, "Zoomed to 100%", "the status line reports the zoom")

        app.typeKey("=", modifierFlags: .command)
        XCTAssertEqual(level.value as? String, "150%", "⌘= steps up from 100% to 150%")
        app.typeKey("-", modifierFlags: .command)
        app.typeKey("-", modifierFlags: .command)
        XCTAssertEqual(level.value as? String, "67%", "⌘− steps down evenly: 150 → 100 → 67")

        level.click()
        XCTAssertEqual(level.value as? String, "100%", "clicking the zoom level returns to 100%")

        let size = app.descendants(matching: .any)["Canvas size"].firstMatch
        XCTAssertTrue(size.waitForExistence(timeout: 5), "the inspector shows the canvas size")

        app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertFalse(level.waitForExistence(timeout: 2), "canvas focus hides the Zoom panel")
        let exit = app.buttons["Exit Canvas Focus"].firstMatch
        XCTAssertTrue(exit.exists, "canvas focus keeps one way back on screen")
        exit.click()
        XCTAssertTrue(level.waitForExistence(timeout: 5), "leaving focus brings the Zoom panel back")
        XCTAssertTrue(app.descendants(matching: .any)["Floating preview"].firstMatch.exists,
                      "the floating preview switch is in the Zoom panel")
        #endif
    }
}
