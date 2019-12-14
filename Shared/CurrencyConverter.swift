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
}

class CurrencyConverter {
    var currencyRateEntity: CurrencyRateEntity?
    var context: NSExtensionContext?
    
    static let shared = CurrencyConverter()
    private init(){}

    init(context: NSExtensionContext? = nil) {
        self.context = context
        print("Setting context : \(String(describing: context))")
    }
    
    fileprivate func loadFromWeb(_ completionHandler: @escaping (Error?) -> Void) {
        let feed_url = URL(string: "http://data.fixer.io/api/latest?access_key=676ac77e5ce5d4b9a57ee6464ff84433&format=1")
        URLSession.shared.dataTask(with: feed_url!) { (data, response, error) in
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
                    let now = Date()
                    currencyRateEntity.fetched_localtime = now
                    UserDefaults.standard.set(now, forKey: "LastUpdateDate")
                    UserDefaults.standard.set(currencyRateEntity.rates, forKey: "CurrencyData")
                    UserDefaults.standard.set(currencyRateEntity.base, forKey:"CurrencyBase")
                }
            }
            completionHandler(nil)
        }.resume()
    }
    
    func loadFromDefaults() -> Bool {
        let today = Date()
        
        guard let record = UserDefaults.standard.value(forKey: "LastUpdateDate") as! Date? else {
            return false
        }
        
        guard record.addingTimeInterval(24.0 * 60.0 * 60.0) > today else {
            return false
        }
        
        guard let rates = UserDefaults.standard.value(forKey: "CurrencyData") as! [String:Float32]? else {
            return false
        }
        print("Convert Rate Data is good from \(record) and now is \(today), load from defaults.")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)
        self.currencyRateEntity = CurrencyRateEntity(base: "EUR", date: todayString, rates: rates)
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
        
        let today = Date()
        guard last_update.addingTimeInterval(24.0 * 60.0 * 60.0) > today else {
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
            
            let fromRate = self.currencyRateEntity?.rates[from]!
            let toRate = self.currencyRateEntity?.rates[to]!
            
            completionHandler((unit / fromRate!) * toRate!, nil)
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
