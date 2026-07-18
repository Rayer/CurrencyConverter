//
//  CurrencyConverter.swift
//  Utilplugin
//
//  Created by Rayer on 2019/11/1.
//  Copyright © 2019 Rayer. All rights reserved.
//

import Foundation
import Cocoa

struct CurrencyRateEntity : Decodable {
    var base: String
    var date: String
    var rates: [String:Float32]
    var fetched_localtime : Date?
    var timestamp: Int
}

class CurrencyConverter {
    var currencyRateEntity: CurrencyRateEntity?
    var context: NSExtensionContext?
    typealias RateTransport = (URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> Void

    private let clock: () -> Date
    private let defaults: UserDefaults
    private let transport: RateTransport
    
    static let shared = CurrencyConverter()
    private init() {
        clock = Date.init
        defaults = sharedUserDefaults
        transport = { url, completion in
            URLSession.shared.dataTask(with: url, completionHandler: completion).resume()
        }
    }

    init(context: NSExtensionContext? = nil, clock: @escaping () -> Date = Date.init, defaults: UserDefaults = sharedUserDefaults, transport: RateTransport? = nil) {
        self.context = context
        self.clock = clock
        self.defaults = defaults
        self.transport = transport ?? { url, completion in
            URLSession.shared.dataTask(with: url, completionHandler: completion).resume()
        }
        print("Setting context : \(String(describing: context))")
    }
    
    func loadFromWeb(_ completionHandler: @escaping (Error?) -> Void) {
        let feed_url : URL?
        if let feed_url_str = Bundle.main.object(forInfoDictionaryKey: "CurrencyInfoFeed") as? String {
            feed_url = URL(string: feed_url_str)
        } else {
            feed_url = URL(string: "http://data.fixer.io/api/latest?access_key=676ac77e5ce5d4b9a57ee6464ff84433&format=1")
        }
        
        print("Loading currency data from \(String(describing: feed_url?.absoluteString))")

        transport(feed_url!, { (data, response, error) in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                completionHandler(error)
                return
            } else if let response = response as? HTTPURLResponse,let data = data {
                print("Status code: \(response.statusCode)")
                let decoder = JSONDecoder()
                if var currencyRateEntity = try? decoder.decode(CurrencyRateEntity.self, from: data) {
                    self.currencyRateEntity = currencyRateEntity
                    //Save this to UserDefaults
                    let now = self.clock()
                    currencyRateEntity.fetched_localtime = now
                    self.defaults.set(now, forKey: "LastUpdateDate")
                    self.defaults.set(currencyRateEntity.rates, forKey: "CurrencyData")
                    self.defaults.set(currencyRateEntity.base, forKey:"CurrencyBase")
                    self.defaults.set(currencyRateEntity.timestamp, forKey: "CurrencyDataTime")
                    self.defaults.set(String(data: data, encoding: .utf8), forKey: "CurrencyDataRaw")
                }
            }
            completionHandler(nil)
        })
    }
    
    func loadFromDefaults() -> Bool {
        let today = clock()
        
        guard let record = defaults.value(forKey: "LastUpdateDate") as! Date? else {
            return false
        }
        
        guard LegacyCachePolicy.isFresh(lastUpdated: record, now: today) else {
            return false
        }
        
        guard let rates = defaults.value(forKey: "CurrencyData") as! [String:Float32]? else {
            return false
        }
        
        let dataTimestamp = defaults.integer(forKey: "CurrencyDataTime")
        
        print("Convert Rate Data is good from \(record) and now is \(today), load from defaults.")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)
        self.currencyRateEntity = CurrencyRateEntity(base: "EUR", date: todayString, rates: rates, timestamp: dataTimestamp)
        self.currencyRateEntity?.fetched_localtime = record
        return true
    }
    
    func loadFromMemory() -> Bool {
        guard let c = currencyRateEntity else {
            return false
        }
        
        guard let last_update = c.fetched_localtime else {
            NSLog("loadFromMemory() fetched_localtime is null!")
            return false
        }
        
        let today = clock()
        guard LegacyCachePolicy.isFresh(lastUpdated: last_update, now: today) else {
            NSLog("Convert Rate Data in Memory not found or too old (\(last_update) vs \(today)), load from Defaults....")
            return false
        }
        
        NSLog("Convert Rate Data in Memory is good (\(last_update) vs \(today))")
        return true
    }
    
    func loadData(completionHandler: @escaping (Error?) -> Void = {_ in }) {
        
        if loadFromMemory() {
            completionHandler(nil)
            return
        }
        
        if loadFromDefaults() {
            completionHandler(nil)
        } else {
            NSLog("Convert Rate Data in Defaults not found or too old, load from web....")
            loadFromWeb(completionHandler)
        }
        
    }
    
    func convert(from: String, to: String, unit: Float32, completionHandler: @escaping (Float32, Error?) -> Void) {
        loadData { (error) in
            if error != nil {
                completionHandler(0.0, error)
                return
            }
            
            let result = LegacyConversionMath.direct(
                unit: unit,
                fromRate: self.currencyRateEntity!.rates[from]!,
                toRate: self.currencyRateEntity!.rates[to]!
            )
            completionHandler(result, nil)
        }
    }
    
    func getSymbols(completionHandler: @escaping ([String]?, Error?) -> Void) {
        loadData { (error) in
            if error != nil {
                completionHandler(nil, error)
            }
            completionHandler(Array((self.currencyRateEntity?.rates.keys)!), nil)
        }
    }
    
}
