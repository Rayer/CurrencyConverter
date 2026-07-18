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
    private var rateDataStatusStorage = RateDataStatus(
        source: nil,
        isStale: false,
        lastUpdated: nil,
        lastRefreshError: nil
    )
    var currencyRateEntity: CurrencyRateEntity? {
        get {
            currencyRateEntityLock.lock()
            defer { currencyRateEntityLock.unlock() }
            return currencyRateEntityStorage
        }
        set {
            currencyRateEntityLock.lock()
            currencyRateEntityStorage = newValue
            rateDataStatusStorage = RateDataStatus(
                source: newValue == nil ? nil : .memory,
                isStale: newValue?.fetched_localtime.map { !LegacyCachePolicy.isFresh(lastUpdated: $0, now: clock()) } ?? false,
                lastUpdated: newValue?.fetched_localtime,
                lastRefreshError: nil
            )
            currencyRateEntityLock.unlock()
        }
    }

    var rateDataStatus: RateDataStatus {
        currencyRateEntityLock.lock()
        defer { currencyRateEntityLock.unlock() }
        return rateDataStatusStorage
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

        guard let feed_url else {
            let error = RateDataError.unavailable
            self.recordRefreshFailure(error)
            completionHandler(error)
            return
        }

        transport(feed_url, { (data, response, error) in
            if error != nil {
                let refreshError = RateDataError.transport
                self.recordRefreshFailure(refreshError)
                completionHandler(refreshError)
                return
            }

            guard let response = response as? HTTPURLResponse else {
                let refreshError = RateDataError.unavailable
                self.recordRefreshFailure(refreshError)
                completionHandler(refreshError)
                return
            }

            guard (200..<300).contains(response.statusCode) else {
                let refreshError = RateDataError.httpStatus(response.statusCode)
                self.recordRefreshFailure(refreshError)
                completionHandler(refreshError)
                return
            }

            guard let data else {
                let refreshError = RateDataError.unavailable
                self.recordRefreshFailure(refreshError)
                completionHandler(refreshError)
                return
            }

            let decodedEntity: CurrencyRateEntity
            do {
                decodedEntity = try JSONDecoder().decode(CurrencyRateEntity.self, from: data)
            } catch {
                let refreshError = RateDataError.decode
                self.recordRefreshFailure(refreshError)
                completionHandler(refreshError)
                return
            }

            guard self.isValidRateEntity(decodedEntity) else {
                let refreshError = RateDataError.invalidPayload
                self.recordRefreshFailure(refreshError)
                completionHandler(refreshError)
                return
            }

            let now = self.clock()
            var validatedEntity = decodedEntity
            validatedEntity.fetched_localtime = now
            self.commitWebSnapshot(validatedEntity, rawData: data, fetchedAt: now)
            completionHandler(nil)
        })
    }
    
    func loadFromDefaults() -> Bool {
        defaultsLock.lock()
        let recordValue = defaults.value(forKey: "LastUpdateDate")
        let ratesValue = defaults.value(forKey: "CurrencyData")
        let dataTimestamp = defaults.integer(forKey: "CurrencyDataTime")
        defaultsLock.unlock()

        guard let record = recordValue as? Date,
              let rates = ratesValue as? [String: Float32] else {
            return false
        }

        let today = clock()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let entity = CurrencyRateEntity(
            base: "EUR", date: formatter.string(from: today), rates: rates,
            fetched_localtime: record, timestamp: dataTimestamp
        )
        guard isValidRateEntity(entity) else {
            return false
        }

        currencyRateEntityLock.lock()
        let hasValidMemory = currencyRateEntityStorage.map(isUsableRateEntity) ?? false
        let hadRefreshError = rateDataStatusStorage.lastRefreshError != nil
        if !hasValidMemory {
            currencyRateEntityStorage = entity
            rateDataStatusStorage = RateDataStatus(
                source: .defaults,
                isStale: !LegacyCachePolicy.isFresh(lastUpdated: record, now: today),
                lastUpdated: record,
                lastRefreshError: rateDataStatusStorage.lastRefreshError
            )
        }
        let currentSource = rateDataStatusStorage.source
        currencyRateEntityLock.unlock()
        return currentSource == .defaults && LegacyCachePolicy.isFresh(lastUpdated: record, now: today) && !hadRefreshError
    }
    
    func loadFromMemory() -> Bool {
        currencyRateEntityLock.lock()
        guard let c = currencyRateEntityStorage,
              isUsableRateEntity(c),
              let lastUpdate = c.fetched_localtime else {
            currencyRateEntityLock.unlock()
            return false
        }
        let today = clock()
        let hadRefreshError = rateDataStatusStorage.lastRefreshError != nil
        let source = rateDataStatusStorage.source ?? .memory
        rateDataStatusStorage = RateDataStatus(
            source: source,
            isStale: !LegacyCachePolicy.isFresh(lastUpdated: lastUpdate, now: today) || hadRefreshError,
            lastUpdated: lastUpdate,
            lastRefreshError: rateDataStatusStorage.lastRefreshError
        )
        let isFresh = LegacyCachePolicy.isFresh(lastUpdated: lastUpdate, now: today)
        currencyRateEntityLock.unlock()
        return isFresh && !hadRefreshError
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
        loadDataForUse { error in
            guard let entity = self.currentUsableEntity() else {
                completionHandler(0.0, error ?? RateDataError.unavailable)
                return
            }
            guard let fromRate = entity.rates[from] else {
                completionHandler(0.0, RateDataError.missingRate(from))
                return
            }
            guard let toRate = entity.rates[to] else {
                completionHandler(0.0, RateDataError.missingRate(to))
                return
            }
            completionHandler(LegacyConversionMath.direct(unit: unit, fromRate: fromRate, toRate: toRate), nil)
        }
    }
    
    func getSymbols(completionHandler: @escaping ([String]?, Error?) -> Void) {
        loadDataForUse { error in
            guard let entity = self.currentUsableEntity() else {
                completionHandler(nil, error ?? RateDataError.unavailable)
                return
            }
            completionHandler(Array(entity.rates.keys), nil)
        }
    }

    private func loadDataForUse(_ completionHandler: @escaping (Error?) -> Void) {
        currencyRateEntityLock.lock()
        let canUseLastKnownGood = currencyRateEntityStorage.map(isUsableRateEntity) == true && rateDataStatusStorage.lastRefreshError != nil
        currencyRateEntityLock.unlock()
        if canUseLastKnownGood {
            completionHandler(nil)
        } else {
            loadData(completionHandler: completionHandler)
        }
    }

    private func currentUsableEntity() -> CurrencyRateEntity? {
        currencyRateEntityLock.lock()
        defer { currencyRateEntityLock.unlock() }
        guard let entity = currencyRateEntityStorage, isUsableRateEntity(entity) else { return nil }
        return entity
    }

    private func isUsableRateEntity(_ entity: CurrencyRateEntity) -> Bool {
        isValidRateEntity(entity) && entity.fetched_localtime != nil
    }

    private func isValidRateEntity(_ entity: CurrencyRateEntity) -> Bool {
        guard !entity.base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !entity.date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !entity.rates.isEmpty else {
            return false
        }
        return entity.rates.allSatisfy { symbol, rate in
            !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rate.isFinite && rate > 0
        }
    }

    private func recordRefreshFailure(_ error: RateDataError) {
        currencyRateEntityLock.lock()
        let entity = currencyRateEntityStorage
        let source = rateDataStatusStorage.source ?? (entity == nil ? nil : .memory)
        rateDataStatusStorage = RateDataStatus(
            source: source,
            isStale: source != nil,
            lastUpdated: entity?.fetched_localtime ?? rateDataStatusStorage.lastUpdated,
            lastRefreshError: error
        )
        currencyRateEntityLock.unlock()
    }

    private func commitWebSnapshot(_ entity: CurrencyRateEntity, rawData: Data, fetchedAt: Date) {
        defaultsLock.lock()
        defaults.set(fetchedAt, forKey: "LastUpdateDate")
        defaults.set(entity.rates, forKey: "CurrencyData")
        defaults.set(entity.base, forKey: "CurrencyBase")
        defaults.set(entity.timestamp, forKey: "CurrencyDataTime")
        if let rawDataString = String(data: rawData, encoding: .utf8) {
            defaults.set(rawDataString, forKey: "CurrencyDataRaw")
        }
        currencyRateEntityLock.lock()
        currencyRateEntityStorage = entity
        rateDataStatusStorage = RateDataStatus(
            source: .web,
            isStale: false,
            lastUpdated: fetchedAt,
            lastRefreshError: nil
        )
        currencyRateEntityLock.unlock()
        defaultsLock.unlock()
    }

}
