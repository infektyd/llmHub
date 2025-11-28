//
//  Item.swift
//  llmHub
//
//  Created by Hans Axelsson on 11/27/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
