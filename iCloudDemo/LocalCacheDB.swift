//
//  LocalCacheDB.swift
//  iCloudDemo
//
//  Created by Aco on 2025/8/29.
//

import Foundation
import CloudKit

class LocalCacheDB {
    // Container
    private(set) var defaultContainer = CKContainer.default()
    private(set) var container = CKContainer(identifier: "iCloud.com.jeff.iCloudDemo")

    // Database
    private(set) var privateDatabase = CKContainer(identifier: "iCloud.com.jeff.iCloudDemo").privateCloudDatabase
    private(set) var sharedDatabase = CKContainer(identifier: "iCloud.com.jeff.iCloudDemo").sharedCloudDatabase

    // Zone
    var customZone: CKRecordZone = CKRecordZone(zoneName: "NoteZone")
    var sharedZone: [CKRecordZone]?

    // Record / Share
    var rootShareRecord: CKRecord {
        let rootID = CKRecord.ID(recordName: "com.demo.app.root.\(CKCurrentUserDefaultName)", zoneID: customZone.zoneID)
        return CKRecord(recordType: "Item", recordID: rootID)
    }

    var share: CKShare?
}
