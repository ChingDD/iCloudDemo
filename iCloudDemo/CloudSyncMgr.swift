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

        if isShare, let rootRecord {
            record.setParent(rootRecord)
            privateDB.modifyRecords(saving: [share, rootRecord, record],
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
            print("Update Data Error: Database Not Ready")
            completion(nil)
            return
        }
        // database
        let db = data.database ?? database.privateDatabase
        let rootRecord = database.rootShareRecord

        db.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self = self else {
                 completion(nil)
                 return
            }
 
            if let error = error {
                print("updateToCloud - Fetch error: \(error)")
                completion(nil)
                return
            }
 
            guard let record = record else {
                print("Update Data Fail - record not found")
                completion(nil)
                return
            }
            
            // Update Item
            updateRecordField(record: record, with: data, database: database)
            
            // 根據資料庫類型選擇更新方式
            if data.database?.databaseScope == .private {
                updatePrivateDBRecord(record: record, with: data, database: database, completion: completion)
            } else {
                updateShareDBRecord(record: record, with: data, completion: completion)
            }
        }
    }
    
    private func updateRecordField(record: CKRecord, with data: Item, database: LocalCacheDB) {
        record["name"] = data.title
        record["isShare"] = data.isShare
        
        let db = data.database ?? database.privateDatabase
        
        if db.databaseScope == .private {
            if data.isShare, let rootRecord = database.rootShareRecord {
                record.setParent(rootRecord)
            } else {
                record.parent = nil
            }
        }
    }
    
    private func updatePrivateDBRecord(record: CKRecord, with data: Item, database: LocalCacheDB, completion: @escaping (CKRecord.ID?) -> Void) {
        guard let db = data.database, db.databaseScope == .private else { return }
        guard let rootRecord = database.rootShareRecord else { return }
        guard let share = database.share else { return }
        
        db.modifyRecords(saving: [record, share, rootRecord], deleting: []) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(_):
                print("Update Private Record Success")
                completion(record.recordID)
            case .failure(let error):
                print("Update Private Record Error: \(error)")
                completion(nil)
            }
        }
    }
    
    private func updateShareDBRecord(record: CKRecord, with data: Item, completion: @escaping (CKRecord.ID?) -> Void) {
        guard let db = data.database, db.databaseScope == .shared else { return }
        db.save(record) { savedRecord, error in
            if let error {
                print("Update Share Record Error: \(error)")
                completion(nil)
                return
            }
            completion(savedRecord?.recordID)
        }
    }
    
    func deleteData(data: Item, database: LocalCacheDB, completion: @escaping (CKRecord.ID?) -> Void) {
        guard let recordID = data.recordID else {
            print("Add Data Error: Database Not Ready")
            return
        }

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
        // Check account status first
        CKContainer.default().accountStatus { status, error in
            print("CloudKit account status: \(status.rawValue)")
            if status != .available {
                print("CloudKit not available: \(status)")
            }
        }
        
        // Step 1: 確保 custom zone 存在
        self.createCustomZoneIfNeeded(database: database) {
            let group = DispatchGroup()
            var fetchedData = FetchedDatabaseData()
            
            // Step 2-1: 並行獲取 shared zones
            group.enter()
            self.fetchSharedZones(database: database) { zones in
                fetchedData.sharedZones = zones
                group.leave()
            }
            
            // Step 2-2: 並行獲取或創建 root record 和 share
            group.enter()
            self.fetchOrCreateRootRecordAndShare(database: database) { share, rootRecord in
                fetchedData.share = share
                fetchedData.rootRecord = rootRecord
                group.leave()
            }
            
            // Step 3: 所有操作完成後更新 LocalCacheDB
            group.notify(queue: .global()) {
                print("All database fetch tasks completed!")
                self.updateLocalCacheDB(database: database, with: fetchedData, completion: completion)
            }
        }
    }
    
    private let backGroundQueue = DispatchQueue(label: "com.Note.backgroundQueue")
    
    // MARK: - Helper Structures
    private struct FetchedDatabaseData {
        var sharedZones: [CKRecordZone]?
        var share: CKShare?
        var rootRecord: CKRecord?
    }

    init() {
//        setupDatabaseNotifications()
    }
    
    private func createCustomZoneIfNeeded(database: LocalCacheDB, completion: @escaping () -> Void) {
        let privateDB = database.privateDatabase
        let customZone = database.customZone
        
        // 檢查 custom zone 是否存在
        privateDB.fetch(withRecordZoneID: customZone.zoneID) { zone, error in
            if let error = error as? CKError, error.code == .zoneNotFound {
                // Zone 不存在，創建新的 zone
                print("Custom zone not found, creating...")
                privateDB.save(customZone) { savedZone, saveError in
                    if let saveError = saveError {
                        print("Failed to create custom zone: \(saveError)")
                    } else {
                        print("Custom zone created successfully: \(savedZone?.zoneID.zoneName ?? "unknown")")
                    }
                    completion()
                }
            } else if let zone = zone {
                print("Custom zone already exists: \(zone.zoneID.zoneName)")
                completion()
            } else {
                print("Error checking custom zone: \(error?.localizedDescription ?? "unknown error")")
                completion()
            }
        }
    }
    
    private func createShareAndRootRecord(database: LocalCacheDB, completion: @escaping (CKShare?,CKRecord?) -> Void) {
        let root = CKRecord(recordType: "Item", recordID: database.rootShareRecordID)
        let share = CKShare(rootRecord: root)
        let op = CKModifyRecordsOperation(recordsToSave: [share, root])
        op.savePolicy = .ifServerRecordUnchanged
        op.modifyRecordsCompletionBlock = { records, recordIDs, error in
            if let error = error {
                print("Create Share Error: \(error)")
                
                // 檢查 partial errors
                if let ckError = error as? CKError,
                   let partialErrors = ckError.partialErrorsByItemID {
                    for (recordID, error) in partialErrors {
                        print("Record \(recordID) failed with error: \(error)")
                    }
                }
                completion(nil,nil)
            } else {
                let rootRecord = records?.filter({ $0.recordID == database.rootShareRecordID }).first as? CKRecord
                let share = records?.filter({ $0 is CKShare }).first as? CKShare
                print("Create Share：\(share), Root Record: \(rootRecord)")
                completion(share,rootRecord)
            }
        }
        database.privateDatabase.add(op)
    }
    
    // MARK: - Refactored Helper Methods
    
    private func fetchSharedZones(database: LocalCacheDB, completion: @escaping ([CKRecordZone]?) -> Void) {
        let shareDB = database.sharedDatabase
        
        shareDB.fetchAllRecordZones { zones, error in
            if let error = error {
                print("Fetch shared zones error: \(error)")
                completion(nil)
                return
            }
            
            print("Fetched \(zones?.count ?? 0) shared zones")
            zones?.forEach { zone in
                print("Shared zone: \(zone.zoneID.zoneName)")
            }
            
            completion(zones)
        }
    }
    
    private func fetchOrCreateRootRecordAndShare(database: LocalCacheDB, completion: @escaping (CKShare?, CKRecord?) -> Void) {
        let privateDB = database.privateDatabase
        
        privateDB.fetch(withRecordID: database.rootShareRecordID) { [weak self] root, error in
            guard let self = self else {
                completion(nil, nil)
                return
            }
            
            if let error = error {
                print("Root record not found, creating new one: \(error)")
                // Root record 不存在，創建新的 root record 和 share
                self.createShareAndRootRecord(database: database, completion: completion)
            } else if let root = root {
                print("Found existing root record: \(root.recordID)")
                // Root record 存在，檢查是否有對應的 share
                self.fetchOrCreateShareForRootRecord(root: root, database: database, completion: completion)
            } else {
                print("Unexpected state: no error but no root record")
                completion(nil, nil)
            }
        }
    }
    
    private func fetchOrCreateShareForRootRecord(root: CKRecord, database: LocalCacheDB, completion: @escaping (CKShare?, CKRecord?) -> Void) {
        let privateDB = database.privateDatabase
        
        if let shareRecordID = root.share?.recordID {
            // Root record 已經有關聯的 share，獲取它
            print("Root record has associated share, fetching: \(shareRecordID)")
            privateDB.fetch(withRecordID: shareRecordID) { record, error in
                if let error = error {
                    print("Failed to fetch existing share: \(error)")
                    completion(nil, root)
                } else if let share = record as? CKShare {
                    print("Successfully fetched existing share: \(share.recordID)")
                    completion(share, root)
                } else {
                    print("Fetched record is not a CKShare")
                    completion(nil, root)
                }
            }
        } else {
            // Root record 沒有關聯的 share，創建新的 share
            print("Root record has no associated share, creating new one")
            self.createShareForExistingRootRecord(root: root, database: database, completion: completion)
        }
    }
    
    private func createShareForExistingRootRecord(root: CKRecord, database: LocalCacheDB, completion: @escaping (CKShare?, CKRecord?) -> Void) {
        let newShare = CKShare(rootRecord: root)
        let op = CKModifyRecordsOperation(recordsToSave: [root, newShare])
        op.savePolicy = .allKeys
        
        op.modifyRecordsCompletionBlock = { records, recordIDs, error in
            if let error = error {
                print("Failed to create share for existing root record: \(error)")
                
                // 檢查 partial errors
                if let ckError = error as? CKError,
                   let partialErrors = ckError.partialErrorsByItemID {
                    for (recordID, error) in partialErrors {
                        print("Record \(recordID) failed with error: \(error)")
                    }
                }
                completion(nil, root)
            } else {
                let updatedShare = records?.first(where: { $0 is CKShare }) as? CKShare
                let updatedRoot = records?.first(where: { $0.recordID == root.recordID })
                
                if let updatedShare = updatedShare {
                    print("Successfully created share for existing root record: \(updatedShare.recordID)")
                    completion(updatedShare, updatedRoot)
                } else {
                    print("Failed to find created share in response")
                    completion(nil, updatedRoot)
                }
            }
        }
        
        database.privateDatabase.add(op)
    }
    
    private func updateLocalCacheDB(database: LocalCacheDB, with data: FetchedDatabaseData, completion: @escaping (LocalCacheDB) -> Void) {
        database.sharedZone = data.sharedZones
        database.share = data.share
        database.rootShareRecord = data.rootRecord
        completion(database)
    }

    func fetchRecords(database: LocalCacheDB, completion: @escaping ([CKDatabase : [CKRecord]]) -> Void) {
        let privateDB = database.privateDatabase
        let shareDB = database.sharedDatabase
        let privateZone = database.customZone
        let sharedZone = database.sharedZone
        var totalRecordDic: [CKDatabase:[CKRecord]] = [:]
        var privateDBRecords: [CKRecord] = []
        var sharedDBRecords: [CKRecord] = []
        
        let dispatchGroup = DispatchGroup()
        
        let item = DispatchWorkItem {
            self.fetchRecords(dbType: .private, database: database, zones: [privateZone]) { records in
                privateDBRecords = records
                print("Fetch private records Success, record counts: \(records.count)")
                dispatchGroup.leave()
            }
        }
        
        let item2 = DispatchWorkItem {
            print("Fetch Shared Record")
            self.fetchRecords(dbType: .shared, database: database, zones: sharedZone) { records in
                sharedDBRecords = records
                print("Fetch share records Success, record counts: \(records.count)")
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.enter()
        DispatchQueue.global().async(execute: item)
        dispatchGroup.enter()
        DispatchQueue.global().async(execute: item2)

        dispatchGroup.notify(queue: .main) {
            totalRecordDic[privateDB] = privateDBRecords
            totalRecordDic[shareDB] = sharedDBRecords
            completion(totalRecordDic)
        }
    }

    private func fetchRecords(dbType: CKDatabase.Scope, database: LocalCacheDB, zones: [CKRecordZone]?, completion: @escaping([CKRecord]) -> Void) {
        let currentDB = dbType == .private ? database.privateDatabase : database.sharedDatabase

        let query = CKQuery(recordType: "Item",
                            predicate: NSPredicate(value: true))

        var recordList = [CKRecord]()

        let group = DispatchGroup()
        
        for zone in zones ?? [] {
            group.enter()
            currentDB.fetch(withQuery: query, inZoneWith: zone.zoneID) { result in
                defer { group.leave() }
                
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
        
        group.notify(queue: .global()) {
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
