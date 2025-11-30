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
    
    // Sheet states
    @State private var showCreateFolder = false
    @State private var showCreateTag = false
    
    var body: some View {
        VStack(spacing: 0) {
            // View Mode Picker
            Picker("View Mode", selection: $viewModel.viewMode) {
                ForEach(ChatViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Tag Filter Bar
            if !viewModel.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.tags) { tag in
                            TagFilterChip(
                                tag: tag,
                                isSelected: viewModel.selectedTags.contains(tag.id),
                                onTap: {
                                    if viewModel.selectedTags.contains(tag.id) {
                                        viewModel.selectedTags.remove(tag.id)
                                    } else {
                                        viewModel.selectedTags.insert(tag.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)
            }
            
            // Main List
            List(selection: Binding(
                get: { viewModel.selectedSession?.id },
                set: { id in
                    if let id, let session = viewModel.sessions.first(where: { $0.id == id }) {
                        viewModel.selectedSession = session
                    }
                })) {
                    ForEach(viewModel.groupedSessions) { section in
                        Section(header: SectionHeader(title: section.title, folder: section.folder, viewModel: viewModel)) {
                            ForEach(section.sessions) { session in
                                ChatSessionRow(session: session, viewModel: viewModel)
                                    .tag(session.id)
                                    .draggable(session.id.uuidString)
                            }
                        }
                    }
                }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: { showCreateFolder = true }) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    Button(action: { showCreateTag = true }) {
                        Label("New Tag", systemImage: "tag")
                    }
                    Divider()
                    Button(action: { showSettings = true }) {
                        Label("Settings", systemImage: "gear")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showCreateFolder) {
            CreateFolderView(viewModel: viewModel)
        }
        .sheet(isPresented: $showCreateTag) {
            CreateTagView(viewModel: viewModel)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let folder: ChatFolder?
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        HStack {
            if let folder = folder {
                Image(systemName: folder.icon)
                    .foregroundStyle(Color(hex: folder.color))
            }
            Text(title)
            Spacer()
        }
        .dropDestination(for: String.self) { items, _ in
            guard let folder = folder, let item = items.first, let uuid = UUID(uuidString: item) else { return false }
            if let session = viewModel.sessions.first(where: { $0.id == uuid }) {
                viewModel.moveSession(session, to: folder)
                return true
            }
            return false
        }
        .contextMenu {
            if let folder = folder {
                Button("Delete Folder", role: .destructive) {
                    viewModel.deleteFolder(id: folder.id)
                }
            }
        }
    }
}

struct ChatSessionRow: View {
    let session: ChatSession
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            
            HStack {
                Text("\(session.providerID.uppercased()) • \(session.model)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                ForEach(session.tags) { tag in
                    Circle()
                        .fill(Color(hex: tag.color))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .contextMenu {
            Button(action: { viewModel.togglePin(session) }) {
                Label(session.isPinned ? "Unpin" : "Pin", systemImage: "pin")
            }
            
            Menu("Move to Folder") {
                Button("None") {
                    viewModel.moveSession(session, to: nil)
                }
                ForEach(viewModel.folders) { folder in
                    Button {
                        viewModel.moveSession(session, to: folder)
                    } label: {
                        Label(folder.name, systemImage: folder.icon)
                    }
                }
            }
            
            Menu("Tags") {
                ForEach(viewModel.tags) { tag in
                    Button {
                        if session.tags.contains(where: { $0.id == tag.id }) {
                            viewModel.removeTag(tag, from: session)
                        } else {
                            viewModel.addTag(tag, to: session)
                        }
                    } label: {
                        HStack {
                            Text(tag.name)
                            if session.tags.contains(where: { $0.id == tag.id }) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TagFilterChip: View {
    let tag: ChatTag
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: tag.color))
                    .frame(width: 8, height: 8)
                Text(tag.name)
                    .font(.caption)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CreateFolderView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var icon = "folder"
    @State private var color = "#007AFF" // Blue
    
    let icons = ["folder", "star", "heart", "doc", "bookmark", "flag", "tag"]
    let colors = ["#007AFF", "#FF3B30", "#4CD964", "#FFCC00", "#5856D6", "#FF9500"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Details") {
                    TextField("Folder Name", text: $name)
                }
                
                Section("Icon") {
                    HStack {
                        ForEach(icons, id: \.self) { iconName in
                            Image(systemName: iconName)
                                .padding(8)
                                .background(icon == iconName ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                                .onTapGesture { icon = iconName }
                        }
                    }
                }
                
                Section("Color") {
                    HStack {
                        ForEach(colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: color == hex ? 2 : 0)
                                )
                                .onTapGesture { color = hex }
                        }
                    }
                }
            }
            .navigationTitle("New Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        viewModel.createFolder(name: name, icon: icon, color: color)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

struct CreateTagView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var color = "#007AFF"
    
    let colors = ["#007AFF", "#FF3B30", "#4CD964", "#FFCC00", "#5856D6", "#FF9500", "#8E8E93"]
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Tag Name", text: $name)
                }
                
                Section("Color") {
                    HStack {
                        ForEach(colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: color == hex ? 2 : 0)
                                )
                                .onTapGesture { color = hex }
                        }
                    }
                }
            }
            .navigationTitle("New Tag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        viewModel.createTag(name: name, color: color)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
