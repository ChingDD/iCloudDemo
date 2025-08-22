//
//  CloudeSyncMgr.swift
//  iCloudDemo
//
//  Created by 林仲景 on 2025/8/11.
//

import Foundation
import CloudKit

class CloudSyncMgr {
    static let shared = CloudSyncMgr()
    private let defaultContainer = CKContainer.default()
    private(set) var container = CKContainer(identifier: "iCloud.com.jeff.iCloudDemo")
    private let privateDatabase = CKContainer(identifier: "iCloud.com.jeff.iCloudDemo").privateCloudDatabase
    private let sharedDatabase = CKContainer(identifier: "iCloud.com.jeff.iCloudDemo").sharedCloudDatabase
    private(set) var customZone = CKRecordZone(zoneName: "NoteZone")
    private let defaultZone = CKRecordZone.default()
    private(set) var rootShareRecord: CKRecord?
    private let backGroundQueue = DispatchQueue(label: "com.Note.backgroundQueue")

    init() {
//        createCustomZoneIfNeeded()
        config()
    }
    
    private func createCustomZoneIfNeeded() {
        let customZone = CKRecordZone(zoneName: "NoteZone")
        
        privateDatabase.fetchAllRecordZones { [weak self] zones, error in
            if let zones = zones {
                let zoneNames = zones.map { $0.zoneID.zoneName }
                print("Existing zones: \(zoneNames)")
                
                if !zoneNames.contains("NoteZone") {
                    print("Creating custom zone: NoteZone")
                    self?.privateDatabase.save(customZone) { zone, error in
                        if let error = error {
                            print("Failed to create custom zone: \(error)")
                        } else {
                            print("Custom zone created successfully")
                        }
                    }
                } else {
                    print("Custom zone NoteZone already exists")
                }
            } else if let error = error {
                print("Failed to fetch zones: \(error)")
            }
        }
    }

    private func addRecord(name: String, isShare: Bool, timestamp: Double, completion: @escaping (CKRecord?) -> Void) {
        // 指定哪個 Zone：
        let recordID = CKRecord.ID(zoneID: customZone.zoneID)
        let record = CKRecord(recordType: "Note", recordID: recordID)
        // Default Zone
//        let record = CKRecord(recordType: "Note")
        record.setValuesForKeys([
            "name": name,
            "isShare": isShare,   // Stored as Int(64)
            "timestamp": timestamp
        ])

        if isShare, let root = rootShareRecord {
            record.setParent(root)
        }

        privateDatabase.save(record) { savedRecord, error in
            guard let savedRecord, error == nil else {
                completion(nil)
                return
            }
            completion(savedRecord)
        }
    }

    func createShare(rootRecord: CKRecord) {
        let share = CKShare(rootRecord: rootRecord, shareID: CKRecord.ID(zoneID: customZone.zoneID))
        privateDatabase.modifyRecords(saving: [share, rootRecord],
                                      deleting: []) { result in
            switch result {
            case .success:
//                self.share = share
                print("Create Share Success")

            case .failure(let error):
                print("Create Share Fail - \(error)")
            }
        }
    }

    private func config() {
        fetchRootRecord { [weak self] result in
            switch result {
            case .success(_):
//                if let root = self?.rootShareRecord {
//                    self?.createShare(rootRecord: root)
//                    print("Fetch Root Record Success")
//                }
                print("Fetch Root Record Success")


            case .failure(let error):
                print("Fetch Root Record Error: \(error)")
            }
        }
    }

    private func fetchRootRecord(completion: @escaping (Result<Int,Error>) -> Void) {
        let query = CKQuery(recordType: "Note",
                            predicate: NSPredicate(format: "name == %@", "share"))
        let zoneID = customZone.zoneID

        privateDatabase.fetch(withQuery: query, inZoneWith: zoneID) { [weak self] result in
            switch result {
            case .success(let records):
                let results = records.matchResults

                if let firstRecord = results.first {
                    switch firstRecord.1 {
                    case .success(let rootShareRecord):
                        self?.rootShareRecord = rootShareRecord
                        completion(.success(0))

                    case .failure(let error):
                        completion(.failure(error))
                    }

                } else {
                    self?.addRecord(name: "share", isShare: false, timestamp: Date().timeIntervalSince1970, completion: {
                        savesRootRecord in
                        guard let savesRootRecord else {
                            completion(.failure(NSError(domain: "CloudSyncMgr", code: 1001, userInfo: nil)))
                            return
                        }
                        self?.rootShareRecord = savesRootRecord
                        completion(.success(0))
                    })
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

//    func fetchSharedNotes(in zone: CKRecordZone) async throws {
//        var changeToken: CKServerChangeToken? = nil
//        var moreChangesComing = true
//
//        while moreChangesComing {
//            let changes = try await sharedDatabase.recordZoneChanges(
//                inZoneWith: zone.zoneID,
//                since: changeToken
//            )
//
//            // Process changes as needed (modifications and deletions)
//            processChanges(changes)
//
//            moreChangesComing = changes.moreComing
//            changeToken = changes.changeToken
//        }
//    }

//    func fetchChanges(in zone: CKRecordZone) {
//        var changeToken: CKServerChangeToken? = nil
//        var moreChangesComing = true
//        var recordsChanged = [CKRecord](), recordIDsDeleted = [CKRecord.ID]()
//        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
//
//        while moreChangesComing {
//            configuration.previousServerChangeToken = changeToken
//
//            let operation = CKFetchRecordZoneChangesOperation(
//                recordZoneIDs: [zone.zoneID], configurationsByRecordZoneID: [zone.zoneID: configuration]
//            )
//
//            // Gather the changed records and process them in a batch in the completion block.
//            //
//            operation.recordChangedBlock = {
//                (record) in recordsChanged.append(record)
//            }
//
//            // Gather the deleted record IDs and process them in a batch in the completion block.
//            //
//            operation.recordWithIDWasDeletedBlock = {
//                (recordID, _) in recordIDsDeleted.append(recordID)
//            }
//
//            // Update the server change token.
//            //
//            operation.recordZoneChangeTokensUpdatedBlock = { (zoneID, serverChangeToken, _) in
//                assert(zoneID == zone.zoneID)
//                changeToken = serverChangeToken
//            }
//
//            // Fetch changes again with a nil token if the token has expired.
//            //
//            operation.recordZoneFetchCompletionBlock = {
//                (zoneID, serverChangeToken, clientChangeTokenData, moreComing, error) in
//                if let ckError = handleCloudKitError(error, operation: .fetchChanges),
//                    ckError.code == .changeTokenExpired {
//                    self.setServerChangeToken(newToken: nil)
//                    self.fetchChanges()
//
//                } else {
//                    assert(zoneID == self.zone.zoneID && moreComing == false)
//                    self.setServerChangeToken(newToken: serverChangeToken)
//                }
//            }
//
//            operation.fetchRecordZoneChangesCompletionBlock = { error in
//                // This sample calls TopicLocalCache.fetchChanges when getting a database change notification.
//                // Deleting a zone by a peer doesn't trigger a fetchRecordZoneChangesOperation.
//                //
//                // .zoneNotFound can happen when a participant removes itself from a share and the
//                // share is the only item in the current zone. In that case,
//                // cloudSharingControllerDidStopSharing deletes the cached zone, which triggers a zone switching.
//                // So this sample ignores .zoneNotFound here.
//                //
//                if let ckError = handleCloudKitError(error, operation: .fetchChanges,
//                                                     affectedObjects: [self.zone.zoneID]) {
//                    print("Error in fetchRecordZoneChangesCompletionBlock: \(ckError)")
//                }
//
//                // Filter out the updated but deleted IDs.
//                //
//                recordsChanged = recordsChanged.filter {
//                    record in return !recordIDsDeleted.contains(record.recordID)
//                }
//
//                // Update the cache with the deleted recordIDs.
//                self.performUpdatingWithRecordIDsDeleted(recordIDsDeleted)
//
//                // Update the topics and notes with the changed records.
//                //
//                self.performUpdatingTopicsWithRecordsChanged(recordsChanged)
//                self.performUpdatingNotesWithRecordsChanged(recordsChanged)
//
//                // The modification payload contains recordIDsDeleted and recordsChanged.
//                //
//                let payload = TopicCacheChanges(recordIDsDeleted: recordIDsDeleted, recordsChanged: recordsChanged)
//                let userInfo = [UserInfoKey.topicCacheChanges: payload]
//                self.performPostBlock(name: .topicCacheDidChange, userInfo: userInfo)
//
//                print("\(#function):Deleted \(recordIDsDeleted.count); Changed \(recordsChanged.count)")
//            }
//
//            operation.database = cloudKitDB
//            operationQueue.addOperation(operation)
//
//            moreChangesComing = changes.moreComing
//            changeToken = changes.changeToken
//        }
//    }
//
////    private func processChanges(_ changes: CKRecordZone.Changes) {
////        // Process modified records
////        for record in changes.modificationResults {
////            switch record {
////            case .success(let modifiedRecord):
////                print("Record modified: \(modifiedRecord.recordID)")
////                // Convert CKRecord to Item and update local data if needed
////                if let name = modifiedRecord["name"] as? String,
////                   let isShareInt = modifiedRecord["isShare"] as? Int,
////                   let timestamp = modifiedRecord["timestamp"] as? Double {
////                    let item = Item(title: name, isShare: isShareInt == 1, timestamp: timestamp, recordID: modifiedRecord.recordID)
////                    print("Processed modified item: \(item.title)")
////                    // You can add notification or callback here to update UI
////                    NotificationCenter.default.post(name: NSNotification.Name("SharedRecordModified"), object: item)
////                }
////                
////            case .failure(let error):
////                print("Failed to process modified record: \(error)")
////            }
////        }
//        
//        // Process deleted record IDs
//        for deletionResult in changes.deletionResults {
//            switch deletionResult {
//            case .success(let deletedRecordID):
//                print("Record deleted: \(deletedRecordID)")
//                // You can add notification or callback here to update UI
//                NotificationCenter.default.post(name: NSNotification.Name("SharedRecordDeleted"), object: deletedRecordID)
//                
//            case .failure(let error):
//                print("Failed to process deleted record: \(error)")
//            }
//        }
//    }

    func fetchRecords(database: CKDatabase.Scope, completion: @escaping ([Item]?) -> Void) {
        var recordList: [CKRecord] = []

        let query = CKQuery(recordType: "Note",
                            predicate: NSPredicate(value: true))
        let zoneID = CKRecordZone(zoneName: "NoteZone").zoneID
        print("fetchRecords - Searching in zone: \(zoneID)")
        let database = database == .private ? privateDatabase : sharedDatabase

        database.fetch(withQuery: query, inZoneWith: zoneID) { result in
            switch result {
            case .success(let records):
                let results = records.matchResults
                for record in results {
                    switch record.1 {
                    case .success(let record):
                        recordList.append(record)

                    case .failure(let error):
                        print("get single item error: \(error)")
                    }
                }

                // transfer data
                let items = recordList
                    .sorted {
                        $0.creationDate! < $1.creationDate!
                    }
                    .compactMap {
                        if let name = $0["name"] as? String,
                           let isShareInt = $0["isShare"] as? Int,
                           let timestamp = $0["timestamp"] as? Double {
                        print("fetchRecords - Found record '\(name)' with timestamp: \(timestamp) in zone: \($0.recordID.zoneID.zoneName)")
                        return Item(title: name, isShare: isShareInt == 1 ? true : false, timestamp: timestamp, recordID: $0.recordID)
                    } else {
                        return nil
                    }
                }

                completion(items)

            case .failure(let error):
                print("fetch error: \(error)")
                completion(nil)
            }
        }
    }

    func saveToCloud(item: Item, completion: @escaping (CKRecord.ID?) -> Void = { _ in }) {
        guard !item.title.isEmpty else { 
            completion(nil)
            return 
        }

        addRecord(name: item.title, isShare: item.isShare, timestamp: item.timestamp) { savedRecord in
            guard let savedRecord else {
                print("Saved Record is nil")
                return
            }

            print("Save Success")
            completion(savedRecord.recordID)
        }
    }

    func updateToCloud(item: Item) {
        guard let recordID = item.recordID else {
            print("updateToCloud - No recordID available, cannot update")
            return
        }
        
        print("updateToCloud - Looking for recordID: \(recordID)")
        
        privateDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
            if let record = record {
                print("updateToCloud - Found record with recordID")
                record["name"] = item.title
                record["isShare"] = item.isShare

                if item.isShare {
                    record.setParent(self?.rootShareRecord)
                } else {
                    record.parent = nil
                }

                self?.privateDatabase.save(record) { savedRecord, error in
                    guard let savedRecord, error == nil else {
                        print("Update error: \(String(describing: error))")
                        return
                    }

                    if item.isShare, let root = self?.rootShareRecord {
                        savedRecord.setParent(root)
                        self?.createShare(rootRecord: root)
                        print("Create Share Success")
                    }

                    print("Update Success")
                }

            } else if let error = error {
                print("updateToCloud - Fetch error: \(error)")
            } else {
                print("updateToCloud - Record not found")
            }
        }
    }

    func saveToCloud(readyToSave: [CKRecord]) {
        let operation = CKModifyRecordsOperation()
        operation.recordsToSave = readyToSave
        backGroundQueue.async {
            self.privateDatabase.add(operation)
        }

        operation.completionBlock = {
            DispatchQueue.main.async {
                print("Save to Cloud Finished: \(operation.isFinished)")
            }
        }
    }

    func deleteToCloud(readyToDelete: Item) {
        guard let recordID = readyToDelete.recordID else {
            print("deleteToCloud - No recordID available, cannot delete")
            return
        }
        
        print("deleteToCloud - Deleting recordID: \(recordID), name: \(readyToDelete.title)")
        let operation = CKModifyRecordsOperation()
        operation.recordIDsToDelete = [recordID]
        self.backGroundQueue.async {
            self.privateDatabase.add(operation)
        }

        operation.completionBlock = {
            DispatchQueue.main.async {
                print("Delete to Cloud Finished: \(operation.isFinished)")
            }
        }
    }

//    func setShareStatus(item: Item) {
//        let isShare = item.isShare
//        addRecord(name: item.title, isShare: item.isShare, timestamp: item.timestamp) {
//            [weak self] savedRecord in
//            guard let self, let savedRecord else { return }
//
//        }
//        let query = CKQuery(recordType: "Note",
//                            predicate: NSPredicate(format: "name == %@", "share"))
//        let zoneID = CKRecordZone(zoneName: "NoteZone").zoneID
//        privateDatabase.fetch(withQuery: query, inZoneWith: zoneID) { [weak self] result in
//            switch result {
//            case .success(let records):
//                let results = records.matchResults
//
//                if let firstRecord = results.first {
//                    switch firstRecord.1 {
//                    case .success(let rootShareRecord):
//                        guard isShare else { return }
//                        record.setParent(rootShareRecord)
//                        self?.privateDatabase.modifyRecords(saving: [rootShareRecord,self!.shareRecord!], deleting: [], completionHandler: { result in
//                            print("setShareStatus Success")
//                        })
//
//                    case .failure(let error):
//                        print("Fetch share record error: \(error)")
//                    }
//                } else {
//                    print("No share record found")
//                }
//
//            case .failure(let error):
//                print("Query error: \(error)")
//            }
//        }
//    }
}
