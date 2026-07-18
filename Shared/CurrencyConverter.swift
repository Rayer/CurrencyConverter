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
            let now = newValue?.fetched_localtime == nil ? nil : clock()
            let isStale = newValue?.fetched_localtime.map { fetchedAt in
                guard let now else { return false }
                return !LegacyCachePolicy.isFresh(lastUpdated: fetchedAt, now: now)
            } ?? false
            currencyRateEntityLock.lock()
            currencyRateEntityStorage = newValue
            rateDataStatusStorage = RateDataStatus(
                source: newValue == nil ? nil : .memory,
                isStale: isStale,
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
    // When both are needed, defaultsLock is acquired before currencyRateEntityLock;
    // injected defaults callbacks never run while the entity lock is held.
    private let defaultsLock = NSRecursiveLock()
    private var isPersistingWebSnapshot = false
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
        defer { defaultsLock.unlock() }
        guard !isPersistingWebSnapshot else { return false }

        let now = clock()
        let formatter = providerDateFormatter()

        let recordValue = defaults.value(forKey: "LastUpdateDate")
        let ratesValue = defaults.value(forKey: "CurrencyData")
        let baseValue = defaults.value(forKey: "CurrencyBase")
        let rawDataValue = defaults.value(forKey: "CurrencyDataRaw")
        let dataTimestamp = defaults.integer(forKey: "CurrencyDataTime")

        guard let record = recordValue as? Date,
              let rates = ratesValue as? [String: Float32] else {
            return false
        }

        let rawEntity: CurrencyRateEntity? = {
            guard let rawDataString = rawDataValue as? String,
                  let rawData = rawDataString.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(CurrencyRateEntity.self, from: rawData),
                  isValidRateEntity(decoded) else {
                return nil
            }
            return decoded
        }()
        let persistedBase = (baseValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = persistedBase.flatMap { $0.isEmpty ? nil : $0 } ?? rawEntity?.base ?? "EUR"
        let date = rawEntity.map { isValidProviderDate($0.date) ? $0.date : formatter.string(from: record) }
            ?? formatter.string(from: record)
        let entity = CurrencyRateEntity(
            base: base, date: date, rates: rates,
            fetched_localtime: record, timestamp: dataTimestamp
        )
        guard isValidRateEntity(entity) else {
            return false
        }

        let defaultsIsFresh = LegacyCachePolicy.isFresh(lastUpdated: record, now: now)
        currencyRateEntityLock.lock()
        defer { currencyRateEntityLock.unlock() }
        let currentStatus = rateDataStatusStorage
        if defaultsIsFresh {
            currencyRateEntityStorage = entity
            rateDataStatusStorage = RateDataStatus(
                source: .defaults,
                isStale: false,
                lastUpdated: record,
                lastRefreshError: nil
            )
            return true
        }

        let memoryCandidate: (CurrencyRateEntity, RateDataSource)? = {
            guard let memory = currencyRateEntityStorage,
                  isUsableRateEntity(memory),
                  memory.fetched_localtime != nil else {
                return nil
            }
            let source = currentStatus.source ?? .memory
            return (memory, source)
        }()
        let candidates: [(CurrencyRateEntity, RateDataSource)] = [memoryCandidate, (entity, .defaults)].compactMap { $0 }
        if let selected = candidates.max(by: { ($0.0.fetched_localtime ?? .distantPast) < ($1.0.fetched_localtime ?? .distantPast) }) {
            currencyRateEntityStorage = selected.0
            rateDataStatusStorage = RateDataStatus(
                source: selected.1,
                isStale: true,
                lastUpdated: selected.0.fetched_localtime,
                lastRefreshError: currentStatus.lastRefreshError
            )
        }
        return false
    }
    
    func loadFromMemory() -> Bool {
        let now = clock()
        currencyRateEntityLock.lock()
        guard let c = currencyRateEntityStorage,
              isUsableRateEntity(c),
              let lastUpdate = c.fetched_localtime else {
            currencyRateEntityLock.unlock()
            return false
        }
        let hadRefreshError = rateDataStatusStorage.lastRefreshError != nil
        let source = rateDataStatusStorage.source ?? .memory
        rateDataStatusStorage = RateDataStatus(
            source: source,
            isStale: !LegacyCachePolicy.isFresh(lastUpdated: lastUpdate, now: now) || hadRefreshError,
            lastUpdated: lastUpdate,
            lastRefreshError: rateDataStatusStorage.lastRefreshError
        )
        let isFresh = LegacyCachePolicy.isFresh(lastUpdated: lastUpdate, now: now)
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
        convertWithStatus(from: from, to: to, unit: unit) { result, _, error in
            completionHandler(result, error)
        }
    }

    func convertWithStatus(
        from: String,
        to: String,
        unit: Float32,
        completionHandler: @escaping (Float32, RateDataStatus, Error?) -> Void
    ) {
        loadDataForUse { error in
            let snapshot = self.currentUsableSnapshot()
            guard let entity = snapshot.entity else {
                completionHandler(0.0, snapshot.status, error ?? RateDataError.unavailable)
                return
            }
            guard let fromRate = entity.rates[from] else {
                completionHandler(0.0, snapshot.status, RateDataError.missingRate(from))
                return
            }
            guard let toRate = entity.rates[to] else {
                completionHandler(0.0, snapshot.status, RateDataError.missingRate(to))
                return
            }
            completionHandler(
                LegacyConversionMath.direct(unit: unit, fromRate: fromRate, toRate: toRate),
                snapshot.status,
                nil
            )
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
        currentUsableSnapshot().entity
    }

    private func currentUsableSnapshot() -> (entity: CurrencyRateEntity?, status: RateDataStatus) {
        currencyRateEntityLock.lock()
        defer { currencyRateEntityLock.unlock() }
        let entity = currencyRateEntityStorage.flatMap { isUsableRateEntity($0) ? $0 : nil }
        return (entity, rateDataStatusStorage)
    }

    private func isUsableRateEntity(_ entity: CurrencyRateEntity) -> Bool {
        isValidRateEntity(entity) && entity.fetched_localtime != nil
    }

    private func isValidRateEntity(_ entity: CurrencyRateEntity) -> Bool {
        guard !entity.base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              isValidProviderDate(entity.date),
              !entity.rates.isEmpty else {
            return false
        }
        return entity.rates.allSatisfy { symbol, rate in
            !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rate.isFinite && rate > 0
        }
    }

    private func recordRefreshFailure(_ error: RateDataError) {
        currencyRateEntityLock.lock()
        guard let entity = currencyRateEntityStorage, isUsableRateEntity(entity) else {
            rateDataStatusStorage = RateDataStatus(
                source: nil,
                isStale: false,
                lastUpdated: nil,
                lastRefreshError: error
            )
            currencyRateEntityLock.unlock()
            return
        }
        let source = rateDataStatusStorage.source ?? .memory
        rateDataStatusStorage = RateDataStatus(
            source: source,
            isStale: true,
            lastUpdated: entity.fetched_localtime,
            lastRefreshError: error
        )
        currencyRateEntityLock.unlock()
    }

    private func commitWebSnapshot(_ entity: CurrencyRateEntity, rawData: Data, fetchedAt: Date) {
        defaultsLock.lock()
        isPersistingWebSnapshot = true
        defer {
            isPersistingWebSnapshot = false
            defaultsLock.unlock()
        }
        defaults.set(fetchedAt, forKey: "LastUpdateDate")
        defaults.set(entity.rates, forKey: "CurrencyData")
        defaults.set(entity.base, forKey: "CurrencyBase")
        defaults.set(entity.timestamp, forKey: "CurrencyDataTime")
        if let rawDataString = String(data: rawData, encoding: .utf8) {
            defaults.set(rawDataString, forKey: "CurrencyDataRaw")
        }
        currencyRateEntityLock.lock()
        defer { currencyRateEntityLock.unlock() }
        currencyRateEntityStorage = entity
        rateDataStatusStorage = RateDataStatus(
            source: .web,
            isStale: false,
            lastUpdated: fetchedAt,
            lastRefreshError: nil
        )
    }

    private func providerDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    private func isValidProviderDate(_ value: String) -> Bool {
        let formatter = providerDateFormatter()
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

}
