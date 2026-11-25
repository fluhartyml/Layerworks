//
//  Layerworks_DeveloperNotes.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//
//  ============================================================================
//  PLAN OF RECORD — living design doc.  Last updated: 2026-11-25.
//  ============================================================================
//
//  WHY THIS APP
//  ------------
//  A ground-up rebuild of Image Producer on Apple's standard patterns. His words,
//  2026-11-25: "we reinvented so many things apple does for free image producer
//  became bloated and confusing" · "a brand new image producer app from the ground
//  up. so it uses standardized apple normal operating proceedures so we dont have
//  to reinvent the wheel".
//
//  NAME: Layerworks (his word: "lets go layerworks first and image millworks as a
//  backup"). Recheck the USPTO's own records before the App Store Connect listing.
//
//  SOURCE: Grok's Blueprint — ~/Downloads/Image-Producer-Consolidated-Amber-Sheet.html
//  (128 lines). NOTHING from it is built until he locks it line by line.
//
//  CURRENT STATE (2026-11-25)
//  --------------------------
//  - Bare scaffold: one window showing the name and the build line.
//  - Multiplatform: iOS/iPadOS + macOS 27.0 (SDKROOT auto, no Catalyst), device
//    family 1,2,7. Sandbox on, user-selected files read/write. Swift 5, MainActor default.
//  - Bundle id com.nightgard.Layerworks, team 3X3F6UJ44H.
//  - GitHub: github.com/fluhartyml/Layerworks (private, created 2026-11-25 at his word).
//  - Build number = git rev-list --count HEAD via Scripts/ hooks
//    (run Scripts/install-hooks.sh once per clone).
//
//  OPEN (his decisions, held for the Blueprint walk)
//  -------------------------------------------------
//  - New app beside Image Producer, or its replacement?
//  - Final folder (scaffolded at ~/Developer.complex/NightGard/Layerworks).
//  - File type / document model.
//

import Foundation
