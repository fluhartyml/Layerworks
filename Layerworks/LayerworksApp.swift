//
//  LayerworksApp.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI

// REM: Bare scaffold only (his order 2026-11-25: "please set up the new xcode project for
// you to work on while im away"). No feature lines are built until he locks them in the
// line-by-line walk of Grok's Blueprint (his word: "we will go through line by line first
// to lock everything in before proceedng"). The app shell — window vs. document scene —
// is itself a Blueprint decision, so this stays a plain window until that line is locked.

@main
struct LayerworksApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
