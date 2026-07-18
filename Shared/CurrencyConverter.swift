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
    private let currencyRateEntityLock = NSLock()
    private var currencyRateEntityStorage: CurrencyRateEntity?
    var currencyRateEntity: CurrencyRateEntity? {
        get {
            currencyRateEntityLock.lock()
            defer { currencyRateEntityLock.unlock() }
            return currencyRateEntityStorage
        }
        set {
            currencyRateEntityLock.lock()
            currencyRateEntityStorage = newValue
            currencyRateEntityLock.unlock()
        }
    }

    var context: NSExtensionContext?
    typealias RateTransport = (URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> Void

    private let clock: () -> Date
    private let defaults: UserDefaults
    private let transport: RateTransport
    private let defaultsLock = NSLock()
    private let refreshLock = NSLock()
    private var nextRefreshID: UInt64 = 0
    private var activeRefreshID: UInt64?
    private var refreshWaiters: [(Error?) -> Void] = []
    
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
        var refreshID: UInt64?

        refreshLock.lock()
        refreshWaiters.append(completionHandler)
        if activeRefreshID == nil {
            nextRefreshID &+= 1
            activeRefreshID = nextRefreshID
            refreshID = nextRefreshID
        }
        refreshLock.unlock()

        guard let refreshID else { return }

        loadFromWebRequest { [self] error in
            finishRefresh(refreshID, error: error)
        }
    }

    private func finishRefresh(_ refreshID: UInt64, error: Error?) {
        refreshLock.lock()
        guard activeRefreshID == refreshID else {
            refreshLock.unlock()
            return
        }
        activeRefreshID = nil
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        refreshLock.unlock()

        waiters.forEach { $0(error) }
    }

    private func loadFromWebRequest(_ completionHandler: @escaping (Error?) -> Void) {
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
                    let now = self.clock()
                    currencyRateEntity.fetched_localtime = now
                    self.currencyRateEntity = currencyRateEntity

                    // Save this to UserDefaults.
                    self.defaultsLock.lock()
                    self.defaults.set(now, forKey: "LastUpdateDate")
                    self.defaults.set(currencyRateEntity.rates, forKey: "CurrencyData")
                    self.defaults.set(currencyRateEntity.base, forKey:"CurrencyBase")
                    self.defaults.set(currencyRateEntity.timestamp, forKey: "CurrencyDataTime")
                    self.defaults.set(String(data: data, encoding: .utf8), forKey: "CurrencyDataRaw")
                    self.defaultsLock.unlock()
                }
            }
            completionHandler(nil)
        })
    }
    
    func loadFromDefaults() -> Bool {
        let today = clock()

        defaultsLock.lock()
        let recordValue = defaults.value(forKey: "LastUpdateDate")
        let ratesValue = defaults.value(forKey: "CurrencyData")
        let dataTimestamp = defaults.integer(forKey: "CurrencyDataTime")
        defaultsLock.unlock()

        let record = recordValue as! Date?
        guard let record = record else {
            return false
        }

        guard LegacyCachePolicy.isFresh(lastUpdated: record, now: today) else {
            return false
        }

        let rates = ratesValue as! [String:Float32]?
        guard let rates else {
            return false
        }

        print("Convert Rate Data is good from \(record) and now is \(today), load from defaults.")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)
        self.currencyRateEntity = CurrencyRateEntity(
            base: "EUR", date: todayString, rates: rates, fetched_localtime: record, timestamp: dataTimestamp
        )
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
            loadFromCacheMiss(completionHandler)
        }
    }

    func loadFromCacheMiss(_ completionHandler: @escaping (Error?) -> Void) {
        var refreshID: UInt64?
        var cacheIsFresh = false

        refreshLock.lock()
        if activeRefreshID == nil {
            // The initial cache check happened before entering this gate. Recheck
            // while claiming the refresh slot so a just-finished refresh is joined
            // without starting a second transport.
            cacheIsFresh = loadFromMemory() || loadFromDefaults()
            if !cacheIsFresh {
                nextRefreshID &+= 1
                activeRefreshID = nextRefreshID
                refreshID = nextRefreshID
                refreshWaiters.append(completionHandler)
            }
        } else {
            refreshWaiters.append(completionHandler)
        }
        refreshLock.unlock()

        if cacheIsFresh {
            completionHandler(nil)
            return
        }

        guard let refreshID else { return }

        loadFromWebRequest { [self] error in
            finishRefresh(refreshID, error: error)
        }
    }
    
    func convert(from: String, to: String, unit: Float32, completionHandler: @escaping (Float32, Error?) -> Void) {
        loadData { (error) in
            if error != nil {
                completionHandler(0.0, error)
                return
            }

            let rates = self.currencyRateEntity!.rates
            let result = LegacyConversionMath.direct(
                unit: unit,
                fromRate: rates[from]!,
                toRate: rates[to]!
            )
            completionHandler(result, nil)
        }
    }
    
    func getSymbols(completionHandler: @escaping ([String]?, Error?) -> Void) {
        loadData { (error) in
            if error != nil {
                completionHandler(nil, error)
                return
            }
            let currencyRateEntity = self.currencyRateEntity!
            let symbols = Array(currencyRateEntity.rates.keys)
            completionHandler(symbols, nil)
        }
    }
    
}
