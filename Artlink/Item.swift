//
//  Item.swift
//  Artlink
//
//  Created by yesunglim on 2025-09-23.
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
