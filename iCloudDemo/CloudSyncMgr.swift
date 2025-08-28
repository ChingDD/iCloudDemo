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
    private(set) var customZone: CKRecordZone?
    private let defaultZone = CKRecordZone.default()
    private var sharedZone: CKRecordZone?
    private(set) var rootShareRecord: CKRecord?
    private(set) var share: CKShare?
    private let backGroundQueue = DispatchQueue(label: "com.Note.backgroundQueue")
    private(set) var isInitialized = false
    private var initializationCallbacks: [() -> Void] = []

    init() {
        config()
        setupDatabaseNotifications()
    }

    private func addRecord(name: String, isShare: Bool, timestamp: Double, completion: @escaping (CKRecord?) -> Void) {
        // 指定哪個 Zone：
        guard let customZone else { return }

        let recordID = CKRecord.ID(zoneID: customZone.zoneID)
        let record = CKRecord(recordType: "Item", recordID: recordID)
        // Default Zone
//        let record = CKRecord(recordType: "Item")
        record.setValuesForKeys([
            "name": name,
            "isShare": isShare,   // Stored as Int(64)
            "timestamp": timestamp
        ])

        if isShare {
            if let root = rootShareRecord {
                record.setParent(root)
                print("New Record Set Parent Success")

                let share = CKShare(rootRecord: root, shareID: CKRecord.ID(zoneID: customZone.zoneID))
                privateDatabase.modifyRecords(saving: [share, root],
                                              deleting: []) { result in
                    switch result {
                    case .success(let success):
                        completion(record)

                    case .failure(let error):
                        print("Create Share Fail - \(error)")
                    }
                }
            } else {
                print("Warning: Trying to create shared record but root record not ready")
            }
        }

        privateDatabase.save(record) { [weak self] savedRecord, error in
            guard let savedRecord, error == nil else {
                print("error: \(error)")
                completion(nil)
                return
            }
            
            // 如果這是分享項目，確保share存在並與root record關聯
            if isShare {
                self?.ensureShareExists()
            }
            
            completion(savedRecord)
        }
    }

    private func createShare(rootRecord: CKRecord) {
        guard let customZone else { return }

        let share = CKShare(rootRecord: rootRecord, shareID: CKRecord.ID(zoneID: customZone.zoneID))
        privateDatabase.modifyRecords(saving: [share, rootRecord],
                                      deleting: []) { result in
            switch result {
            case .success(let success):
                for (key , value) in success.saveResults {
                    switch value {
                    case .success(let record):
                        if record.recordType == "cloudkit.share", let share = record as? CKShare {
                            share.publicPermission = .readWrite
                            self.share = share
                            PersistenceHelper.setShareID(key)
                            print("這是 Share Record: \(record)")
                        } else {
                            self.rootShareRecord = record
                            PersistenceHelper.setRootRecordID(key)
                            print("這是 Root Record: \(record)")
                        }

                    case .failure(let error):
                        print("Create Share Error: \(error)")
                    }
                }

            case .failure(let error):
                print("Create Share Fail - \(error)")
            }
        }
    }
    
    private func ensureShareExists() {
        guard let rootRecord = rootShareRecord else {
            print("No root record available for sharing")
            return
        }
        
        if share == nil {
            // Share不存在，建立新的share
            createShare(rootRecord: rootRecord)
        } else {
            // Share已存在，更新root record和share的關聯
            let op = CKModifyRecordsOperation(recordsToSave: [rootRecord, share!], recordIDsToDelete: nil)
            op.savePolicy = .allKeys
            op.modifyRecordsCompletionBlock = { records, recordIDs, error in
                if let error = error {
                    print("Failed to update share relationship: \(error)")
                } else {
                    print("Share relationship updated successfully")
                }
            }
            privateDatabase.add(op)
        }
    }

    private func config() {
        checkRecordZoneExists { [weak self] in
            self?.fetchRootRecord { [weak self] in
                self?.fetchShare { [weak self] in
                    DispatchQueue.main.async {
                        self?.isInitialized = true
                        let callbacks = self?.initializationCallbacks ?? []
                        self?.initializationCallbacks.removeAll()
                        callbacks.forEach { $0() }
                        print("CloudSyncMgr initialization completed")
                    }
                }
            }
        }
    }
    
    func performAfterInitialization(_ callback: @escaping () -> Void) {
        if isInitialized {
            callback()
        } else {
            initializationCallbacks.append(callback)
        }
    }
    
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

    private func checkRecordZoneExists(completion: @escaping () -> Void) {
        let fetchZonesOperation = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
        fetchZonesOperation.fetchRecordZonesCompletionBlock = { (recordZonesByZoneID, error) in
            if let error = error {
                print("Error fetching record zones: \(error.localizedDescription)")
                let sharedZone = CKRecordZone(zoneName: "NoteZone")
                self.privateDatabase.save(sharedZone) { zone, error in
                    if let error = error {
                        print("Failed to create custom zone: \(error)")
                    } else {
                        self.customZone = zone
                        print("Custom zone created successfully: \(String(describing: zone?.zoneID.zoneName))")
                    }
                    completion()
                }
            } else if let recordZones = recordZonesByZoneID {
                var isNoteZoneExist: Bool = false
                
                for (zoneID, recordZone) in recordZones {
                    let name = zoneID.zoneName
                    print("Fetched zone: \(name)")
                    if name == "NoteZone" {
                        self.customZone = recordZone
                        isNoteZoneExist = true
                        break
                    }
                }
                
                if !isNoteZoneExist {
                    let sharedZone = CKRecordZone(zoneName: "NoteZone")
                    self.privateDatabase.save(sharedZone) { zone, error in
                        if let error = error {
                            print("Failed to create custom zone: \(error)")
                        } else {
                            self.customZone = zone
                            print("Custom zone created successfully: \(String(describing: zone?.zoneID.zoneName))")
                        }
                        completion()
                    }
                } else {
                    completion()
                }
            }
        }

        privateDatabase.add(fetchZonesOperation)
    }

    private func fetchRootRecord(completion: @escaping () -> Void) {
        let rootRecordID = PersistenceHelper.getRootRecordID()
        if let rootRecordID {
            fetch(id: rootRecordID) { [weak self] result in
                switch result {
                case .success(let rootRecord):
                    self?.rootShareRecord = rootRecord
                    print("Fetch Root Record Success")

                case .failure(let error):
                    self?.rootShareRecord = nil
                    print("Fetch Root Record Error: \(error)")
                }
                completion()
            }
        } else {
            guard let customZone else { 
                completion()
                return 
            }

            let rootRecord = CKRecord(recordType: "RootRecord", recordID: CKRecord.ID(zoneID: customZone.zoneID))
            rootRecord["name"] = "Share Root"
            rootRecord["timestamp"] = Date().timeIntervalSince1970
            
            PersistenceHelper.setRootRecordID(rootRecord.recordID)
            rootShareRecord = rootRecord
            createShare(rootRecord: rootRecord)
            completion()
        }
    }

    private func fetchShare(completion: @escaping () -> Void) {
        let shareID = PersistenceHelper.getShareID()
        if let shareID {
            fetch(id: shareID) { [weak self] result in
                switch result {
                case .success(let share):
                    if let share = share as? CKShare {
                        share.publicPermission = .readWrite
                        self?.share = share
                        print("Fetch Share Success")
                    } else {
                        print("Transfer to Share Fail")
                    }

                case .failure(let error):
                    self?.share = nil
                    print("Fetch share Error: \(error)")
                }
                completion()
            }
        } else {
            if let rootShareRecord {
                createShare(rootRecord: rootShareRecord)
            } else {
                guard let customZone else { 
                    completion()
                    return 
                }

                let rootRecord = CKRecord(recordType: "RootRecord", recordID: CKRecord.ID(zoneID: customZone.zoneID))
                rootRecord["name"] = "Share Root"
                rootRecord["timestamp"] = Date().timeIntervalSince1970
                
                rootShareRecord = rootRecord
                createShare(rootRecord: rootRecord)
            }
            completion()
        }
    }

    func fetch(id: CKRecord.ID, completion: @escaping (Result<CKRecord,Error>) -> Void) {
        privateDatabase.fetch(withRecordID: id) { (record, error) in
            guard error == nil else {
                completion(.failure(error!))
                return
            }
            guard let record else {
                completion(.failure(NSError(domain: "Record is nil", code: 0)))
                return
            }
            completion(.success(record))
        }
    }

    func fetchRecords(database: CKDatabase.Scope, completion: @escaping ([Item]?) -> Void) {
        guard let customZone else {
            print("customZone is nil")
            return
        }

        var recordList: [CKRecord] = []

        let query = CKQuery(recordType: "Item",
                            predicate: NSPredicate(value: true))
        let usedDatabase = database == .private ? privateDatabase : sharedDatabase
        if database == .shared {
            sharedDatabase.fetchAllRecordZones { (recordZones, error) in
                if error != nil {
                    print(error?.localizedDescription)
                }
                if let recordZones = recordZones {
                    self.sharedZone = recordZones.first
                }
            }
        }

        let zoneID = database == .private ? customZone.zoneID : self.sharedZone?.zoneID
        print("fetchRecords - Searching in zone: \(zoneID)")

        usedDatabase.fetch(withQuery: query, inZoneWith: zoneID) { result in
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

        // 所有項目都儲存到private database，分享項目透過parent關係建立分享
        addRecord(name: item.title, isShare: item.isShare, timestamp: item.timestamp) { savedRecord in
            guard let savedRecord else {
                print("Saved Record is nil")
                completion(nil)
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
        
        // 更新操作總是在private database進行
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
        
        // 刪除操作總是在private database進行（原始記錄所在地）
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
    
    // MARK: - Database Notifications
    private func setupDatabaseNotifications() {
        // 註冊private database變更通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePrivateDatabaseChange(_:)),
            name: .CKAccountChanged,
            object: nil
        )
        
        // 註冊shared database變更通知
        let subscription = CKDatabaseSubscription(subscriptionID: "shared-database-changes")
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        sharedDatabase.save(subscription) { subscription, error in
            if let error = error {
                print("Failed to save shared database subscription: \(error)")
            } else {
                print("Successfully saved shared database subscription")
            }
        }
    }
    
    @objc private func handlePrivateDatabaseChange(_ notification: Notification) {
        print("Private database changed, refetching records...")
        NotificationCenter.default.post(name: .init("RefreshData"), object: nil)
    }
    
    // 處理remote notification (需要在AppDelegate中調用)
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            switch ckNotification.notificationType {
            case .database:
                if let dbNotification = ckNotification as? CKDatabaseNotification {
                    print("Database notification received: \(dbNotification)")
                    NotificationCenter.default.post(name: .init("RefreshData"), object: nil)
                }
            default:
                break
            }
        }
    }
}
