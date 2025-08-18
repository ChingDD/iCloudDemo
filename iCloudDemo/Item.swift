//
//  Item.swift
//  iCloudDemo
//
//  Created by 林仲景 on 2025/8/11.
//

import Foundation
struct Item {
    var title: String
    var isShare: Bool
    let timestamp: Double

    init(title: String = "", isShare: Bool = false, timestamp: Double = Date().timeIntervalSince1970) {
        self.title = title
        self.isShare = isShare
        self.timestamp = timestamp
    }
}
