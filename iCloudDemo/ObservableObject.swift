//
//  ObservableObject.swift
//  iCloudDemo
//
//  Created by Aco on 2025/8/29.
//

import Foundation

class ObservableObject <T> {
    var value: T {
        didSet {
            listener?(value)
        }
    }

    var listener: ((T) -> Void)?

    init(value: T) {
        self.value = value
    }

    func bind(_ listener: @escaping ((T) -> Void)) {
        listener(value)
        self.listener = listener
    }
}
