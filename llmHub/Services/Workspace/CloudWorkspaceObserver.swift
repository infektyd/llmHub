import Foundation
import Combine
import OSLog

/// Observes iCloud workspace changes and publishes updates.
@MainActor
final class CloudWorkspaceObserver: ObservableObject {

    @Published private(set) var workspaceIDs: [UUID] = []
    @Published private(set) var isQueryRunning = false

    private let logger = Logger(subsystem: "com.llmhub", category: "CloudWorkspaceObserver")
    nonisolated(unsafe) private let metadataQuery = NSMetadataQuery()
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupQuery()
    }

    deinit {
        let query = metadataQuery
        Task { @MainActor in
            query.stop()
        }
    }

    func startObserving() {
        guard !metadataQuery.isStarted else { return }
        metadataQuery.start()
        isQueryRunning = true
        logger.info("Started observing iCloud workspace changes")
    }

    func stopObserving() {
        metadataQuery.stop()
        isQueryRunning = false
        logger.info("Stopped observing iCloud workspace changes")
    }

    private func setupQuery() {
        // Search for directories in our Workspaces folder
        metadataQuery.predicate = NSPredicate(format: "%K LIKE 'Workspaces/*'", NSMetadataItemPathKey)
        metadataQuery.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        // Notifications
        NotificationCenter.default.publisher(for: .NSMetadataQueryDidFinishGathering)
            .sink { [weak self] _ in self?.processResults() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSMetadataQueryDidUpdate)
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.processResults() }
            .store(in: &cancellables)
    }

    private func processResults() {
        metadataQuery.disableUpdates()
        defer { metadataQuery.enableUpdates() }

        var foundIDs: Set<UUID> = []

        for item in metadataQuery.results {
            guard let metadataItem = item as? NSMetadataItem,
                  let path = metadataItem.value(forAttribute: NSMetadataItemPathKey) as? String else {
                continue
            }

            // Extract workspace UUID from path
            let components = path.components(separatedBy: "/")
            if let workspacesIndex = components.firstIndex(of: "Workspaces"),
               workspacesIndex + 1 < components.count,
               let uuid = UUID(uuidString: components[workspacesIndex + 1]) {
                foundIDs.insert(uuid)
            }
        }

        let sortedIDs = foundIDs.sorted { $0.uuidString < $1.uuidString }
        if sortedIDs != workspaceIDs {
            workspaceIDs = sortedIDs
            logger.info("Workspace list updated: \(sortedIDs.count) workspaces")
        }
    }
}
