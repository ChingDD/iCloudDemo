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
    private let sharedZone = CKShare(recordZoneID: CKRecordZone(zoneName: "NoteZone").zoneID)
    private let defaultZone = CKRecordZone.default()
    private(set) var shareRecord: CKShare?
    private(set) var rootShareRecord: CKRecord?
    private let backGroundQueue = DispatchQueue(label: "com.Note.backgroundQueue")

    init() {
        createCustomZoneIfNeeded()
        configShare()
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

    private func setRecord(name: String, isShare: Bool, timestamp: Double) -> CKRecord {
        // 指定哪個 Zone：
        let zoneID = CKRecordZone(zoneName: "NoteZone").zoneID
        let record = CKRecord(recordType: "Note", recordID: CKRecord.ID(zoneID: zoneID))
        // Default Zone
//        let record = CKRecord(recordType: "Note")
        record.setValuesForKeys([
            "name": name,
            "isShare": isShare,   // Stored as Int(64)
            "timestamp": timestamp
        ])
        return record
    }

    private func configShare() {
        let query = CKQuery(recordType: "Note",
                            predicate: NSPredicate(format: "name == %@", "share"))
        let zoneID = CKRecordZone(zoneName: "NoteZone").zoneID
        privateDatabase.fetch(withQuery: query, inZoneWith: zoneID) { [weak self] result in
            switch result {
            case .success(let records):
                let results = records.matchResults

                if let firstRecord = results.first {
                    switch firstRecord.1 {
                    case .success(let rootShareRecord):
                        let share = CKShare(rootRecord: rootShareRecord)
                        self?.rootShareRecord = rootShareRecord
                        self?.shareRecord = share
                        print("share record exist")

                    case .failure(let error):
                        print("Fetch share record error: \(error)")
                    }
                } else {
                    let rootShareRecord = CKRecord(recordType: "Note", recordID: CKRecord.ID(zoneID: zoneID))
                    rootShareRecord.setValuesForKeys([
                        "name": "share",
                        "isShare": false,   // Stored as Int(64)
                        "timestamp": Date().timeIntervalSince1970
                    ])
                    let share = CKShare(rootRecord: rootShareRecord)
                    self?.privateDatabase.modifyRecords(saving: [rootShareRecord,share], deleting: [], completionHandler: { result in
                        print("configShare | set Share Status Success")
                    })

                    self?.rootShareRecord = rootShareRecord
                    self?.shareRecord = share
                }

            case .failure(let error):
                print("Query error: \(error)")
            }
        }
    }

    func fetchRecords(completion: @escaping ([Item]?) -> Void) {
        var recordList: [CKRecord] = []

        let query = CKQuery(recordType: "Note",
                            predicate: NSPredicate(value: true))
        let zoneID = CKRecordZone(zoneName: "NoteZone").zoneID
        print("fetchRecords - Searching in zone: \(zoneID)")
        privateDatabase.fetch(withQuery: query, inZoneWith: zoneID) { result in
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

        let record = setRecord(name: item.title, isShare: item.isShare, timestamp: item.timestamp)
        if item.isShare {
            record.setParent(self.rootShareRecord)
        }
        privateDatabase.save(record) { savedRecord, error in
            guard let savedRecord = savedRecord, error == nil else {
                print("error:\(String(describing: error))")
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
                    guard savedRecord != nil, error == nil else {
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

    func setShareStatus(item: Item) {
        let isShare = item.isShare
        let record = setRecord(name: item.title, isShare: item.isShare, timestamp: item.timestamp)
        let query = CKQuery(recordType: "Note",
                            predicate: NSPredicate(format: "name == %@", "share"))
        let zoneID = CKRecordZone(zoneName: "NoteZone").zoneID
        privateDatabase.fetch(withQuery: query, inZoneWith: zoneID) { [weak self] result in
            switch result {
            case .success(let records):
                let results = records.matchResults

                if let firstRecord = results.first {
                    switch firstRecord.1 {
                    case .success(let rootShareRecord):
                        guard isShare else { return }
                        record.setParent(rootShareRecord)
                        self?.privateDatabase.modifyRecords(saving: [rootShareRecord,self!.shareRecord!], deleting: [], completionHandler: { result in
                            print("setShareStatus Success")
                        })

                    case .failure(let error):
                        print("Fetch share record error: \(error)")
                    }
                } else {
                    print("No share record found")
                }

            case .failure(let error):
                print("Query error: \(error)")
            }
        }
    }
}
