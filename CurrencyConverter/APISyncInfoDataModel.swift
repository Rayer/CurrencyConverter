//
//  APISyncInfoDataModel.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/14.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation

class APISyncInfoDataModel {
    var userDefaults: UserDefaults
    var lastUpdate: String?
    var parsedPayloadUpdate: String?
    var rawData: String?
    
    init(_ host : UserDefaults) {
        userDefaults = host
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd hh:mm:ss"
        lastUpdate = formatter.string(from: host.object(forKey: "LastUpdateDate") as! Date)
        parsedPayloadUpdate = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(host.integer(forKey: "CurrencyDataTime"))))
        rawData = host.string(forKey: "CurrencyDataRaw")
    }
}

