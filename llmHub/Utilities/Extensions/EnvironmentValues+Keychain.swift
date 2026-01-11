//
//  EnvironmentValues+Keychain.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import SwiftUI

private struct KeychainStoreKey: EnvironmentKey {
    static let defaultValue = KeychainStore()
}

extension EnvironmentValues {
    var keychainStore: KeychainStore {
        get { self[KeychainStoreKey.self] }
        set { self[KeychainStoreKey.self] = newValue }
    }
}
