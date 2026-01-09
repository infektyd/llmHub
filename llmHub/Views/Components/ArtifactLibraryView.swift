//
//  ArtifactLibraryView.swift
//  llmHub
//
//  UI for viewing and managing the curated artifact sandbox.
//  Shows all files the user has shared with the AI.
//

import SwiftUI
import UniformTypeIdentifiers

/// A view that displays and manages the artifact library.
/// Users can view, import, and delete files shared with the AI.
struct ArtifactLibraryView: View {
    @State private var artifacts: [SandboxedArtifact] = []
    @State private var isLoading = true
    @State private var showFilePicker = false
    @State private var showFolderPicker = false
    @State private var selectedArtifact: SandboxedArtifact?
    @State private var showDeleteConfirmation = false
    @State private var artifactToDelete: SandboxedArtifact?
    @State private var importError: String?
    @State private var showImportError = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            if isLoading {
                loadingView
            } else if artifacts.isEmpty {
                emptyView
            } else {
                artifactList
            }
        }
        .frame(minWidth: 300, minHeight: 400)
        .onAppear {
            Task {
                await loadArtifacts()
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            Task {
                await handleFileImport(result)
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            Task {
                await handleFolderImport(result)
            }
        }
        .alert("Delete Artifact", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let artifact = artifactToDelete {
                    Task {
                        await deleteArtifact(artifact)
                    }
                }
            }
        } message: {
            if let artifact = artifactToDelete {
                Text(
                    "Are you sure you want to delete '\(artifact.filename)'? This cannot be undone."
                )
            }
        }
        .alert("Import Error", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Artifact Library")
                    .font(.headline)
                Text("\(artifacts.count) files • \(formattedTotalSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Import Files...", systemImage: "doc.badge.plus")
                }

                Button {
                    showFolderPicker = true
                } label: {
                    Label("Import Folder...", systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.accent)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding()
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading artifacts...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Files Shared")
                .font(.headline)

            Text(
                "Drag files here or use the + button to share files with the AI. Only shared files can be read and analyzed."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Import Files", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)

                Button {
                    showFolderPicker = true
                } label: {
                    Label("Import Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var artifactList: some View {
        List(artifacts) { artifact in
            ArtifactRow(artifact: artifact)
                .contextMenu {
                    Button {
                        revealInFinder(artifact)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Divider()

                    Button(role: .destructive) {
                        artifactToDelete = artifact
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
        .listStyle(.inset)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Computed Properties

    private var formattedTotalSize: String {
        let total = artifacts.reduce(0) { $0 + $1.sizeBytes }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    // MARK: - Actions

    private func loadArtifacts() async {
        isLoading = true
        artifacts = await ArtifactSandboxService.shared.listArtifacts()
        isLoading = false
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    _ = try await ArtifactSandboxService.shared.importFile(from: url)
                } catch {
                    importError = error.localizedDescription
                    await MainActor.run { showImportError = true }
                }
            }
            await loadArtifacts()

        case .failure(let error):
            importError = error.localizedDescription
            await MainActor.run { showImportError = true }
        }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                _ = try await ArtifactSandboxService.shared.importFolder(from: url)
                await loadArtifacts()
            } catch {
                importError = error.localizedDescription
                await MainActor.run { showImportError = true }
            }

        case .failure(let error):
            importError = error.localizedDescription
            await MainActor.run { showImportError = true }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                data, _ in
                guard let data = data as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    return
                }

                Task {
                    do {
                        _ = try await ArtifactSandboxService.shared.importFile(from: url)
                        await loadArtifacts()
                    } catch {
                        await MainActor.run {
                            importError = error.localizedDescription
                            showImportError = true
                        }
                    }
                }
            }
        }
        return true
    }

    private func deleteArtifact(_ artifact: SandboxedArtifact) async {
        do {
            try await ArtifactSandboxService.shared.deleteArtifact(id: artifact.id)
            await loadArtifacts()
        } catch {
            importError = error.localizedDescription
            await MainActor.run { showImportError = true }
        }
    }

    private func revealInFinder(_ artifact: SandboxedArtifact) {
        #if os(macOS)
            let path = ArtifactSandboxService.shared.sandboxURL
                .appendingPathComponent(artifact.sandboxRelativePath)
            NSWorkspace.shared.selectFile(path.path, inFileViewerRootedAtPath: "")
        #endif
    }
}

// MARK: - Artifact Row

private struct ArtifactRow: View {
    let artifact: SandboxedArtifact

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: artifact.iconName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.filename)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(artifact.formattedSize)
                    Text("•")
                    Text(artifact.importedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    ArtifactLibraryView()
        .frame(width: 350, height: 500)
}
