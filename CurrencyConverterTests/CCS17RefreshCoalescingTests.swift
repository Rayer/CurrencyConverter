import XCTest
@testable import CurrencyConverter

private final class CCS17ControlledTransport {
    typealias Completion = (Data?, URLResponse?, Error?) -> Void

    private let lock = NSLock()
    private var pendingCompletions: [Completion] = []
    private var requestCountValue = 0
    private let requestStarted = DispatchSemaphore(value: 0)
    private let defaultTimeout: TimeInterval = 2

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCountValue
    }

    func send(_ url: URL, completion: @escaping Completion) {
        lock.lock()
        requestCountValue += 1
        pendingCompletions.append(completion)
        lock.unlock()
        requestStarted.signal()
    }

    func waitForRequest() -> Bool {
        if requestStarted.wait(timeout: .now() + defaultTimeout) != .success {
            XCTFail("waitForRequest timeout")
            return false
        }
        return true
    }

    func finishNext(data: Data? = nil, response: URLResponse? = nil, error: Error? = nil) -> Bool {
        lock.lock()
        guard !pendingCompletions.isEmpty else {
            lock.unlock()
            XCTFail("No pending transport completions to drain")
            return false
        }
        let completion = pendingCompletions.removeFirst()
        lock.unlock()
        completion(data, response, error)
        return true
    }
}

private final class CCS17MemoryDefaults: UserDefaults {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return storage[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value = value {
            storage[defaultName] = value
        } else {
            storage.removeValue(forKey: defaultName)
        }
    }

    override func integer(forKey defaultName: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage[defaultName] as? Int ?? 0
    }

    override func value(forKey key: String) -> Any? {
        object(forKey: key)
    }
}

private final class CCS17ObservedConverter: CurrencyConverter {
    private let refreshEntry = DispatchSemaphore(value: 0)
    private let directLoadEntry = DispatchSemaphore(value: 0)

    func waitForRefreshEntry() -> Bool {
        if refreshEntry.wait(timeout: .now() + 2) != .success {
            XCTFail("waitForRefreshEntry timeout")
            return false
        }
        return true
    }

    func waitForDirectLoadEntry() -> Bool {
        if directLoadEntry.wait(timeout: .now() + 2) != .success {
            XCTFail("waitForDirectLoadEntry timeout")
            return false
        }
        return true
    }

    override func loadFromCacheMiss(_ completionHandler: @escaping (Error?) -> Void) {
        super.loadFromCacheMiss(completionHandler)
        refreshEntry.signal()
    }

    override func loadFromWeb(_ completionHandler: @escaping (Error?) -> Void) {
        super.loadFromWeb(completionHandler)
        directLoadEntry.signal()
    }
}

private final class CCS17LateJoinConverter: CurrencyConverter {
    private let lock = NSLock()
    private var cacheMissCount = 0
    private let secondCacheMissEntered = DispatchSemaphore(value: 0)
    private let releaseSecondCacheMiss = DispatchSemaphore(value: 0)

    func waitForSecondCacheMiss() -> Bool {
        if secondCacheMissEntered.wait(timeout: .now() + 2) != .success {
            XCTFail("waitForSecondCacheMiss timeout")
            return false
        }
        return true
    }

    func releasePausedCacheMiss() {
        releaseSecondCacheMiss.signal()
    }

    override func loadFromCacheMiss(_ completionHandler: @escaping (Error?) -> Void) {
        lock.lock()
        cacheMissCount += 1
        let shouldPause = cacheMissCount == 2
        lock.unlock()

        if shouldPause {
            secondCacheMissEntered.signal()
            guard releaseSecondCacheMiss.wait(timeout: .now() + 2) == .success else {
                XCTFail("releaseSecondCacheMiss timeout")
                return
            }
        }
        super.loadFromCacheMiss(completionHandler)
    }
}

final class CCS17RefreshCoalescingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1000)
    private let successData = Data(#"{"base":"EUR","date":"2026-07-18","rates":{"USD":1.0,"JPY":110.0},"timestamp":123}"#.utf8)

    func testConcurrentStaleLoadsUseOneTransportAndFanOutSuccessOnce() {
        let transport = CCS17ControlledTransport()
        let converter = makeObservedStaleConverter(transport: transport)
        let completionExpectation = expectation(description: "all callers complete")
        completionExpectation.expectedFulfillmentCount = 16
        completionExpectation.assertForOverFulfill = true
        let results = LockedResults()

        let didLaunch = startConcurrentLoads(on: converter, count: 16) { error in
            results.append(error: error, rate: converter.currencyRateEntity?.rates["USD"])
            completionExpectation.fulfill()
        }
        guard didLaunch else { return }
        guard transport.waitForRequest() else { return }
        XCTAssertEqual(transport.requestCount, 1)
        for _ in 0..<16 {
            guard converter.waitForRefreshEntry() else { return }
        }

        guard transport.finishNext(
            data: successData,
            response: HTTPURLResponse(url: URL(string: "https://example.test")!, statusCode: 200, httpVersion: nil, headerFields: nil)
        ) else { return }
        wait(for: [completionExpectation], timeout: 1)

        XCTAssertEqual(results.count, 16)
        XCTAssertTrue(results.errors.allSatisfy { $0 == nil })
        XCTAssertTrue(results.rates.allSatisfy { $0 == 1 })
    }

    func testConcurrentStaleLoadsFanOutTransportFailureOnceWithoutTrailingNil() {
        let transport = CCS17ControlledTransport()
        let converter = makeObservedStaleConverter(transport: transport)
        let completionExpectation = expectation(description: "all callers complete")
        completionExpectation.expectedFulfillmentCount = 16
        completionExpectation.assertForOverFulfill = true
        let results = LockedResults()
        let failure = NSError(domain: "CCS17", code: 17)

        let didLaunchFailCase = startConcurrentLoads(on: converter, count: 16) { error in
            results.append(error: error, rate: nil)
            completionExpectation.fulfill()
        }
        guard didLaunchFailCase else { return }
        guard transport.waitForRequest() else { return }
        XCTAssertEqual(transport.requestCount, 1)
        for _ in 0..<16 {
            guard converter.waitForRefreshEntry() else { return }
        }
        guard transport.finishNext(error: failure) else { return }
        wait(for: [completionExpectation], timeout: 1)

        XCTAssertEqual(results.count, 16)
        XCTAssertTrue(results.errors.allSatisfy { ($0 as? RateDataError) == .transport })
        XCTAssertEqual(results.nilErrorCount, 0)
    }

    func testFailedRefreshClearsInFlightStateForRetry() {
        let transport = CCS17ControlledTransport()
        let converter = makeStaleConverter(transport: transport)
        let failureExpectation = expectation(description: "failure completion")
        let failure = NSError(domain: "CCS17", code: 18)

        converter.loadData { error in
            XCTAssertEqual(error as? RateDataError, .transport)
            failureExpectation.fulfill()
        }
        guard transport.waitForRequest() else { return }
        XCTAssertEqual(transport.requestCount, 1)
        guard transport.finishNext(error: failure) else { return }
        wait(for: [failureExpectation], timeout: 1)

        let retryExpectation = expectation(description: "retry completion")
        converter.loadData { error in
            XCTAssertNil(error)
            XCTAssertEqual(converter.currencyRateEntity?.rates["USD"], 1)
            retryExpectation.fulfill()
        }
        guard transport.waitForRequest() else { return }
        XCTAssertEqual(transport.requestCount, 2)
        guard transport.finishNext(
            data: successData,
            response: HTTPURLResponse(url: URL(string: "https://example.test")!, statusCode: 200, httpVersion: nil, headerFields: nil)
        ) else { return }
        wait(for: [retryExpectation], timeout: 1)
    }

    func testFreshMemoryAndDefaultsCompleteWithoutTransport() {
        let memoryTransport = CCS17ControlledTransport()
        let memoryConverter = makeStaleConverter(transport: memoryTransport)
        memoryConverter.currencyRateEntity = CurrencyRateEntity(
            base: "EUR", date: "2026-07-18", rates: ["USD": 1], fetched_localtime: now, timestamp: 123
        )
        let memoryExpectation = expectation(description: "fresh memory callers complete")
        memoryExpectation.expectedFulfillmentCount = 8
        memoryExpectation.assertForOverFulfill = true
        let didLaunchMemory = startConcurrentLoads(on: memoryConverter, count: 8) { error in
            XCTAssertNil(error)
            memoryExpectation.fulfill()
        }
        guard didLaunchMemory else { return }
        wait(for: [memoryExpectation], timeout: 1)
        XCTAssertEqual(memoryTransport.requestCount, 0)

        let defaultsTransport = CCS17ControlledTransport()
        let defaults = CCS17MemoryDefaults()
        defaults.set(now, forKey: "LastUpdateDate")
        defaults.set(["USD": Float32(1)], forKey: "CurrencyData")
        defaults.set(123, forKey: "CurrencyDataTime")
        let defaultsConverter = CurrencyConverter(clock: { self.now }, defaults: defaults, transport: defaultsTransport.send)
        let defaultsExpectation = expectation(description: "fresh defaults callers complete")
        defaultsExpectation.expectedFulfillmentCount = 8
        defaultsExpectation.assertForOverFulfill = true
        let didLaunchDefaults = startConcurrentLoads(on: defaultsConverter, count: 8) { error in
            XCTAssertNil(error)
            defaultsExpectation.fulfill()
        }
        guard didLaunchDefaults else { return }
        wait(for: [defaultsExpectation], timeout: 1)
        XCTAssertEqual(defaultsTransport.requestCount, 0)
    }

    func testSynchronousTransportCompletionDoesNotLoseCompletionOrLeaveRefreshInFlight() {
        let defaults = CCS17MemoryDefaults()
        var transportCount = 0
        let response = HTTPURLResponse(url: URL(string: "https://example.test")!, statusCode: 200, httpVersion: nil, headerFields: nil)
        let failure = NSError(domain: "CCS17", code: 19)
        let converter = CurrencyConverter(clock: { self.now }, defaults: defaults) { [self] _, completion in
            transportCount += 1
            if transportCount == 1 {
                completion(nil, nil, failure)
            } else {
                completion(successData, response, nil)
            }
        }

        let firstExpectation = expectation(description: "synchronous failure completion")
        converter.loadData { error in
            XCTAssertEqual(error as? RateDataError, .transport)
            firstExpectation.fulfill()
        }
        wait(for: [firstExpectation], timeout: 1)

        XCTAssertEqual(transportCount, 1)
        let retryExpectation = expectation(description: "synchronous retry completion")
        converter.loadData { error in
            XCTAssertNil(error)
            retryExpectation.fulfill()
        }
        wait(for: [retryExpectation], timeout: 1)
        XCTAssertEqual(transportCount, 2)
    }

    func testLateCacheMissJoinsFreshCacheAfterRefreshFinishes() {
        let transport = CCS17ControlledTransport()
        let converter = CCS17LateJoinConverter(clock: { self.now }, defaults: CCS17MemoryDefaults(), transport: transport.send)
        let firstCompletion = expectation(description: "first refresh completion")

        converter.loadData { error in
            XCTAssertNil(error)
            firstCompletion.fulfill()
        }
        guard transport.waitForRequest() else { return }
        XCTAssertEqual(transport.requestCount, 1)

        let secondCompletion = expectation(description: "late cache miss completion")
        DispatchQueue.global().async {
            converter.loadData { error in
                XCTAssertNil(error)
                secondCompletion.fulfill()
            }
        }
        guard converter.waitForSecondCacheMiss() else { return }

        guard transport.finishNext(
            data: self.successData,
            response: HTTPURLResponse(url: URL(string: "https://example.test")!, statusCode: 200, httpVersion: nil, headerFields: nil)
        ) else { return }
        wait(for: [firstCompletion], timeout: 1)

        converter.releasePausedCacheMiss()
        wait(for: [secondCompletion], timeout: 1)
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testConcurrentCurrencyRateEntitySnapshotsAreSafe() {
        let converter = makeStaleConverter(transport: CCS17ControlledTransport())
        let work = DispatchGroup()
        let queue = DispatchQueue.global()

        for index in 0..<100 {
            work.enter()
            queue.async {
                converter.currencyRateEntity = CurrencyRateEntity(
                    base: "EUR",
                    date: "2026-07-18",
                    rates: ["USD": Float32(index)],
                    fetched_localtime: self.now,
                    timestamp: index
                )
                work.leave()
            }

            work.enter()
            queue.async {
                _ = converter.currencyRateEntity?.rates["USD"]
                work.leave()
            }
        }

        guard work.wait(timeout: .now() + 2) == .success else {
            XCTFail("currency rate snapshot test timeout")
            return
        }
    }

    private func makeStaleConverter(transport: CCS17ControlledTransport) -> CurrencyConverter {
        CurrencyConverter(clock: { self.now }, defaults: CCS17MemoryDefaults(), transport: transport.send)
    }

    private func makeObservedStaleConverter(transport: CCS17ControlledTransport) -> CCS17ObservedConverter {
        CCS17ObservedConverter(clock: { self.now }, defaults: CCS17MemoryDefaults(), transport: transport.send)
    }

    private func startConcurrentLoads(
        on converter: CurrencyConverter,
        count: Int,
        completion: @escaping (Error?) -> Void
    ) -> Bool {
        let ready = DispatchGroup()
        let start = CCS17StartGate()
        for _ in 0..<count {
            ready.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                ready.leave()
                start.wait()
                converter.loadData(completionHandler: completion)
            }
        }
        guard ready.wait(timeout: .now() + 2) == .success else {
            XCTFail("startConcurrentLoads ready timeout")
            return false
        }
        for _ in 0..<count {
            start.open()
        }
        return true
    }

    func testConcurrentDirectLoadFromWebCallsCoalesceWithFreshCache() {
        let transport = CCS17ControlledTransport()
        let converter = makeObservedStaleConverter(transport: transport)
        converter.currencyRateEntity = CurrencyRateEntity(
            base: "EUR",
            date: "2026-07-18",
            rates: ["USD": Float32(1)],
            fetched_localtime: now,
            timestamp: 123
        )
        let completionExpectation = expectation(description: "all force refresh callers complete")
        completionExpectation.expectedFulfillmentCount = 2
        completionExpectation.assertForOverFulfill = true
        let results = LockedResults()

        DispatchQueue.global().async {
            converter.loadFromWeb { error in
                results.append(error: error, rate: converter.currencyRateEntity?.rates["USD"])
                completionExpectation.fulfill()
            }
        }
        guard transport.waitForRequest() else { return }
        guard converter.waitForDirectLoadEntry() else { return }

        DispatchQueue.global().async {
            converter.loadFromWeb { error in
                results.append(error: error, rate: converter.currencyRateEntity?.rates["USD"])
                completionExpectation.fulfill()
            }
        }
        guard converter.waitForDirectLoadEntry() else { return }
        XCTAssertEqual(transport.requestCount, 1)

        guard transport.finishNext(
            data: successData,
            response: HTTPURLResponse(
                url: URL(string: "https://example.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        ) else { return }
        wait(for: [completionExpectation], timeout: 1)

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.errors.allSatisfy { $0 == nil })
        XCTAssertTrue(results.rates.allSatisfy { $0 == Float32(1) })
    }
}

private final class CCS17StartGate {
    private let condition = NSCondition()
    private var isOpen = false

    func wait() {
        condition.lock()
        while !isOpen {
            condition.wait()
        }
        condition.unlock()
    }

    func open() {
        condition.lock()
        isOpen = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class LockedResults {
    private let lock = NSLock()
    private(set) var count = 0
    private(set) var errors: [Error?] = []
    private(set) var rates: [Float32?] = []

    var nilErrorCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return errors.filter { $0 == nil }.count
    }

    func append(error: Error?, rate: Float32?) {
        lock.lock()
        count += 1
        errors.append(error)
        rates.append(rate)
        lock.unlock()
    }
}
