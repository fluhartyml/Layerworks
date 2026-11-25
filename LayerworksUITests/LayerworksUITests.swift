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
        XCTAssertTrue(app.buttons["Canvas Tool"].firstMatch.waitForExistence(timeout: 10), "the tool box has Canvas Tool")
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
        type("Hello\r", into: field)
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
        type("star.fill", into: search)
        XCTAssertTrue(app.buttons["star.fill"].firstMatch.waitForExistence(timeout: 5))
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

    /// Build step 4d1 (Blueprint 045): Move by typed position, Done keeps it on a new layer with
    /// the original hidden, Undo steps back, Crop makes a "(Crop 1)" layer, leaving the tool commits.
    @MainActor
    func testMoveAndCrop() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        showInspector(app)
        let status = app.descendants(matching: .any)["Status"].firstMatch
        XCTAssertTrue(app.buttons["Text"].firstMatch.waitForExistence(timeout: 10))
        app.radioButtons["Layers"].firstMatch.click()
        app.buttons["Text"].firstMatch.click()
        let words = app.textFields["Text"].firstMatch
        type("Hi\r", into: words)
        XCTAssertTrue(app.buttons["Hi"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Move"].firstMatch.click()
        let x = app.textFields["X"].firstMatch
        XCTAssertTrue(x.waitForExistence(timeout: 5), "Move shows the typed position")
        x.click()
        x.typeKey("a", modifierFlags: .command)
        x.typeText("10\t")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue((status.value as? String ?? "").hasPrefix("Moved “Hi” to 10,"), "Done keeps the move: \(status.value ?? "")")
        XCTAssertTrue(app.buttons["Show Hi"].firstMatch.exists, "the original stays underneath, hidden")
        app.descendants(matching: .any)["Canvas picture"].firstMatch.click()
        app.typeKey("z", modifierFlags: .command)
        XCTAssertFalse(app.buttons["Show Hi"].firstMatch.waitForExistence(timeout: 2), "Undo takes the move back")

        app.buttons["Nudge Right"].firstMatch.click()
        app.buttons["Palette"].firstMatch.click()
        XCTAssertTrue(waitForPrefix(status, "Moved “Hi”"), "leaving the tool keeps the change: \(status.value ?? "")")

        app.buttons["Move"].firstMatch.click()
        app.radioButtons["Crop"].firstMatch.click()
        app.buttons["Apply Crop"].firstMatch.click()
        XCTAssertTrue(app.buttons["Hi (Crop 1)"].firstMatch.waitForExistence(timeout: 5), "Apply Crop makes a new layer")
        #endif
    }

    /// Build step 4d2 (Blueprint 047 / 048 / 056): Select All, Copy, Paste as a layer, Clear;
    /// Add / Remove Mask; two Magic Lasso clears land on ONE new layer as two History steps.
    @MainActor
    func testSelectionMaskLasso() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        showInspector(app)
        let any = app.descendants(matching: .any)
        let status = any["Status"].firstMatch
        XCTAssertTrue(app.buttons["Text"].firstMatch.waitForExistence(timeout: 10))
        app.radioButtons["Layers"].firstMatch.click()
        app.buttons["Text"].firstMatch.click()
        let words = app.textFields["Text"].firstMatch
        type("Hi\r", into: words)
        XCTAssertTrue(app.buttons["Hi"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Selection"].firstMatch.click()
        app.buttons["Select All"].firstMatch.click()
        app.buttons["Copy"].firstMatch.click()
        XCTAssertTrue((status.value as? String ?? "").hasPrefix("Copied"), "Copy puts the selection on the pasteboard")
        app.buttons["Paste"].firstMatch.click()
        XCTAssertTrue(app.buttons["Pasted"].firstMatch.waitForExistence(timeout: 5), "Paste makes a new layer")
        app.buttons["Hi"].firstMatch.click()
        app.buttons["Clear"].firstMatch.click()
        XCTAssertTrue(app.buttons["Hi (Clear 1)"].firstMatch.waitForExistence(timeout: 5), "Clear works on a new layer")

        app.buttons["Mask"].firstMatch.click()
        app.buttons["Add Mask"].firstMatch.click()
        XCTAssertEqual(status.value as? String, "Mask added")
        app.buttons["Remove Mask"].firstMatch.click()
        XCTAssertEqual(status.value as? String, "Mask removed")

        // Magic Lasso on a filled layer: two clears, one layer.
        app.buttons["Layer 1"].firstMatch.click()
        app.buttons["Paint Bucket"].firstMatch.click()
        app.buttons["Fill Layer"].firstMatch.click()
        // A red square in the middle of the black layer gives the lasso two separate areas.
        app.buttons["Palette"].firstMatch.click()
        app.buttons["Color 3, #FF3B30"].firstMatch.click()
        app.buttons["Pen"].firstMatch.click()
        let canvas = any["Canvas picture"].firstMatch
        canvas.click()
        XCTAssertTrue(app.buttons["Layer 1 (Pixel 1)"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Magic Lasso"].firstMatch.click()
        canvas.click()
        XCTAssertTrue(app.buttons["Layer 1 (Lasso 1)"].firstMatch.waitForExistence(timeout: 5), "the first clear starts one layer")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).click()
        XCTAssertTrue(waitFor(status, "Cleared another area"), "a second clear on a different area")
        XCTAssertFalse(app.buttons["Layer 1 (Lasso 2)"].exists, "later clears land on the same layer")
        app.radioButtons["History"].firstMatch.click()
        XCTAssertEqual(any.matching(identifier: "History step Magic Lasso").count, 2, "each clear is its own History step")
        #endif
    }

    /// Build step 4e1 (Blueprint 039 / 040 / 041): each Layer effect applies onto a new layer named
    /// for it; Gradient fills an empty layer; Remove Background answers (Apple's subject lift).
    @MainActor
    func testLayerEffectsAndRemoveBackground() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        showInspector(app)
        let status = app.descendants(matching: .any)["Status"].firstMatch
        XCTAssertTrue(app.buttons["Text"].firstMatch.waitForExistence(timeout: 10))
        app.radioButtons["Layers"].firstMatch.click()
        app.buttons["Text"].firstMatch.click()
        let words = app.textFields["Text"].firstMatch
        type("Hi\r", into: words)
        XCTAssertTrue(app.buttons["Hi"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Layer"].firstMatch.click()
        func choose(_ effect: String) {
            app.popUpButtons["Effect"].firstMatch.click()
            app.menuItems[effect].firstMatch.click()
        }
        choose("Translucent")
        app.buttons["Apply"].firstMatch.click()
        XCTAssertTrue(app.buttons["Hi (Translucent 1)"].firstMatch.waitForExistence(timeout: 5))
        choose("Glow")
        app.buttons["Apply"].firstMatch.click()
        XCTAssertTrue(app.buttons["Hi (Glow 1)"].firstMatch.waitForExistence(timeout: 10))
        choose("Blend")
        app.buttons["Apply"].firstMatch.click()
        XCTAssertTrue(app.buttons["Hi (Blend 1)"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Layer 1"].firstMatch.click()
        choose("Gradient")
        app.buttons["Apply"].firstMatch.click()
        XCTAssertTrue(app.buttons["Layer 1 (Gradient 1)"].firstMatch.waitForExistence(timeout: 5), "Gradient fills an empty layer")

        app.buttons["Hi (Blend 1)"].firstMatch.click()
        app.buttons["Remove Background"].firstMatch.click()   // the tool
        app.buttons.matching(identifier: "Remove Background").element(boundBy: 1).click()   // the command in its panel
        let said = status.value as? String ?? ""
        XCTAssertTrue(said == "Background removed" || said == "No subject found in this layer" || said.hasPrefix("Kept"),
                      "Remove Background gives an answer, got \(said)")
        #endif
    }

    /// Build step 4e2a (Blueprint 059 / 053 3D): Adjust panel (Blur, Levels from the Image menu,
    /// Flip), Liquify from the Filter menu by a click; 3D text restyles live; Image Playground panel.
    @MainActor
    func testAdjustmentsAnd3DText() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        showInspector(app)
        let any = app.descendants(matching: .any)
        let status = any["Status"].firstMatch
        XCTAssertTrue(app.buttons["Text"].firstMatch.waitForExistence(timeout: 10))
        app.radioButtons["Layers"].firstMatch.click()
        app.buttons["Text"].firstMatch.click()
        type("Hi\r", into: app.textFields["Text"].firstMatch)
        XCTAssertTrue(app.buttons["Hi"].firstMatch.waitForExistence(timeout: 5))
        any.matching(NSPredicate(format: "label == %@", "3D")).firstMatch.click()
        XCTAssertTrue(waitFor(status, "Restyled “Hi”"), "3D restyles the text live")

        app.buttons["Adjust"].firstMatch.click()
        app.popUpButtons["Adjustment"].firstMatch.click()
        app.menuItems["Gaussian Blur"].firstMatch.click()
        app.buttons["Apply"].firstMatch.click()
        XCTAssertTrue(app.buttons["Hi (Gaussian Blur 1)"].firstMatch.waitForExistence(timeout: 10))

        app.menuBars.menuBarItems["Image"].click()
        app.menuItems["Adjustments"].click()
        app.menuItems["Levels…"].click()
        app.buttons["Apply"].firstMatch.click()
        XCTAssertTrue(app.buttons["Hi (Levels 1)"].firstMatch.waitForExistence(timeout: 10), "Image ▸ Adjustments ▸ Levels…")

        app.popUpButtons["Adjustment"].firstMatch.click()
        app.menuItems["Flip"].firstMatch.click()
        app.buttons["Flip Horizontal"].firstMatch.click()
        app.buttons["Apply"].firstMatch.click()
        XCTAssertTrue(app.buttons["Hi (Flip 1)"].firstMatch.waitForExistence(timeout: 10))

        app.menuBars.menuBarItems["Filter"].click()
        app.menuItems["Liquify…"].click()
        any["Canvas picture"].firstMatch.click()
        XCTAssertTrue(app.buttons["Hi (Liquify 1)"].firstMatch.waitForExistence(timeout: 10), "Liquify bends where you click")

        app.buttons["Image Playground"].firstMatch.click()
        XCTAssertTrue(any.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Image Playground", "Image Playground")).count > 1,
                      "the Image Playground panel shows")
        #endif
    }

    /// Build step 4e2b (Blueprint 058): Capture makes a top layer; Animation mode captures frames;
    /// Generate adds in-betweens; Play shows the Lightbox until Exit Preview.
    @MainActor
    func testCameraAndLightbox() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        showInspector(app)
        let any = app.descendants(matching: .any)
        let status = any["Status"].firstMatch
        XCTAssertTrue(app.buttons["Text"].firstMatch.waitForExistence(timeout: 10))
        app.radioButtons["Layers"].firstMatch.click()
        app.buttons["Text"].firstMatch.click()
        type("Hi\r", into: app.textFields["Text"].firstMatch)
        XCTAssertTrue(app.buttons["Hi"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Camera"].firstMatch.click()
        // Animation mode is remembered between launches; start this test with it off.
        let animation = app.switches["Animation mode"].firstMatch
        XCTAssertTrue(animation.waitForExistence(timeout: 5))
        if (animation.value as? Int) == 1 { animation.click() }
        app.buttons["Capture"].firstMatch.click()
        XCTAssertTrue(app.buttons["Capture 1"].firstMatch.waitForExistence(timeout: 5), "Capture stamps a new top layer")
        XCTAssertTrue((status.value as? String ?? "").hasPrefix("Captured and copied"))

        animation.click()
        app.buttons["Capture Frame"].firstMatch.click()
        app.buttons["Hi"].firstMatch.click()
        app.buttons["Move"].firstMatch.click()
        app.buttons["Nudge Right"].firstMatch.click()
        app.buttons["Camera"].firstMatch.click()      // leaving Move keeps the move
        app.buttons["Capture Frame"].firstMatch.click()
        XCTAssertTrue(waitFor(any["Frame count"].firstMatch, "2 frames"), "two frames captured")
        app.buttons["Generate"].firstMatch.click()
        XCTAssertTrue(waitFor(any["Frame count"].firstMatch, "5 frames"), "three in-betweens between two frames")

        app.buttons["Play"].firstMatch.click()
        XCTAssertTrue(app.buttons["Exit Preview"].firstMatch.waitForExistence(timeout: 5), "the Lightbox plays")
        app.buttons["Exit Preview"].firstMatch.click()
        XCTAssertFalse(app.buttons["Exit Preview"].firstMatch.waitForExistence(timeout: 2))
        #endif
    }

    /// Build step 6a (Blueprint 061 / 043): File ▸ Export… (⌘E) writes a PNG, an Icon Set folder
    /// and a Print PDF through Apple's save panel (into a scratch folder, never his Desktop).
    @MainActor
    func testExport() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LW_ROBOT"] = "1"   // exports skip the save panel; Add Soundtrack uses a test tone
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        showInspector(app)
        let status = app.descendants(matching: .any)["Status"].firstMatch
        XCTAssertTrue(app.buttons["Text"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Text"].firstMatch.click()
        type("Export me\r", into: app.textFields["Text"].firstMatch)
        XCTAssertTrue(app.toolbars.buttons["Share"].firstMatch.exists || app.buttons["Share"].firstMatch.exists, "Share is on the toolbar")

        for (format, file) in [("PNG", "Layerworks Picture.png"), ("Icon Set (light and dark)", "Layerworks Picture"),
                               ("Print PDF (bleed and marks)", "Layerworks Picture.pdf")] {
            app.typeKey("e", modifierFlags: .command)
            let picker = app.popUpButtons["Format"].firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 5), "⌘E opens Export")
            picker.click()
            app.menuItems[format].firstMatch.click()
            app.buttons["Export…"].firstMatch.click()
            // Under the robot (LW_ROBOT) the export skips the save panel and goes to the app's Robot Exports folder.
            XCTAssertTrue(waitFor(status, "Exported \(file)"), "\(format) exported, status: \(status.value ?? "")")
        }
        #endif
    }

    /// Build step 7a (Blueprint 074): the locked single-letter tool keys (Tools menu, no modifier),
    /// typing in a text box is not stolen by them, and the names bots depend on.
    @MainActor
    func testToolLettersAndNames() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        showInspector(app)
        let status = app.descendants(matching: .any)["Status"].firstMatch
        XCTAssertTrue(app.buttons["Canvas Tool"].firstMatch.waitForExistence(timeout: 10), "074: the canvas tool is Canvas Tool")
        XCTAssertTrue(app.menuBars.menuBarItems["Tools"].exists, "the Tools menu lists every tool")
        app.descendants(matching: .any)["Canvas picture"].firstMatch.click()
        for (key, name) in [("t", "Text"), ("b", "Paint Bucket"), ("w", "Magic Lasso"), ("h", "Camera"), ("c", "Canvas")] {
            app.typeKey(key, modifierFlags: [])
            XCTAssertTrue(waitFor(status, "\(name) tool"), "\(key.uppercased()) picks \(name), status: \(status.value ?? "")")
        }

        // Letters typed into a text box are words, not tool keys.
        app.typeKey("t", modifierFlags: [])
        type("hey\r", into: app.textFields["Text"].firstMatch)
        XCTAssertTrue(waitFor(status, "Added text “hey”"), "typing e, h, y stays in the box, status: \(status.value ?? "")")

        app.descendants(matching: .any)["Canvas picture"].firstMatch.click()   // leave the text box
        app.typeKey("a", modifierFlags: [])
        XCTAssertTrue(waitFor(status, "Image Playground tool"), "status: \(status.value ?? "")")
        if app.buttons["New Layer"].firstMatch.waitForExistence(timeout: 3) {
            XCTAssertTrue(app.buttons["Filter Current Layer"].firstMatch.exists, "074: bots use Filter Current Layer")
        } else {
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Image Playground'")).firstMatch.exists)
        }
        #endif
    }

    /// Build step 7b (Blueprint 075): Settings holds command mode's job folder. The jobs themselves
    /// are checked by Scripts/test-command-mode.sh (a UI test can't reach the job folder).
    @MainActor
    func testCommandModeSettings() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.typeKey(",", modifierFlags: .command)
        let folder = app.descendants(matching: .any)["Job folder"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5), "Settings shows the job folder")
        XCTAssertTrue(app.buttons["Choose…"].firstMatch.exists)
        #endif
    }

    /// Build step 7c (Blueprint 076): the standard Help menu, backed by the Layerworks Help Book.
    @MainActor
    func testHelpMenu() throws {
        let app = XCUIApplication()
        app.launch()
        #if os(macOS)
        app.menuBars.menuBarItems["Help"].click()
        let item = app.menuBars.menuItems["Layerworks Help"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Help ▸ Layerworks Help")
        XCTAssertTrue(item.isEnabled, "the Help Book is registered, so the item is enabled")
        app.typeKey(.escape, modifierFlags: [])
        #endif
    }

    /// Build step 6b (Blueprint 066 / 067): File ▸ Storyboard… (⌥⌘B, not on the toolbar) orders the
    /// Camera frames, sets a transition and a soundtrack, plays, and Export writes a real video.
    @MainActor
    func testStoryboardAndVideo() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LW_ROBOT"] = "1"   // exports skip the save panel; Add Soundtrack uses a test tone
        app.launch()
        #if os(macOS)
        app.typeKey("n", modifierFlags: .command)
        showInspector(app)
        let any = app.descendants(matching: .any)
        let status = any["Status"].firstMatch
        XCTAssertFalse(app.toolbars.buttons["Storyboard"].exists, "067: no Storyboard button on the toolbar")
        XCTAssertTrue(app.buttons["Text"].firstMatch.waitForExistence(timeout: 10))
        app.radioButtons["Layers"].firstMatch.click()
        app.buttons["Text"].firstMatch.click()
        type("Hi\r", into: app.textFields["Text"].firstMatch)
        XCTAssertTrue(app.buttons["Hi"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Camera"].firstMatch.click()
        let animation = app.switches["Animation mode"].firstMatch
        XCTAssertTrue(animation.waitForExistence(timeout: 5))
        if (animation.value as? Int) != 1 { animation.click() }
        app.buttons["Capture Frame"].firstMatch.click()
        app.buttons["Hi"].firstMatch.click()
        app.buttons["Move"].firstMatch.click()
        app.buttons["Nudge Right"].firstMatch.click()
        app.buttons["Camera"].firstMatch.click()
        app.buttons["Capture Frame"].firstMatch.click()
        XCTAssertTrue(waitFor(any["Frame count"].firstMatch, "2 frames"))

        // File ▸ Storyboard…
        app.typeKey("b", modifierFlags: [.command, .option])
        let length = any["Video length"].firstMatch
        XCTAssertTrue(length.waitForExistence(timeout: 5), "⌥⌘B opens the Storyboard")
        XCTAssertTrue(app.staticTexts["Frame 2"].firstMatch.exists)
        let before = length.value as? String ?? ""
        let then = app.popUpButtons["Transition after frame 1"].firstMatch
        then.click()
        app.menuItems["Dissolve"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["Transition length after frame 1"].firstMatch.waitForExistence(timeout: 3),
                      "a Dissolve gets a length")
        XCTAssertNotEqual(length.value as? String ?? "", before, "the Dissolve adds to the video's length")

        // Soundtrack through Apple's open panel.
        app.buttons["Add Soundtrack…"].firstMatch.click()   // LW_ROBOT: a made tone, no open panel
        XCTAssertTrue(waitFor(status, "Added the soundtrack Robot Tone.m4a"), "status: \(status.value ?? "")")

        let sheet = app.sheets.firstMatch
        sheet.buttons["Play"].firstMatch.click()
        let played = NSPredicate(format: "value BEGINSWITH %@", "Playing the storyboard")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: played, object: status)], timeout: 30),
                       .completed, "Play makes and plays the video, status: \(status.value ?? "")")
        sheet.buttons["Done"].firstMatch.click()
        // Let the Storyboard sheet finish closing before Export opens its own sheet.
        XCTAssertTrue(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                                       object: length)], timeout: 5) == .completed)

        // File ▸ Export… ▸ Video (Storyboard), H.264.
        app.typeKey("e", modifierFlags: .command)
        let picker = app.popUpButtons["Format"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        app.menuItems["Video (Storyboard)"].firstMatch.click()
        let codec = app.popUpButtons["Video format"].firstMatch
        XCTAssertTrue(codec.waitForExistence(timeout: 3))
        codec.click()
        app.menuItems["H.264 (.mp4)"].firstMatch.click()
        app.buttons["Export…"].firstMatch.click()
        let exported = NSPredicate(format: "value == %@", "Exported Layerworks Picture.mp4")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: exported, object: status)], timeout: 60),
                       .completed, "the video is made and saved, status: \(status.value ?? "")")
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

/// Clicks a text field and waits until it really has the keyboard before typing (the robot can
/// otherwise type into nothing while the click is still landing).
@MainActor
private func type(_ text: String, into field: XCUIElement) {
    field.click()
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline, (field.value(forKey: "hasKeyboardFocus") as? Bool) != true {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    field.typeText(text)
}

/// Waits up to 10 s for an element's value (the status line) to read `text`.
@MainActor
private func waitFor(_ element: XCUIElement, _ text: String) -> Bool {
    let done = NSPredicate(format: "value == %@", text)
    return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: done, object: element)], timeout: 10) == .completed
}

/// Waits up to 10 s for an element's value to start with `prefix`.
@MainActor
private func waitForPrefix(_ element: XCUIElement, _ prefix: String) -> Bool {
    let done = NSPredicate(format: "value BEGINSWITH %@", prefix)
    return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: done, object: element)], timeout: 10) == .completed
}
