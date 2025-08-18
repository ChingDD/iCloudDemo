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
    private let database = CKContainer(identifier: "iCloud.com.jeff.iCloudDemo").privateCloudDatabase
    private let sharedZone = CKShare(recordZoneID: CKRecordZone(zoneName: "NoteZone").zoneID)
    private let defaultZone = CKRecordZone.default()
    private let operation = CKModifyRecordsOperation()
    private let backGroundQueue = DispatchQueue(label: "com.Note.backgroundQueue")

    init() {}

    private func handleCompletion() {
        operation.completionBlock = {
            DispatchQueue.main.async {
                print("Cloud sync finished: \(self.operation.isFinished)")
            }
        }
    }

    private func setRecord(name: String, isShare: Bool) -> CKRecord {
        // 指定哪個 Zone：let record = CKRecord(recordType: "Note", zoneID: CKRecordZone(zoneName: "NoteZone").zoneID)
        // Default Zone
        let record = CKRecord(recordType: "Note")
        record.setValuesForKeys([
            "name": name,
            "isShare": isShare,   // Stored as Int(64)
        ])
        return record
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
                    if let name = $0["name"] as? String, let isShareInt = $0["isShare"] as? Int {
                        return Item(title: name,
                                    isShare: isShareInt == 1 ? true : false)
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

    func saveToCloud(name: String?, isShare: Bool) {
        guard let name, !name.isEmpty else { return }

        let record = setRecord(name: name, isShare: isShare)
        database.save(record) { record, error in
            guard record != nil, error == nil else {
                print("error:\(String(describing: error))")
                return
            }
            print("Save Success")
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
