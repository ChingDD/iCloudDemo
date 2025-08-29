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
            self.cloudService.fetchRecords(database: localCacheDB) { recordDic in
                var tmpItems: [Item] = []
                
                // Convert CKRecord to Item
                for (database , records) in recordDic {
                    let items = records.compactMap {
                        if let name = $0["name"] as? String,
                           let isShareInt = $0["isShare"] as? Int,
                           let timestamp = $0["timestamp"] as? Double {
                            print("fetchRecords - Found record '\(name)' with timestamp: \(timestamp) in zone: \($0.recordID.zoneID.zoneName)")
                            return Item(title: name, isShare: isShareInt == 1 ? true : false, timestamp: timestamp, recordID: $0.recordID, database: database)
                        } else {
                            return nil
                        }
                    }
                    tmpItems.append(contentsOf: items)
                }
                
                tmpItems.sort { $0.timestamp < $1.timestamp }
                self.item.value = tmpItems
            }
        }
    }

    func addData(data: Item) {
        cloudService.addData(data: data, database: database) { [weak self] recordDic in
            guard let self else { return }
            var data = data
            for (database , record) in recordDic {
                data.recordID = record?.recordID
                data.database = database

                var items = item.value
                items?.append(data)
                item.value = items
            }
        }
    }

    func updateData(data: Item, index: Int) {
        cloudService.updateData(data: data, database: database) { [weak self] recordID in
            guard let self else { return }
            var items = item.value
            items?[index] = data
            item.value = items
        }
    }

    func deleteData(data: Item, index: Int) {
        cloudService.deleteData(data: data, database: database) { [weak self] recordID in
            guard let self else { return }
            var items = item.value
            items?.remove(at: index)
            item.value = items
        }
    }

    func startOperation(op: CKOperation) {
        database.startOperation(op: op)
    }

}
