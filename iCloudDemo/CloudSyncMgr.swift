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
    private let database = CKContainer(identifier: "iCloud.com.jeff.iCloudDemo").privateCloudDatabase
    private let sharedZone = CKShare(recordZoneID: CKRecordZone(zoneName: "NoteZone").zoneID)
    private let defaultZone = CKRecordZone.default()
    private let operation = CKModifyRecordsOperation()
    private(set) var shareRecord: CKShare?
    private var rootShareRecord: CKRecord?
    private let backGroundQueue = DispatchQueue(label: "com.Note.backgroundQueue")

    init() {
        handleCompletion()
        configShare()
    }

    private func handleCompletion() {
        operation.completionBlock = {
            DispatchQueue.main.async {
                print("Cloud sync finished: \(self.operation.isFinished)")
            }
        }
    }

    private func setRecord(name: String, isShare: Bool, timestamp: Double) -> CKRecord {
        // 指定哪個 Zone：let record = CKRecord(recordType: "Note", zoneID: CKRecordZone(zoneName: "NoteZone").zoneID)
        // Default Zone
        let record = CKRecord(recordType: "Note")
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
        database.fetch(withQuery: query) { [weak self] result in
            switch result {
            case .success(let records):
                let results = records.matchResults

                if let firstRecord = results.first {
                    switch firstRecord.1 {
                    case .success(let rootShareRecord):
                        print("share record exist")

                    case .failure(let error):
                        print("Fetch share record error: \(error)")
                    }
                } else {
                    let rootShareRecord = CKRecord(recordType: "Note")
                    rootShareRecord.setValuesForKeys([
                        "name": "share",
                        "isShare": false,   // Stored as Int(64)
                        "timestamp": Date().timeIntervalSince1970
                    ])
                    let share = CKShare(rootRecord: rootShareRecord)
                    rootShareRecord.setParent(share)
                    self?.database.modifyRecords(saving: [rootShareRecord,share], deleting: [], completionHandler: { result in
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
        database.fetch(withQuery: query) { result in
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
                        return Item(title: name, isShare: isShareInt == 1 ? true : false, timestamp: timestamp)
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

    func saveToCloud(item: Item) {
        guard !item.title.isEmpty else { return }

        let record = setRecord(name: item.title, isShare: item.isShare, timestamp: item.timestamp)
        if item.isShare {
            record.setParent(self.rootShareRecord)
        }
        database.save(record) { record, error in
            guard record != nil, error == nil else {
                print("error:\(String(describing: error))")
                return
            }
            print("Save Success")
        }
    }

    func updateToCloud(item: Item) {
        let query = CKQuery(recordType: "Note", 
                           predicate: NSPredicate(format: "timestamp == %f", item.timestamp))
        
        database.fetch(withQuery: query) { [weak self] result in
            switch result {
            case .success(let records):
                let results = records.matchResults
                
                if let firstRecord = results.first {
                    switch firstRecord.1 {
                    case .success(let existingRecord):
                        existingRecord["name"] = item.title
                        existingRecord["isShare"] = item.isShare
                        
                        self?.database.save(existingRecord) { record, error in
                            guard record != nil, error == nil else {
                                print("Update error: \(String(describing: error))")
                                return
                            }
                            print("Update Success")
                        }
                        
                    case .failure(let error):
                        print("Fetch record error: \(error)")
                    }
                } else {
                    print("No record found with timestamp: \(item.timestamp)")
                }
                
            case .failure(let error):
                print("Query error: \(error)")
            }
        }
    }

    func saveToCloud(readyToSave: [CKRecord]) {
        operation.recordsToSave = readyToSave
        backGroundQueue.async {
            self.operation.start()
        }
    }
    
    func deleteToCloud(readyToDelete: Item) {
        let query = CKQuery(recordType: "Note",
                           predicate: NSPredicate(format: "timestamp == %f", readyToDelete.timestamp))
        database.fetch(withQuery: query) { [weak self] result in
            switch result {
            case .success(let records):
                let results = records.matchResults

                if let firstRecord = results.first {
                    switch firstRecord.1 {
                    case .success(let existingRecord):
                        self?.operation.recordIDsToDelete = [existingRecord.recordID]
                        self?.backGroundQueue.async {
                            self?.operation.start()
                            print("Delete record successfully")
                        }

                    case .failure(let error):
                        print("Fetch record error: \(error)")
                    }
                } else {
                    print("No record found with timestamp: \(readyToDelete.timestamp)")
                }

            case .failure(let error):
                print("Query error: \(error)")
            }
        }
    }

    func setShareStatus(item: Item) {
        let isShare = item.isShare
        let record = setRecord(name: item.title, isShare: item.isShare, timestamp: item.timestamp)
        let query = CKQuery(recordType: "Note",
                            predicate: NSPredicate(format: "name == %@", "share"))
        database.fetch(withQuery: query) { [weak self] result in
            switch result {
            case .success(let records):
                let results = records.matchResults

                if let firstRecord = results.first {
                    switch firstRecord.1 {
                    case .success(let rootShareRecord):
                        guard isShare else { return }
                        record.setParent(rootShareRecord)
                        self?.database.modifyRecords(saving: [rootShareRecord,self!.shareRecord!], deleting: [], completionHandler: { result in
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
