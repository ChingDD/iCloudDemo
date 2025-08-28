//
//  PersistenceHelper.swift
//  iCloudDemo
//
//  Created by Aco on 2025/8/26.
//

import Foundation
import CloudKit

class PersistenceHelper {
    static let shareIDKey = "share"
    static let rootRecordIDKey = "rootRecord"
    static let customRecordZone = "recordZone"

    static private let defaults = UserDefaults.standard

    static func getRootRecordID() -> CKRecord.ID? {
        guard let dict = UserDefaults.standard.dictionary(forKey: rootRecordIDKey) as? [String: String],
              let recordName = dict["recordName"],
              let zoneName = dict["zoneName"],
              let ownerName = dict["ownerName"] else {
            return nil
        }
            let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
            return CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    static func setRootRecordID(_ rootRecordID: CKRecord.ID) {
        let zoneName = rootRecordID.zoneID.zoneName
        let ownerName = rootRecordID.zoneID.ownerName
        let recordName = rootRecordID.recordName

        let dic:[String : String] = [
            "recordName" : recordName,
            "zoneName" : zoneName,
            "ownerName" : ownerName
        ]

        defaults.set(dic, forKey: rootRecordIDKey)
    }

    static func getShareID() -> CKRecord.ID? {
        guard let dict = UserDefaults.standard.dictionary(forKey: shareIDKey) as? [String: String],
              let recordName = dict["recordName"],
              let zoneName = dict["zoneName"],
              let ownerName = dict["ownerName"] else {
            return nil
        }
            let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
            return CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    static func setShareID(_ rootRecordID: CKRecord.ID) {
        let zoneName = rootRecordID.zoneID.zoneName
        let ownerName = rootRecordID.zoneID.ownerName
        let recordName = rootRecordID.recordName

        let dic:[String : String] = [
            "recordName" : recordName,
            "zoneName" : zoneName,
            "ownerName" : ownerName
        ]

        defaults.set(dic, forKey: shareIDKey)
    }

}
