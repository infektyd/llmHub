import SwiftUI

typealias OpenArtifactDetailAction = (ArtifactPayload) -> Void

private struct OpenArtifactDetailActionKey: EnvironmentKey {
    static let defaultValue: OpenArtifactDetailAction? = nil
}

extension EnvironmentValues {
    var openArtifactDetail: OpenArtifactDetailAction? {
        get { self[OpenArtifactDetailActionKey.self] }
        set { self[OpenArtifactDetailActionKey.self] = newValue }
    }
}
