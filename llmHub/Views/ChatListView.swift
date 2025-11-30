//
//  ChatListView.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import SwiftUI

struct ChatListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showSettings = false

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedSession?.id },
            set: { id in
                if let id, let session = viewModel.sessions.first(where: { $0.id == id }) {
                    DispatchQueue.main.async {
                        viewModel.selectedSession = session
                    }
                }
            })) {
                ForEach(viewModel.sessions) { session in
                    VStack(alignment: .leading) {
                        Text(session.title)
                            .font(.headline)
                        Text("\(session.providerID.uppercased()) • \(session.model)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .tag(session.id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showSettings = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
    }
}

