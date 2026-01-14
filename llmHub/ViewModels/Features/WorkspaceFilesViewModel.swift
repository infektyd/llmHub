//
//  WorkspaceFilesViewModel.swift
//  llmHub
//
//  ViewModel for the Workspace Files panel in the right sidebar.
//

import Foundation
import SwiftUI
import Combine
import OSLog

/// ViewModel for the Workspace Files panel in the right sidebar.
@MainActor
@Observable
final class WorkspaceFilesViewModel {
    
    private let logger = Logger(subsystem: "com.llmhub", category: "WorkspaceFilesViewModel")
    
    // MARK: - Published State
    
    var files: [WorkspaceFile] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var workspaceLocation: String = "Loading..."
    var isICloudAvailable: Bool = false
    
    // MARK: - Private
    
    private var refreshTask: Task<Void, Never>?
    private let observer = CloudWorkspaceObserver()
    private var observerCancellable: AnyCancellable?
    
    // MARK: - Lifecycle
    
    func startObserving() {
        observer.startObserving()
        
        // Subscribe to workspace changes
        observerCancellable = observer.$workspaceIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
        
        // Initial load
        Task { await refresh() }
    }
    
    func stopObserving() {
        observer.stopObserving()
        observerCancellable?.cancel()
        refreshTask?.cancel()
    }
    
    // MARK: - Refresh
    
    func refresh() async {
        refreshTask?.cancel()
        
        refreshTask = Task {
            isLoading = true
            errorMessage = nil
            
            let manager = CloudWorkspaceManager.shared
            let workspaceID = manager.defaultWorkspaceID()
            
            // Check iCloud status
            let containerURL = await manager.containerURL()
            isICloudAvailable = containerURL != nil
            
            do {
                // Get workspace URL for display
                if let url = try await manager.workspaceURL(for: workspaceID) {
                    workspaceLocation = abbreviatePath(url.path)
                } else {
                    workspaceLocation = "Not created yet"
                }
                
                // List files
                let filenames = try await manager.listFiles(inWorkspace: workspaceID)
                
                // Build WorkspaceFile models
                var newFiles: [WorkspaceFile] = []
                for filename in filenames {
                    // Skip manifest
                    guard filename != "manifest.json" else { continue }
                    
                    // Get file info
                    let data = try? await manager.readFile(named: filename, inWorkspace: workspaceID)
                    let size = data?.count ?? 0
                    
                    let file = WorkspaceFile(
                        id: filename,
                        filename: filename,
                        sizeBytes: size,
                        modifiedAt: nil,  // Could add if needed
                        fileType: WorkspaceFile.detect(filename: filename)
                    )
                    newFiles.append(file)
                }
                
                // Sort: errors first, then outputs, then code, then others
                files = newFiles.sorted { lhs, rhs in
                    let order: [WorkspaceFile.FileType] = [.error, .output, .code, .image, .data, .other]
                    let lhsIndex = order.firstIndex(of: lhs.fileType) ?? 99
                    let rhsIndex = order.firstIndex(of: rhs.fileType) ?? 99
                    if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                    return lhs.filename < rhs.filename
                }
                
                logger.info("Loaded \(self.files.count) workspace files")
                
            } catch {
                logger.error("Failed to load workspace files: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                files = []
            }
            
            isLoading = false
        }
        
        await refreshTask?.value
    }
    
    // MARK: - Actions
    
    func deleteFile(_ file: WorkspaceFile) async {
        let manager = CloudWorkspaceManager.shared
        let workspaceID = manager.defaultWorkspaceID()
        
        guard let workspaceURL = try? await manager.workspaceURL(for: workspaceID) else { return }
        
        let fileURL = workspaceURL.appendingPathComponent(file.filename)
        try? FileManager.default.removeItem(at: fileURL)
        
        await refresh()
    }
    
    func clearAllFiles() async {
        let manager = CloudWorkspaceManager.shared
        let workspaceID = manager.defaultWorkspaceID()
        
        // Delete and recreate workspace
        try? await manager.deleteWorkspace(id: workspaceID)
        _ = try? await manager.getOrCreateWorkspace(id: workspaceID)
        
        await refresh()
    }
    
    func openInFinder() {
        #if os(macOS)
        Task {
            let manager = CloudWorkspaceManager.shared
            let workspaceID = manager.defaultWorkspaceID()
            
            if let url = try? await manager.workspaceURL(for: workspaceID) {
                NSWorkspace.shared.open(url)
            }
        }
        #endif
    }
    
    func copyFileContents(_ file: WorkspaceFile) async -> String? {
        let manager = CloudWorkspaceManager.shared
        let workspaceID = manager.defaultWorkspaceID()
        
        guard let data = try? await manager.readFile(named: file.filename, inWorkspace: workspaceID),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    // MARK: - Helpers
    
    private func abbreviatePath(_ path: String) -> String {
        // Shorten iCloud paths for display
        if path.contains("Mobile Documents") {
            return "iCloud Drive/llmHub/..."
        }
        if path.contains("Documents/Workspaces") {
            return "Local/Workspaces/..."
        }
        return path
    }
}
