//
//  ContentView.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI

// REM: Shows only the app name and the build line (standing order: every build shows its
// commit number). No buttons — his rule is no placeholders or dead controls in any project.

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Layerworks")
                .font(.largeTitle.bold())
            Text(BuildStamp.line)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
