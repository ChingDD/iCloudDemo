//
//  CloudeSyncMgr.swift
//  iCloudDemo
//
//  Created by 林仲景 on 2025/8/11.
//

import Foundation
import CloudKit
protocol CloudServiceProtocol{
    func addData(data: Item, database: LocalCacheDB, completion: @escaping ([CKDatabase : CKRecord?]) -> Void)
    func updateData(data: Item, database: LocalCacheDB, completion: @escaping (CKRecord.ID?) -> Void)
    func deleteData(data: Item, database: LocalCacheDB, completion: @escaping (CKRecord.ID?) -> Void)
    func fetchDatabase(database: LocalCacheDB, completion: @escaping (LocalCacheDB) -> Void)
    func fetchRecords(database: LocalCacheDB, completion: @escaping ([CKDatabase : [CKRecord]]) -> Void)
}

class CloudSyncMgr: CloudServiceProtocol {
    func addData(data: Item, database: LocalCacheDB, completion: @escaping ([CKDatabase : CKRecord?]) -> Void) {
        guard let share = database.share else {
            print("Add Data Error: Database Not Ready")
            return
        }
        // database
        let privateDB = database.privateDatabase
        let zone = database.customZone
        let rootRecord = database.rootShareRecord

        // data
        let name = data.title
        let isShare = data.isShare
        let timestamp = data.timestamp

        let recordID = CKRecord.ID(zoneID: zone.zoneID)
        let record = CKRecord(recordType: "Item", recordID: recordID)

        var recordDic: [CKDatabase : CKRecord?] = [:]

        record.setValuesForKeys([
            "name": name,
            "isShare": isShare,   // Stored as Int(64)
            "timestamp": timestamp
        ])

        if isShare {
            record.setParent(rootRecord)
            privateDB.modifyRecords(saving: [share, rootRecord],
                                          deleting: []) { result in
                switch result {
                case .success(let success):
                    print("Add Record Success")
                    recordDic[privateDB] = record

                case .failure(let error):
                    print("Add Record Error: \(error)")
                    recordDic[privateDB] = nil
                }
                completion(recordDic)

            }
        } else {
            privateDB.save(record) { savedRecord, error in
                if error != nil {
                    print("Add Record Error: \(error)")
                    recordDic[privateDB] = nil
                    completion(recordDic)
                    return
                }
                print("Add Record Success")
                recordDic[privateDB] = record
                completion(recordDic)
            }
        }
    }
    
    func updateData(data: Item, database: LocalCacheDB, completion: @escaping (CKRecord.ID?) -> Void) {
        guard let share = database.share,
              let recordID = data.recordID else {
            print("Add Data Error: Database Not Ready")
            return
        }
        // database
        let privateDB = database.privateDatabase
        let zone = database.customZone
        let rootRecord = database.rootShareRecord

        privateDB.fetch(withRecordID: recordID) { record, error in
            if error != nil {
                print("updateToCloud - Fetch error: \(error)")
                return
            }

            if let record = record {
                print("updateToCloud - Found record with recordID")
                record["name"] = data.title
                record["isShare"] = data.isShare

                if data.isShare {
                    record.setParent(rootRecord)
                } else {
                    record.parent = nil
                }

                privateDB.modifyRecords(saving: [share, rootRecord],
                                              deleting: []) { result in
                    switch result {
                    case .success(let success):
                        completion(recordID)
                        print("Update Record Success")

                    case .failure(let error):
                        completion(recordID)
                        print("Update Record Error: \(error)")
                    }
                }
            }
        }
    }
    
    func deleteData(data: Item, database: LocalCacheDB, completion: @escaping (CKRecord.ID?) -> Void) {
        guard let share = database.share,
              let recordID = data.recordID else {
            print("Add Data Error: Database Not Ready")
            return
        }
        // database
        let privateDB = database.privateDatabase
        let zone = database.customZone
        let rootRecord = database.rootShareRecord

        let operation = CKModifyRecordsOperation()
        operation.recordIDsToDelete = [recordID]
        data.database?.add(operation)
        operation.completionBlock = {
            DispatchQueue.main.async {
                completion(recordID)
                print("Delete to Cloud Finished: \(operation.isFinished)")
            }
        }
    }
    
    func fetchDatabase(database: LocalCacheDB, completion: @escaping (LocalCacheDB) -> Void) {
        let privateDB = database.privateDatabase
        let shareDB = database.sharedDatabase
        let shareID = database.rootShareRecord.share?.recordID

        var sharedZone: [CKRecordZone]?
        var share: CKShare?

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2

        let fetchSharedZoneOP = BlockOperation {
            // Fetch Shared Zone
            shareDB.fetchAllRecordZones { zones, error in
                if error != nil {
                    print("Fetch shared zone error: \(error)")
                    return
                }
                sharedZone = zones
            }
        }

        let fetchShareOP = BlockOperation {
            // Fetch Share
            if let shareID = shareID {
                privateDB.fetch(withRecordID: shareID) { record, error in
                    if error != nil {
                        print("Fetch Share Error: \(error)")
                        return
                    }
                    guard let shareData = record as? CKShare else {
                        print("Transform Record Error")
                        return
                    }
                    share = shareData
                }
            }
        }

        queue.addOperation(fetchSharedZoneOP)
        queue.addOperation(fetchShareOP)
        queue.addBarrierBlock {
            print("All tasks done!")
            let localCacheDB = database
            localCacheDB.sharedZone = sharedZone
            localCacheDB.share = share
            completion(localCacheDB)
        }
    }
    
    private let backGroundQueue = DispatchQueue(label: "com.Note.backgroundQueue")

    init() {
//        setupDatabaseNotifications()
    }

    func fetchRecords(database: LocalCacheDB, completion: @escaping ([CKDatabase : [CKRecord]]) -> Void) {
        let privateDB = database.privateDatabase
        let shareDB = database.sharedDatabase
        let privateZone = database.customZone
        let sharedZone = database.sharedZone
        var totalRecordDic: [CKDatabase:[CKRecord]] = [:]
        let dispatchGroup = DispatchGroup()

        let item = DispatchWorkItem {
            dispatchGroup.enter()
            self.fetchRecords(database: privateDB, zones: [privateZone]) { records in
                totalRecordDic[privateDB] = records
                print("Fetch private records Success")
                dispatchGroup.leave()
            }
        }

        let item2 = DispatchWorkItem {
            dispatchGroup.enter()
            self.fetchRecords(database: shareDB, zones: sharedZone) { records in
                totalRecordDic[shareDB] = records
                print("Fetch share records Success")
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            completion(totalRecordDic)
        }
    }

    private func fetchRecords(database: CKDatabase, zones: [CKRecordZone]?, completion: @escaping([CKRecord]) -> Void) {
        guard let zones else {
            print("Zone is nil")
            return
        }

        let query = CKQuery(recordType: "Item",
                            predicate: NSPredicate(value: true))

        var recordList = [CKRecord]()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 3

        for zone in zones {
            let op = BlockOperation {
                database.fetch(withQuery: query, inZoneWith: zone.zoneID) { result in
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

                    case .failure(let error):
                        print("fetch error: \(error)")
                    }
                }
            }
            queue.addOperation(op)
        }

        queue.addBarrierBlock {
            print("Fetch Records Complete")
            completion(recordList)
        }
    }

//    private func ensureShareExists() {
//        guard let rootRecord = rootShareRecord else {
//            print("No root record available for sharing")
//            return
//        }
//        
//        if share == nil {
//            // Share不存在，建立新的share
//            createShare(rootRecord: rootRecord)
//        } else {
//            // Share已存在，更新root record和share的關聯
//            let op = CKModifyRecordsOperation(recordsToSave: [rootRecord, share!], recordIDsToDelete: nil)
//            op.savePolicy = .allKeys
//            op.modifyRecordsCompletionBlock = { records, recordIDs, error in
//                if let error = error {
//                    print("Failed to update share relationship: \(error)")
//                } else {
//                    print("Share relationship updated successfully")
//                }
//            }
//            privateDatabase.add(op)
//        }
//    }

//    private func createCustomZoneIfNeeded() {
//        privateDatabase.fetch(withRecordZoneID: customZone.zoneID) { [weak self] zone, error in
//            if let error = error as? CKError, error.code == .zoneNotFound {
//                // Zone不存在，建立新的zone
//                self?.privateDatabase.save(self!.customZone) { zone, error in
//                    if let error = error {
//                        print("Failed to create custom zone: \(error)")
//                    } else {
//                        print("Custom zone created successfully: \(String(describing: zone?.zoneID.zoneName))")
//                    }
//                }
//            } else if let zone = zone {
//                print("Custom zone already exists: \(zone.zoneID.zoneName)")
//            } else if let error = error {
//                print("Error checking custom zone: \(error)")
//            }
//        }
//    }
//
//    private func checkRecordZoneExists(completion: @escaping () -> Void) {
//        let fetchZonesOperation = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
//        fetchZonesOperation.fetchRecordZonesCompletionBlock = { (recordZonesByZoneID, error) in
//            if let error = error {
//                print("Error fetching record zones: \(error.localizedDescription)")
//                let sharedZone = CKRecordZone(zoneName: "NoteZone")
//                self.privateDatabase.save(sharedZone) { zone, error in
//                    if let error = error {
//                        print("Failed to create custom zone: \(error)")
//                    } else {
//                        self.customZone = zone
//                        print("Custom zone created successfully: \(String(describing: zone?.zoneID.zoneName))")
//                    }
//                    completion()
//                }
//            } else if let recordZones = recordZonesByZoneID {
//                var isNoteZoneExist: Bool = false
//                
//                for (zoneID, recordZone) in recordZones {
//                    let name = zoneID.zoneName
//                    print("Fetched zone: \(name)")
//                    if name == "NoteZone" {
//                        self.customZone = recordZone
//                        isNoteZoneExist = true
//                        break
//                    }
//                }
//                
//                if !isNoteZoneExist {
//                    let sharedZone = CKRecordZone(zoneName: "NoteZone")
//                    self.privateDatabase.save(sharedZone) { zone, error in
//                        if let error = error {
//                            print("Failed to create custom zone: \(error)")
//                        } else {
//                            self.customZone = zone
//                            print("Custom zone created successfully: \(String(describing: zone?.zoneID.zoneName))")
//                        }
//                        completion()
//                    }
//                } else {
//                    completion()
//                }
//            }
//        }
//
//        privateDatabase.add(fetchZonesOperation)
//    }
//
//    func fetch(id: CKRecord.ID, completion: @escaping (Result<CKRecord,Error>) -> Void) {
//        privateDatabase.fetch(withRecordID: id) { (record, error) in
//            guard error == nil else {
//                completion(.failure(error!))
//                return
//            }
//            guard let record else {
//                completion(.failure(NSError(domain: "Record is nil", code: 0)))
//                return
//            }
//            completion(.success(record))
//        }
//    }

//    func saveToCloud(item: Item, completion: @escaping (CKRecord.ID?) -> Void = { _ in }) {
//        guard !item.title.isEmpty else { 
//            completion(nil)
//            return 
//        }
//
//        // 所有項目都儲存到private database，分享項目透過parent關係建立分享
//        addRecord(name: item.title, isShare: item.isShare, timestamp: item.timestamp) { savedRecord in
//            guard let savedRecord else {
//                print("Saved Record is nil")
//                completion(nil)
//                return
//            }
//
//            print("Save Success")
//            completion(savedRecord.recordID)
//        }
//    }
//
//    func updateToCloud(item: Item) {
//        guard let recordID = item.recordID else {
//            print("updateToCloud - No recordID available, cannot update")
//            return
//        }
//        
//        print("updateToCloud - Looking for recordID: \(recordID)")
//        
//        // 更新操作總是在private database進行
//        privateDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
//            if let record = record {
//                print("updateToCloud - Found record with recordID")
//                record["name"] = item.title
//                record["isShare"] = item.isShare
//
//                if item.isShare {
//                    record.setParent(self?.rootShareRecord)
//                } else {
//                    record.parent = nil
//                }
//
//                self?.privateDatabase.save(record) { savedRecord, error in
//                    guard let savedRecord, error == nil else {
//                        print("Update error: \(String(describing: error))")
//                        return
//                    }
//
//                    print("Update Success")
//                }
//
//            } else if let error = error {
//                print("updateToCloud - Fetch error: \(error)")
//            } else {
//                print("updateToCloud - Record not found")
//            }
//        }
//    }
//
//    func saveToCloud(readyToSave: [CKRecord]) {
//        let operation = CKModifyRecordsOperation()
//        operation.recordsToSave = readyToSave
//        backGroundQueue.async {
//            self.privateDatabase.add(operation)
//        }
//
//        operation.completionBlock = {
//            DispatchQueue.main.async {
//                print("Save to Cloud Finished: \(operation.isFinished)")
//            }
//        }
//    }
//
//    func deleteToCloud(readyToDelete: Item) {
//        guard let recordID = readyToDelete.recordID else {
//            print("deleteToCloud - No recordID available, cannot delete")
//            return
//        }
//        
//        print("deleteToCloud - Deleting recordID: \(recordID), name: \(readyToDelete.title)")
//        
//        // 刪除操作總是在private database進行（原始記錄所在地）
//        let operation = CKModifyRecordsOperation()
//        operation.recordIDsToDelete = [recordID]
//        
//        self.backGroundQueue.async {
//            self.privateDatabase.add(operation)
//        }
//
//        operation.completionBlock = {
//            DispatchQueue.main.async {
//                print("Delete to Cloud Finished: \(operation.isFinished)")
//            }
//        }
//    }
//    
//    // MARK: - Database Notifications
//    private func setupDatabaseNotifications() {
//        // 註冊private database變更通知
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(handlePrivateDatabaseChange(_:)),
//            name: .CKAccountChanged,
//            object: nil
//        )
//        
//        // 註冊shared database變更通知
//        let subscription = CKDatabaseSubscription(subscriptionID: "shared-database-changes")
//        let notificationInfo = CKSubscription.NotificationInfo()
//        notificationInfo.shouldSendContentAvailable = true
//        subscription.notificationInfo = notificationInfo
//        
//        sharedDatabase.save(subscription) { subscription, error in
//            if let error = error {
//                print("Failed to save shared database subscription: \(error)")
//            } else {
//                print("Successfully saved shared database subscription")
//            }
//        }
//    }
//    
//    @objc private func handlePrivateDatabaseChange(_ notification: Notification) {
//        print("Private database changed, refetching records...")
//        NotificationCenter.default.post(name: .init("RefreshData"), object: nil)
//    }
//    
//    // 處理remote notification (需要在AppDelegate中調用)
//    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
//        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
//            switch ckNotification.notificationType {
//            case .database:
//                if let dbNotification = ckNotification as? CKDatabaseNotification {
//                    print("Database notification received: \(dbNotification)")
//                    NotificationCenter.default.post(name: .init("RefreshData"), object: nil)
//                }
//            default:
//                break
//            }
//        }
//    }
}
