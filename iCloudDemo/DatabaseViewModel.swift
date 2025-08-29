//
//  DatabaseViewModel.swift
//  iCloudDemo
//
//  Created by Aco on 2025/8/29.
//

import Foundation
import CloudKit

class DatabaseViewModel {
    // Service
    let cloudService: CloudServiceProtocol

    // Database
    let database = LocalCacheDB()

    // Data
    var item: ObservableObject = ObservableObject<[Item]?>(value: [])

    init(service: CloudServiceProtocol) {
        cloudService = service
        fetchData()
    }

    func fetchData() {
        cloudService.fetchDatabase(database: database) { localCacheDB in
            self.cloudService.fetchRecords(database: localCacheDB) { records in
                // Convert CKRecord to Item
                let tmpItems = records.sorted {
                    $0.creationDate! < $1.creationDate!
                }.compactMap {
                    if let name = $0["name"] as? String,
                       let isShareInt = $0["isShare"] as? Int,
                       let timestamp = $0["timestamp"] as? Double {
                        print("fetchRecords - Found record '\(name)' with timestamp: \(timestamp) in zone: \($0.recordID.zoneID.zoneName)")
                        return Item(title: name, isShare: isShareInt == 1 ? true : false, timestamp: timestamp, recordID: $0.recordID, database: )
                    } else {
                        return nil
                    }
                }
                self.item.value = tmpItems
            }
        }
    }

    func addData(data: Item, database: LocalCacheDB) {

    }

    func updateData(data: Item, database: LocalCacheDB) {

    }

    func deleteData(data: Item, database: LocalCacheDB) {

    }

}
