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
        showInspector(app)
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
        showInspector(app)
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

        let tool = app.descendants(matching: .any)["Current tool"].firstMatch
        XCTAssertTrue(tool.waitForExistence(timeout: 5), "the inspector names the tool")

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

    /// Build step 3 (Blueprint 036 / 037 / 033): a new picture's layers, + Add Layer, the eye,
    /// and ⌘Z / ⇧⌘Z stepping History through Apple's standard Edit ▸ Undo / Redo.
    @MainActor
    func testLayersAndHistoryUndo() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        showInspector(app)
        let any = app.descendants(matching: .any)
        let layersTab = app.radioButtons["Layers"].firstMatch
        XCTAssertTrue(layersTab.waitForExistence(timeout: 10), "the right column has a Layers tab")
        layersTab.click()

        for name in ["Light", "Dark", "Layer 1"] {
            XCTAssertTrue(app.buttons[name].firstMatch.exists, "a new picture starts with \(name)")
        }
        XCTAssertEqual(text(any["Selected layer"].firstMatch), "Layer 1", "the content layer starts selected")

        app.buttons["Add Layer"].firstMatch.click()
        XCTAssertTrue(app.buttons["Layer 2"].firstMatch.waitForExistence(timeout: 5), "+ adds Layer 2")
        XCTAssertEqual(text(any["Selected layer"].firstMatch), "Layer 2", "the new layer is selected")
        app.buttons["Dark"].firstMatch.click()
        XCTAssertEqual(text(any["Selected layer"].firstMatch), "Dark", "clicking a name selects that layer")
        app.buttons["Layer 2"].firstMatch.click()

        app.typeKey("z", modifierFlags: .command)
        XCTAssertFalse(app.buttons["Layer 2"].firstMatch.waitForExistence(timeout: 2), "⌘Z steps History back")
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["Layer 2"].firstMatch.waitForExistence(timeout: 5), "⇧⌘Z steps forward")

        app.buttons["Hide Layer 1"].firstMatch.click()
        XCTAssertTrue(app.buttons["Show Layer 1"].firstMatch.waitForExistence(timeout: 5), "the eye hides a layer")

        app.menuBars.menuBarItems["Edit"].click()
        let undo = app.menuBars.menuBarItems["Edit"].menuItems["Undo"]
        XCTAssertTrue(undo.exists && undo.isEnabled, "Apple's standard Edit ▸ Undo is back, bound to History")
        app.typeKey(.escape, modifierFlags: [])

        app.radioButtons["History"].firstMatch.click()
        for step in ["Original", "Add Layer", "Hide Layer"] {
            XCTAssertTrue(app.descendants(matching: .any)["History step \(step)"].firstMatch.waitForExistence(timeout: 5),
                          "History lists \(step)")
        }
        // His lock 13:11: Optimize and Purge are their own buttons and File menu items.
        app.buttons["Optimize History"].firstMatch.click()
        XCTAssertEqual(app.descendants(matching: .any)["Status"].firstMatch.value as? String,
                       "History is already as small as it can be")
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuItems["Optimize History"].exists && app.menuItems["Purge History…"].exists,
                      "File ▸ Optimize History and Purge History…")
        app.typeKey(.escape, modifierFlags: [])
        app.descendants(matching: .any)["History step Original"].firstMatch.click()
        XCTAssertEqual(app.descendants(matching: .any)["Status"].firstMatch.value as? String, "Looking at “Original”", "clicking a step looks at it; row hittable=\(app.descendants(matching: .any)["History step Original"].firstMatch.isHittable) frame=\(app.descendants(matching: .any)["History step Original"].firstMatch.frame) type=\(app.descendants(matching: .any)["History step Original"].firstMatch.elementType.rawValue) window=\(app.windows.firstMatch.frame)")
        app.radioButtons["Layers"].firstMatch.click()
        XCTAssertFalse(app.buttons["Layer 2"].firstMatch.waitForExistence(timeout: 2),
                       "looking at the Original shows its layers")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Layer 2"].firstMatch.waitForExistence(timeout: 5),
                      "⌘Z after a look goes back to where you were")
        #endif
    }

    /// Build step 4a (Blueprint 029 / 043 / 044): the tool box, the Canvas tool (every picture
    /// opens on it; a new size is a History step), and the Palette tool.
    @MainActor
    func testToolBoxCanvasAndPalette() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        showInspector(app)
        let any = app.descendants(matching: .any)
        XCTAssertTrue(app.buttons["Canvas"].firstMatch.waitForExistence(timeout: 10), "the tool box has Canvas")
        XCTAssertTrue(app.buttons["Palette"].firstMatch.exists, "the tool box has Palette")
        XCTAssertEqual(text(any["Current tool"].firstMatch), "Canvas", "every picture opens on the Canvas tool")

        let height = app.textFields["Height"].firstMatch
        func size() -> String { "\(app.textFields["Width"].firstMatch.value as? String ?? "?") by \(height.value as? String ?? "?")" }
        XCTAssertEqual(size(), "1,024 by 1,024")
        let width = app.textFields["Width"].firstMatch
        width.click()
        width.typeKey("a", modifierFlags: .command)
        width.typeText("800\t")
        app.buttons["Apply Size"].firstMatch.click()
        XCTAssertEqual(size(), "800 by 1,024", "Apply Size changes the canvas")
        app.buttons["Swap Width and Height"].firstMatch.click()
        XCTAssertEqual(size(), "1,024 by 800", "swap makes it landscape")
        app.typeKey("z", modifierFlags: .command)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(size(), "1,024 by 1,024", "Undo steps the size back through History")

        app.buttons["Palette"].firstMatch.click()
        XCTAssertEqual(text(any["Current tool"].firstMatch), "Palette")
        XCTAssertTrue(app.buttons["Color 8, #AF52DE"].firstMatch.waitForExistence(timeout: 5), "eight starting colors")
        XCTAssertFalse(app.buttons["Remove"].firstMatch.isEnabled, "the palette never drops below eight")
        app.buttons["Add Color"].firstMatch.click()
        XCTAssertTrue(app.buttons["Color 9, #000000"].firstMatch.waitForExistence(timeout: 5), "Add Color grows the palette")
        XCTAssertTrue(app.buttons["Remove"].firstMatch.isEnabled)
        #endif
    }

    /// Build step 4b (Blueprint 049–052): Fill Layer, Pen squares, Eraser brush, Paint Bucket
    /// pour and Eyedropper — each result lands on a new layer, original hidden.
    @MainActor
    func testDrawingTools() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        showInspector(app)
        let any = app.descendants(matching: .any)
        let status = any["Status"].firstMatch
        let canvas = any["Canvas picture"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        app.radioButtons["Layers"].firstMatch.click()

        // Fill Layer on the Light floor takes the color as its fill (no new layer).
        app.buttons["Light"].firstMatch.click()
        app.buttons["Paint Bucket"].firstMatch.click()
        app.buttons["Fill Layer"].firstMatch.click()
        XCTAssertEqual(status.value as? String, "Filled the layer")

        // Pen on Layer 1: one stroke = one new layer, "Layer 1 (Pixel 1)".
        app.buttons["Layer 1"].firstMatch.click()
        app.buttons["Pen"].firstMatch.click()
        // REM: XCUITest drags do not reach SwiftUI's DragGesture on the Mac (clicks do), so the
        // robot draws with clicks: one click = one square / one eraser dab, same code path.
        canvas.click()
        XCTAssertTrue(app.buttons["Layer 1 (Pixel 1)"].firstMatch.waitForExistence(timeout: 5), "a pen stroke forks a layer")
        XCTAssertTrue(app.buttons["Show Layer 1"].firstMatch.exists, "the original is hidden")

        // Eraser brush across the squares.
        app.buttons["Eraser"].firstMatch.click()
        canvas.click()
        XCTAssertTrue(app.buttons["Layer 1 (Erase 1)"].firstMatch.waitForExistence(timeout: 5), "erasing forks a layer")

        // Paint Bucket pour.
        app.buttons["Paint Bucket"].firstMatch.click()
        canvas.click()
        XCTAssertTrue(app.buttons["Layer 1 (Fill 1)"].firstMatch.waitForExistence(timeout: 5), "a pour forks a layer")

        // Eyedropper picks a color into the palette.
        app.buttons["Eyedropper"].firstMatch.click()
        canvas.click()
        XCTAssertTrue((status.value as? String ?? "").hasPrefix("Picked #"), "the eyedropper picks a color")

        // Every step is in History, and Undo takes the pour back.
        app.typeKey("z", modifierFlags: .command)
        XCTAssertFalse(app.buttons["Layer 1 (Fill 1)"].firstMatch.waitForExistence(timeout: 2), "Undo removes the pour")
        #endif
    }

    /// Build step 4c (Blueprint 053–055): a text line becomes a layer named after its words and
    /// restyles live; a symbol layer is created and swapped in place; New from Import… is in File.
    @MainActor
    func testTextSymbolImage() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        showInspector(app)
        let status = app.descendants(matching: .any)["Status"].firstMatch
        XCTAssertTrue(app.buttons["Text"].firstMatch.waitForExistence(timeout: 10))
        app.radioButtons["Layers"].firstMatch.click()

        app.buttons["Text"].firstMatch.click()
        let field = app.textFields["Text"].firstMatch
        field.click()
        field.typeText("Hello\r")
        XCTAssertTrue(app.buttons["Hello"].firstMatch.waitForExistence(timeout: 5), "Return makes a text layer named after its words")
        let bold = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Bold")).firstMatch
        XCTAssertTrue(bold.waitForExistence(timeout: 5), "Bold sits under the text box")
        bold.click()
        XCTAssertEqual(status.value as? String, "Restyled “Hello”", "style changes apply live to the selected text")

        app.buttons["Symbol"].firstMatch.click()
        app.buttons["heart.fill"].firstMatch.click()
        app.buttons["Create New Layer"].firstMatch.click()
        XCTAssertTrue(app.buttons["heart.fill"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "Added heart.fill")
        let search = app.textFields["Search symbols"].firstMatch
        search.click()
        search.typeText("star.fill")
        app.buttons["star.fill"].firstMatch.click()
        app.buttons["Apply to Selected Layer"].firstMatch.click()
        XCTAssertEqual(status.value as? String, "Swapped to star.fill", "Apply swaps the symbol in place")

        app.buttons["Image"].firstMatch.click()
        XCTAssertTrue(app.buttons["Import Image to New Layer…"].firstMatch.waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuItems["New from Import…"].exists, "File ▸ New from Import…")
        app.typeKey(.escape, modifierFlags: [])
        #endif
    }
}

/// A static text's words: macOS reports them as the value, iOS as the label.
private func text(_ element: XCUIElement) -> String {
    let value = element.value as? String ?? ""
    return value.isEmpty ? element.label : value
}

/// The inspector's open/closed state is remembered between launches (his rule), so a test
/// that needs it opens it first.
@MainActor
private func showInspector(_ app: XCUIApplication) {
    #if os(macOS)
    let show = app.buttons["Show Inspector"].firstMatch
    if show.waitForExistence(timeout: 3) { show.click() }
    #endif
}
