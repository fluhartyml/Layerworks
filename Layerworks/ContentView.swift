//
//  ContentView.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI

// REM: Build step 1 (Blueprint 010) is the document model only. This window shows the blank
// canvas at its true shape and the build line. The editor chrome — tool box, inspector,
// Layers / History — is build step 2. No dead buttons (his rule: no placeholders).

struct ContentView: View {
    @ObservedObject var document: LayerworksDocument

    var body: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(.white)
                .aspectRatio(CGFloat(document.manifest.canvasWidth) /
                             CGFloat(max(document.manifest.canvasHeight, 1)), contentMode: .fit)
                .shadow(radius: 2)
                .padding()
                .accessibilityLabel("Canvas")
                .accessibilityValue("\(document.manifest.canvasWidth) by \(document.manifest.canvasHeight) pixels")
            Text(BuildStamp.line)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.gray.opacity(0.15))
    }
}

#Preview {
    ContentView(document: LayerworksDocument())
}
