//
//  CurrencySymbolMap.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/23.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation

/*
 {
 "symbol": "NT$",
 "name": "New Taiwan Dollar",
 "symbol_native": "NT$",
 "code": "TWD",
 "emoji": "🇹🇼"
 },
 */
struct CountryCurrencyData : Codable {
    var symbol: String
    var name: String
    var symbol_native: String
    var code: String
    var emoji: String
}

struct Countries : Codable {
    var currencies : [CountryCurrencyData]
}

class CountryCurrency {
    
    var data : [String:CountryCurrencyData] = [:]
    static var shared = CountryCurrency()
    
    init() {
        do {
            if let bundlePath = Bundle.main.path(forResource: "CurrencyCountry", ofType: "json") {
                let jsonData = try String(contentsOfFile: bundlePath).data(using: .utf8)
                let decoder = JSONDecoder()
                let decoded = try decoder.decode(Countries.self, from: jsonData!)
                decoded.currencies.forEach { (CountryCurrencyData) in
                    data[CountryCurrencyData.code] = CountryCurrencyData
                }
            }
        } catch {
            print(error)
        }
    }
    
    func getFlag(symbol: String) -> String {
        return data[symbol]?.emoji ?? ""
    }
}
