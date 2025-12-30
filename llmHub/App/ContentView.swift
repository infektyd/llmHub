//
//  ContentView.swift
//  llmHub
//
//  Created by Hans Axelsson on 11/27/25.
//

import SwiftData
import SwiftUI

/// The root view of the application.
struct ContentView: View {
    @AppStorage("uiMode") private var uiMode: String = "canvas"

    var body: some View {
        switch uiMode.lowercased() {
        case "nordic":
            NordicRootView()
        case "legacy":
            NeonWorkbenchWindow()
        default:
            // Treat legacy stored values ("neon") as "canvas" going forward.
            CanvasWorkbenchWindow()
        }
    }
}
