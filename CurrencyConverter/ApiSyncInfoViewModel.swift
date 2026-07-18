//
//  APISyncInfoDataModel.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/14.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation

class ApiSyncInfoViewModel : ObservableObject {
    @Published var data: ApiSyncInfoViewModel?
    @Published private(set) var rateStatus = CurrencyConverter.shared.rateDataStatus
    var userDefaults: UserDefaults
    var lastUpdate: String?
    var parsedPayloadUpdate: String?
    var rawData: String?
    
    init(_ host : UserDefaults) {
        userDefaults = host
        loadFromUserDefaults(host)
    }
    
    func loadFromUserDefaults(_ host : UserDefaults, rateStatus: RateDataStatus? = nil) {
        self.userDefaults = host
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd hh:mm:ss"
        if let date = host.object(forKey: "LastUpdateDate") as? Date {
            lastUpdate = formatter.string(from: date)
        } else {
            lastUpdate = nil
        }
        parsedPayloadUpdate = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(host.integer(forKey: "CurrencyDataTime"))))
        rawData = host.string(forKey: "CurrencyDataRaw")
        self.rateStatus = rateStatus ?? CurrencyConverter.shared.rateDataStatus
        data = self
    }
    
    func sync() {
        CurrencyConverter.shared.loadFromWeb { [self] _ in
            DispatchQueue.main.async {
                let refreshedStatus = CurrencyConverter.shared.rateDataStatus
                self.loadFromUserDefaults(sharedUserDefaults, rateStatus: refreshedStatus)
            }
        }
    }
}
