import XCTest
@testable import CurrencyConverter

private final class CCS10Transport {
    typealias Completion = (Data?, URLResponse?, Error?) -> Void

    private let lock = NSLock()
    private var completions: [Completion] = []
    private var requestCountValue = 0
    private let requestStarted = DispatchSemaphore(value: 0)

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCountValue
    }

    func send(_ url: URL, completion: @escaping Completion) {
        lock.lock()
        requestCountValue += 1
        completions.append(completion)
        lock.unlock()
        requestStarted.signal()
    }

    func waitForRequest() -> Bool {
        guard requestStarted.wait(timeout: .now() + 1) == .success else {
            XCTFail("request start timeout")
            return false
        }
        return true
    }

    @discardableResult
    func finish(data: Data? = nil, response: URLResponse? = nil, error: Error? = nil) -> Bool {
        lock.lock()
        guard !completions.isEmpty else {
            lock.unlock()
            XCTFail("No pending transport completion to drain")
            return false
        }
        let completion = completions.removeFirst()
        lock.unlock()
        completion(data, response, error)
        return true
    }
}

private class CCS10Defaults: UserDefaults {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return storage[defaultName]
    }

    override func value(forKey key: String) -> Any? { object(forKey: key) }

    override func integer(forKey defaultName: String) -> Int {
        object(forKey: defaultName) as? Int ?? 0
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[defaultName] = value
    }
}

private final class CCS10SnapshotBarrierDefaults: CCS10Defaults {
    let snapshotCaptured = DispatchSemaphore(value: 0)
    let releaseSnapshot = DispatchSemaphore(value: 0)
    var onSet: (() -> Void)?

    override func integer(forKey defaultName: String) -> Int {
        let value = super.integer(forKey: defaultName)
        snapshotCaptured.signal()
        _ = releaseSnapshot.wait(timeout: .now() + 2)
        return value
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        onSet?()
        super.set(value, forKey: defaultName)
    }
}

final class CCS10RateFallbackTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1000)
    private let response = HTTPURLResponse(
        url: URL(string: "https://example.test")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!

    func testTransportFailureFansOutAndConversionUsesStaleMemoryWithoutSecondRequest() {
        let transport = CCS10Transport()
        let converter = makeConverter(transport: transport)
        let original = CurrencyRateEntity(
            base: "EUR", date: "2026-07-16", rates: ["USD": 1, "JPY": 110],
            fetched_localtime: now.addingTimeInterval(-2 * LegacyCachePolicy.lifetime), timestamp: 123
        )
        converter.currencyRateEntity = original
        let completion = expectation(description: "joined load callers")
        completion.expectedFulfillmentCount = 2
        var errors: [RateDataError?] = []
        let errorLock = NSLock()

        for _ in 0..<2 {
            converter.loadData { error in
                errorLock.lock()
                errors.append(error as? RateDataError)
                errorLock.unlock()
                completion.fulfill()
            }
        }
        XCTAssertEqual(transport.requestCount, 1)
        guard transport.waitForRequest() else { return }
        guard transport.finish(error: URLError(.notConnectedToInternet)) else { return }
        wait(for: [completion], timeout: 1)

        XCTAssertEqual(errors, [.transport, .transport])
        XCTAssertEqual(converter.currencyRateEntity?.rates, original.rates)
        XCTAssertEqual(converter.rateDataStatus.source, .memory)
        XCTAssertTrue(converter.rateDataStatus.isStale)
        XCTAssertEqual(converter.rateDataStatus.lastRefreshError, .transport)

        let conversion = expectation(description: "stale conversion")
        converter.convert(from: "JPY", to: "USD", unit: 110) { amount, error in
            XCTAssertNil(error)
            XCTAssertEqual(amount, 1, accuracy: 0.0001)
            conversion.fulfill()
        }
        wait(for: [conversion], timeout: 1)
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testHTTPFailureKeepsStaleDefaultsAndTimestamp() {
        let transport = CCS10Transport()
        let defaults = CCS10Defaults()
        let updated = now.addingTimeInterval(-2 * LegacyCachePolicy.lifetime)
        defaults.set(updated, forKey: "LastUpdateDate")
        defaults.set(["USD": Float32(1)], forKey: "CurrencyData")
        defaults.set(123, forKey: "CurrencyDataTime")
        let converter = CurrencyConverter(clock: { self.now }, defaults: defaults, transport: transport.send)

        let completion = expectation(description: "http failure")
        converter.loadData { error in
            XCTAssertEqual(error as? RateDataError, .httpStatus(503))
            completion.fulfill()
        }
        XCTAssertEqual(transport.requestCount, 1)
        guard transport.waitForRequest() else { return }
        guard transport.finish(
            data: Data(#"{"message":"ignored"}"#.utf8),
            response: HTTPURLResponse(url: response.url!, statusCode: 503, httpVersion: nil, headerFields: nil)
        ) else { return }
        wait(for: [completion], timeout: 1)

        XCTAssertEqual(defaults.object(forKey: "LastUpdateDate") as? Date, updated)
        XCTAssertEqual(converter.currencyRateEntity?.rates["USD"], 1)
        XCTAssertEqual(converter.rateDataStatus.source, .defaults)
        XCTAssertTrue(converter.rateDataStatus.isStale)
        XCTAssertEqual(converter.rateDataStatus.lastRefreshError, .httpStatus(503))
    }

    func testInvalidPayloadWithoutCacheReturnsBoundedTypedError() {
        let transport = CCS10Transport()
        let converter = makeConverter(transport: transport)
        let completion = expectation(description: "invalid payload")

        converter.loadData { error in
            XCTAssertEqual(error as? RateDataError, .invalidPayload)
            XCTAssertNil(converter.currencyRateEntity)
            XCTAssertEqual(converter.rateDataStatus.source, nil)
            XCTAssertFalse(converter.rateDataStatus.message.contains("ignored"))
            completion.fulfill()
        }
        guard transport.waitForRequest() else { return }
        guard transport.finish(
            data: Data(#"{"base":"EUR","date":"2026-07-18","rates":{},"timestamp":123}"#.utf8),
            response: response
        ) else { return }
        wait(for: [completion], timeout: 1)
    }

    func testMalformedProviderDateIsInvalidPayload() {
        let transport = CCS10Transport()
        let converter = makeConverter(transport: transport)
        let completion = expectation(description: "malformed provider date")

        converter.loadData { error in
            XCTAssertEqual(error as? RateDataError, .invalidPayload)
            completion.fulfill()
        }
        guard transport.waitForRequest() else { return }
        guard transport.finish(
            data: Data(#"{"base":"EUR","date":"2026-02-30","rates":{"USD":1.2},"timestamp":456}"#.utf8),
            response: response
        ) else { return }
        wait(for: [completion], timeout: 1)
    }

    func testDecodeFailureWithoutCacheReturnsTypedDecodeError() {
        let transport = CCS10Transport()
        let converter = makeConverter(transport: transport)
        let completion = expectation(description: "decode failure")

        converter.loadData { error in
            XCTAssertEqual(error as? RateDataError, .decode)
            XCTAssertNil(converter.currencyRateEntity)
            completion.fulfill()
        }
        guard transport.waitForRequest() else { return }
        guard transport.finish(data: Data("not-json".utf8), response: response) else { return }
        wait(for: [completion], timeout: 1)
    }

    func testMissingHTTPResponseWithoutCacheReturnsUnavailableError() {
        let transport = CCS10Transport()
        let converter = makeConverter(transport: transport)
        let completion = expectation(description: "unavailable response")

        converter.loadData { error in
            XCTAssertEqual(error as? RateDataError, .unavailable)
            XCTAssertNil(converter.currencyRateEntity)
            completion.fulfill()
        }
        guard transport.waitForRequest() else { return }
        guard transport.finish(data: Data(), response: nil) else { return }
        wait(for: [completion], timeout: 1)
    }

    func testMissingRateIsTypedAndDoesNotCrash() {
        let converter = makeConverter(transport: CCS10Transport())
        converter.currencyRateEntity = CurrencyRateEntity(
            base: "EUR", date: "2026-07-18", rates: ["USD": 1],
            fetched_localtime: now, timestamp: 123
        )
        let completion = expectation(description: "missing rate")

        converter.convert(from: "JPY", to: "USD", unit: 1) { amount, error in
            XCTAssertEqual(amount, 0)
            XCTAssertEqual(error as? RateDataError, .missingRate("JPY"))
            completion.fulfill()
        }
        wait(for: [completion], timeout: 1)
    }

    func testValidRefreshAtomicallyReplacesSnapshotAndClearsFailureStatus() {
        let transport = CCS10Transport()
        let converter = makeConverter(transport: transport)
        converter.currencyRateEntity = CurrencyRateEntity(
            base: "EUR", date: "2026-07-16", rates: ["USD": 1],
            fetched_localtime: now.addingTimeInterval(-2 * LegacyCachePolicy.lifetime), timestamp: 123
        )

        let failed = expectation(description: "first failure")
        converter.loadData { error in
            XCTAssertEqual(error as? RateDataError, .transport)
            failed.fulfill()
        }
        guard transport.waitForRequest() else { return }
        guard transport.finish(error: URLError(.cannotLoadFromNetwork)) else { return }
        wait(for: [failed], timeout: 1)

        let recovered = expectation(description: "recovery")
        converter.loadData { error in
            XCTAssertNil(error)
            XCTAssertEqual(converter.currencyRateEntity?.rates["USD"], 1.2)
            XCTAssertEqual(converter.rateDataStatus.source, .web)
            XCTAssertFalse(converter.rateDataStatus.isStale)
            XCTAssertNil(converter.rateDataStatus.lastRefreshError)
            recovered.fulfill()
        }
        XCTAssertEqual(transport.requestCount, 2)
        guard transport.waitForRequest() else { return }
        guard transport.finish(
            data: Data(#"{"base":"EUR","date":"2026-07-18","rates":{"USD":1.2},"timestamp":456}"#.utf8),
            response: response
        ) else { return }
        wait(for: [recovered], timeout: 1)
    }

    func testFreshDefaultsReplaceStaleMemoryWithoutTransport() {
        let transport = CCS10Transport()
        let defaults = CCS10Defaults()
        defaults.set(now, forKey: "LastUpdateDate")
        defaults.set(["USD": Float32(2)], forKey: "CurrencyData")
        defaults.set(456, forKey: "CurrencyDataTime")
        let converter = makeConverter(defaults: defaults, transport: transport)
        converter.currencyRateEntity = CurrencyRateEntity(
            base: "EUR", date: "2026-07-16", rates: ["USD": 1],
            fetched_localtime: now.addingTimeInterval(-2 * LegacyCachePolicy.lifetime), timestamp: 123
        )

        XCTAssertTrue(converter.loadFromDefaults())
        XCTAssertEqual(converter.currencyRateEntity?.rates["USD"], 2)
        XCTAssertEqual(converter.currencyRateEntity?.timestamp, 456)
        XCTAssertEqual(converter.rateDataStatus.source, .defaults)
        XCTAssertFalse(converter.rateDataStatus.isStale)
        XCTAssertNil(converter.rateDataStatus.lastRefreshError)
        XCTAssertEqual(transport.requestCount, 0)
    }

    func testDefaultsUsePersistedBaseRawDateAndExistingRateMetadata() {
        let defaults = CCS10Defaults()
        let fetchedAt = now.addingTimeInterval(-60)
        defaults.set(fetchedAt, forKey: "LastUpdateDate")
        defaults.set(["USD": Float32(2)], forKey: "CurrencyData")
        defaults.set("GBP", forKey: "CurrencyBase")
        defaults.set(456, forKey: "CurrencyDataTime")
        defaults.set(#"{"base":"JPY","date":"2025-01-02","rates":{"USD":999},"timestamp":999}"#, forKey: "CurrencyDataRaw")
        let converter = makeConverter(defaults: defaults, transport: CCS10Transport())

        XCTAssertTrue(converter.loadFromDefaults())
        XCTAssertEqual(converter.currencyRateEntity?.base, "GBP")
        XCTAssertEqual(converter.currencyRateEntity?.date, "2025-01-02")
        XCTAssertEqual(converter.currencyRateEntity?.rates["USD"], 2)
        XCTAssertEqual(converter.currencyRateEntity?.timestamp, 456)
    }

    func testMalformedRawDateFallsBackToLastUpdateDateWithPersistedBasePrecedence() {
        let defaults = CCS10Defaults()
        let fetchedAt = now.addingTimeInterval(-60)
        defaults.set(fetchedAt, forKey: "LastUpdateDate")
        defaults.set(["USD": Float32(2)], forKey: "CurrencyData")
        defaults.set("GBP", forKey: "CurrencyBase")
        defaults.set(456, forKey: "CurrencyDataTime")
        defaults.set(#"{"base":"JPY","date":"2026-02-30","rates":{"USD":999},"timestamp":999}"#, forKey: "CurrencyDataRaw")
        let converter = makeConverter(defaults: defaults, transport: CCS10Transport())

        XCTAssertTrue(converter.loadFromDefaults())
        XCTAssertEqual(converter.currencyRateEntity?.base, "GBP")
        XCTAssertEqual(converter.currencyRateEntity?.date, "1970-01-01")
    }

    func testLegacyDefaultsUseFetchDateAndEURWhenRawDateAndBaseAreMissing() {
        let defaults = CCS10Defaults()
        let fetchedAt = now.addingTimeInterval(-60)
        defaults.set(fetchedAt, forKey: "LastUpdateDate")
        defaults.set(["USD": Float32(2)], forKey: "CurrencyData")
        defaults.set(456, forKey: "CurrencyDataTime")
        defaults.set(#"{"base":"JPY","date":"","rates":{"USD":999},"timestamp":999}"#, forKey: "CurrencyDataRaw")
        let converter = makeConverter(defaults: defaults, transport: CCS10Transport())

        XCTAssertTrue(converter.loadFromDefaults())
        XCTAssertEqual(converter.currencyRateEntity?.base, "EUR")
        XCTAssertEqual(converter.currencyRateEntity?.date, "1970-01-01")
        XCTAssertEqual(converter.currencyRateEntity?.timestamp, 456)
    }

    func testClockMayReadStatusDuringSetterAndMemoryLoad() {
        let finished = expectation(description: "reentrant clock operations finish")
        var converter: CurrencyConverter!
        converter = CurrencyConverter(
            clock: {
                _ = converter.rateDataStatus
                return self.now
            },
            defaults: CCS10Defaults(),
            transport: CCS10Transport().send
        )

        DispatchQueue.global().async {
            converter.currencyRateEntity = CurrencyRateEntity(
                base: "EUR", date: "2026-07-18", rates: ["USD": 1], fetched_localtime: self.now, timestamp: 123
            )
            XCTAssertTrue(converter.loadFromMemory())
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
    }

    func testFirstConversionRefreshFailureFallsBackToLKGWithoutSecondRequest() {
        let transport = CCS10Transport()
        let converter = makeConverter(transport: transport)
        converter.currencyRateEntity = CurrencyRateEntity(
            base: "EUR", date: "2026-07-16", rates: ["USD": 1, "JPY": 110],
            fetched_localtime: now.addingTimeInterval(-2 * LegacyCachePolicy.lifetime), timestamp: 123
        )
        let conversion = expectation(description: "first conversion uses LKG")

        converter.convert(from: "JPY", to: "USD", unit: 110) { amount, error in
            XCTAssertNil(error)
            XCTAssertEqual(amount, 1, accuracy: 0.0001)
            conversion.fulfill()
        }
        guard transport.waitForRequest() else { return }
        guard transport.finish(error: URLError(.notConnectedToInternet)) else { return }
        wait(for: [conversion], timeout: 1)
        XCTAssertEqual(transport.requestCount, 1)

        let secondConversion = expectation(description: "second conversion reuses LKG")
        converter.convert(from: "JPY", to: "USD", unit: 220) { amount, error in
            XCTAssertNil(error)
            XCTAssertEqual(amount, 2, accuracy: 0.0001)
            secondConversion.fulfill()
        }
        wait(for: [secondConversion], timeout: 1)
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testGetSymbolsUsesLKGAfterRefreshFailure() {
        let transport = CCS10Transport()
        let converter = makeConverter(transport: transport)
        converter.currencyRateEntity = CurrencyRateEntity(
            base: "EUR", date: "2026-07-16", rates: ["USD": 1, "JPY": 110],
            fetched_localtime: now.addingTimeInterval(-2 * LegacyCachePolicy.lifetime), timestamp: 123
        )
        let symbols = expectation(description: "symbols use LKG")

        converter.getSymbols { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(Set(result ?? []), ["USD", "JPY"])
            symbols.fulfill()
        }
        guard transport.waitForRequest() else { return }
        guard transport.finish(error: URLError(.notConnectedToInternet)) else { return }
        wait(for: [symbols], timeout: 1)
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testInvalidStoredEntityDoesNotClassifyRefreshFailureAsMemory() {
        let transport = CCS10Transport()
        let converter = makeConverter(transport: transport)
        converter.currencyRateEntity = CurrencyRateEntity(
            base: "EUR", date: "2026-02-30", rates: ["USD": 1],
            fetched_localtime: now, timestamp: 123
        )
        let completion = expectation(description: "invalid stored entity failure")

        converter.loadData { error in
            XCTAssertEqual(error as? RateDataError, .transport)
            XCTAssertNil(converter.rateDataStatus.source)
            XCTAssertFalse(converter.rateDataStatus.isStale)
            XCTAssertNil(converter.rateDataStatus.lastUpdated)
            completion.fulfill()
        }
        guard transport.waitForRequest() else { return }
        guard transport.finish(error: URLError(.notConnectedToInternet)) else { return }
        wait(for: [completion], timeout: 1)
    }

    func testSynchronousSuccessfulTransportCompletesTypedLoad() {
        let converter = CurrencyConverter(
            clock: { self.now },
            defaults: CCS10Defaults(),
            transport: { _, completion in
                completion(
                    Data(#"{"base":"EUR","date":"2026-07-18","rates":{"USD":1.2},"timestamp":456}"#.utf8),
                    self.response,
                    nil
                )
            }
        )
        let loaded = expectation(description: "synchronous transport")

        converter.loadData { error in
            XCTAssertNil(error)
            XCTAssertEqual(converter.currencyRateEntity?.rates["USD"], 1.2)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 1)
    }

    func testDefaultsSnapshotCannotPublishOverCompetingWebCommit() {
        let defaults = CCS10SnapshotBarrierDefaults()
        defaults.set(now, forKey: "LastUpdateDate")
        defaults.set(["USD": Float32(2)], forKey: "CurrencyData")
        defaults.set(123, forKey: "CurrencyDataTime")
        let transportStarted = DispatchSemaphore(value: 0)
        let webPayload = Data(#"{"base":"EUR","date":"2026-07-18","rates":{"USD":3.0},"timestamp":999}"#.utf8)
        let converter = CurrencyConverter(
            clock: { self.now },
            defaults: defaults,
            transport: { _, completion in
                transportStarted.signal()
                completion(webPayload, self.response, nil)
            }
        )
        defaults.onSet = { _ = converter.rateDataStatus }
        let loadFinished = DispatchSemaphore(value: 0)
        let webFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            XCTAssertTrue(converter.loadFromDefaults())
            loadFinished.signal()
        }
        XCTAssertEqual(defaults.snapshotCaptured.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            converter.loadFromWeb { error in
                XCTAssertNil(error)
                webFinished.signal()
            }
        }
        XCTAssertEqual(transportStarted.wait(timeout: .now() + 1), .success)
        defaults.releaseSnapshot.signal()

        XCTAssertEqual(loadFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(webFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(converter.currencyRateEntity?.rates["USD"], 3)
        XCTAssertEqual(converter.rateDataStatus.source, .web)
    }

    func testPresentationInputDistinguishesStaleAndUnavailable() {
        XCTAssertEqual(
            RateDataStatus(source: .defaults, isStale: true, lastUpdated: nil, lastRefreshError: .decode).message,
            "Using saved rates; refresh failed."
        )
        XCTAssertEqual(
            RateDataStatus(source: nil, isStale: false, lastUpdated: nil, lastRefreshError: .unavailable).message,
            "Exchange rates unavailable."
        )
        let title = LegacyContextMenuPresentation.menuTitle(
            resultString: String(repeating: "x", count: 200),
            status: RateDataStatus(source: .defaults, isStale: true, lastUpdated: nil, lastRefreshError: .transport)
        )
        XCTAssertEqual(title.count, 120)
        XCTAssertTrue(title.hasSuffix("saved rates; refresh failed"))
    }

    func testConversionPresentationUsesCapturedStaleStatusAfterConverterMutation() {
        let transport = CCS10Transport()
        let converter = makeConverter(transport: transport)
        converter.currencyRateEntity = CurrencyRateEntity(
            base: "EUR", date: "2026-07-16", rates: ["USD": 1, "JPY": 110],
            fetched_localtime: now.addingTimeInterval(-2 * LegacyCachePolicy.lifetime), timestamp: 123
        )
        let failed = expectation(description: "refresh failure")
        converter.loadData { error in
            XCTAssertEqual(error as? RateDataError, .transport)
            failed.fulfill()
        }
        guard transport.waitForRequest() else { return }
        guard transport.finish(error: URLError(.notConnectedToInternet)) else { return }
        wait(for: [failed], timeout: 1)

        let converted = expectation(description: "conversion status snapshot")
        converter.convertWithStatus(from: "JPY", to: "USD", unit: 110) { result, status, error in
            XCTAssertNil(error)
            XCTAssertEqual(result, 1, accuracy: 0.0001)
            XCTAssertTrue(status.isStale)
            converter.currencyRateEntity = CurrencyRateEntity(
                base: "EUR", date: "2026-07-18", rates: ["USD": 2, "JPY": 110],
                fetched_localtime: self.now, timestamp: 456
            )
            let title = LegacyContextMenuPresentation.menuTitle(resultString: "1 USD", status: status)
            XCTAssertTrue(title.hasSuffix("saved rates; refresh failed"))
            converted.fulfill()
        }
        wait(for: [converted], timeout: 1)
    }

    private func makeConverter(defaults: CCS10Defaults = CCS10Defaults(), transport: CCS10Transport) -> CurrencyConverter {
        CurrencyConverter(clock: { self.now }, defaults: defaults, transport: transport.send)
    }
}
