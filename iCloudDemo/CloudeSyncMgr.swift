//
//  CloudeSyncMgr.swift
//  iCloudDemo
//
//  Created by 林仲景 on 2025/8/11.
//

import Foundation
import CloudKit

class CloudeSyncMgr {
    static let shared = CloudeSyncMgr()
    private let defaultContainer = CKContainer.default()
    private let sharedZone = CKShare(recordZoneID: CKRecordZone(zoneName: "SharedZone").zoneID)
    private let defaultZone = CKRecordZone.default()
    private let operation = CKModifyRecordsOperation()
    private let backGroundQueue = DispatchQueue(label: "com.fridgehelper.backgroundQueue")
    
    private func handleCompletion() {
        operation.completionBlock = {
            DispatchQueue.main.async {
                print("Cloud sync finished: \(self.operation.isFinished)")
            }
        }
    }
    
    func saveToCloud(readyToSave: [CKRecord]) {
        operation.recordsToSave = readyToSave
        backGroundQueue.async {
            self.operation.start()
        }
    }
    
    func deleteToCloud(readyToDelete: [CKRecord]) {
        operation.recordIDsToDelete = readyToDelete.map({ $0.recordID })
        backGroundQueue.async {
            self.operation.start()
        }
    }
    
}

