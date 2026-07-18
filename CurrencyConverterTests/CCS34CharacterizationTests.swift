import XCTest
@testable import CurrencyConverter

final class CCS34ConversionCharacterizationTests: XCTestCase {
    func testFixedRateDirectConversionUsesBaseRateMath() {
        let result = LegacyConversionMath.direct(unit: 2, fromRate: 4, toRate: 1)
        XCTAssertEqual(result, 0.5, accuracy: 0.0001)
    }

    func testConverterConvertsWithValidRatesWithoutNetwork() {
        let now = Date(timeIntervalSince1970: 1000)
        let exchange: [String: Float32] = ["USD": 1, "JPY": 110]
        let suiteName = "CCS34-conversion-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let seededRates = CurrencyRateEntity(
            base: "EUR",
            date: "2026-07-18",
            rates: exchange,
            fetched_localtime: now,
            timestamp: 0
        )
        let expectedRate = LegacyConversionMath.direct(unit: 110, fromRate: 110, toRate: 1)
        var transportCalled = false
        let converterWithoutNetwork = CurrencyConverter(
            clock: { now },
            defaults: defaults,
            transport: { _, _ in
                transportCalled = true
                XCTFail("Conversion should not trigger network transport when in-memory rates are valid")
            }
        )
        converterWithoutNetwork.currencyRateEntity = seededRates

        let expectation = expectation(description: "conversion")
        converterWithoutNetwork.convert(from: "JPY", to: "USD", unit: 110) { amount, error in
            XCTAssertEqual(amount, expectedRate, accuracy: 0.0001)
            XCTAssertNil(error)
            XCTAssertFalse(transportCalled)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
}

final class CCS34CacheCharacterizationTests: XCTestCase {
    func testCacheIsFreshBeforeTwentyFourHoursAndExpiredAtBoundary() {
        let saved = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(LegacyCachePolicy.isFresh(lastUpdated: saved, now: saved.addingTimeInterval(86_399)))
        XCTAssertFalse(LegacyCachePolicy.isFresh(lastUpdated: saved, now: saved.addingTimeInterval(86_400)))
        XCTAssertFalse(LegacyCachePolicy.isFresh(lastUpdated: nil, now: saved))
    }

    func testConverterLoadsFreshFixtureAndRejectsExpiredFixture() {
        let saved = Date(timeIntervalSince1970: 10_000)
        let suiteName = "CCS34-cache-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(saved, forKey: "LastUpdateDate")
        defaults.set(["USD": Float32(1.2)], forKey: "CurrencyData")
        defaults.set(123, forKey: "CurrencyDataTime")

        let fresh = CurrencyConverter(clock: { saved.addingTimeInterval(86_399) }, defaults: defaults)
        XCTAssertTrue(fresh.loadFromDefaults())
        XCTAssertEqual(fresh.currencyRateEntity?.rates["USD"], 1.2)

        let expired = CurrencyConverter(clock: { saved.addingTimeInterval(86_400) }, defaults: defaults)
        XCTAssertFalse(expired.loadFromDefaults())
    }
}

final class CCS34PersistenceCharacterizationTests: XCTestCase {
    func testContextMenuFeeIndexUsesLegacySelection() {
        XCTAssertEqual(LegacyContextMenuFXFeePolicy.rate(for: 0), 0)
        XCTAssertEqual(LegacyContextMenuFXFeePolicy.rate(for: 1), 0.015)
        XCTAssertEqual(LegacyContextMenuFXFeePolicy.rate(for: 2), 0.02)
        XCTAssertEqual(LegacyContextMenuFXFeePolicy.rate(for: 99), 0)
    }

    func testLastResultRoundTripsThroughIsolatedDefaultsData() throws {
        let result = LastResult(resultString: "2.03 USD", convertFrom: "TWD", convertTo: "USD", units: 8, fxRate: 0.015, ratio: 0.25)
        let suiteName = "CCS34-last-result-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try LastResultPersistence.encode(result), forKey: "lastResult")

        let data = try XCTUnwrap(defaults.data(forKey: "lastResult"))
        XCTAssertEqual(try LastResultPersistence.decode(data), result)
    }
}

final class CCS34HistoryCharacterizationTests: XCTestCase {
    func testConvertHistoryUIBeanCalculatesAmountAndFeeInclusively() {
        let toAmount = LegacyConvertHistoryCalculations.toAmount(fromAmount: 200, ratio: 0.25)
        XCTAssertEqual(toAmount, 50, accuracy: 0.0001)
        XCTAssertEqual(LegacyConvertHistoryCalculations.fxFee(toAmount: toAmount, fxFeeRate: 0.015), 0.75, accuracy: 0.0001)
        XCTAssertEqual(LegacyConvertHistoryCalculations.toAmountWithFx(toAmount: toAmount, fxFeeRate: 0.015), 50.75, accuracy: 0.0001)
    }
}

final class CCS34CreditCardCharacterizationTests: XCTestCase {
    func testCashbackUsesDomesticAndCrossCurrencyRates() {
        var card = CashBackCreditCardProfile()
        card.currencySymbol = "TWD"
        card.fxRate = 1.5
        card.cashBackRateDomestic = 0.02
        card.cashBackRateInternational = 0.01
        XCTAssertEqual(card.estimatedPrice(price: 100, sourceSymbol: "TWD"), 98, accuracy: 0.0001)
        XCTAssertEqual(card.estimatedPrice(price: 100, sourceSymbol: "USD"), 100.5, accuracy: 0.0001)
        XCTAssertEqual(card.estimateRewardAmount(price: 100, sourceSymbol: "TWD"), 2, accuracy: 0.0001)
        // CCS-26: this intentionally keeps the legacy numeric-unit behavior for cross-currency rewards.
        XCTAssertEqual(card.estimateRewardAmount(price: 100, sourceSymbol: "USD"), 1, accuracy: 0.0001)
    }

    func testMileageUsesDomesticAndCrossCurrencyRates() {
        var card = MileageCreditCardProfile()
        card.currencySymbol = "TWD"
        card.fxRate = 1.5
        card.mileageRatioDomestic = 0.01
        card.mileageRatioInternational = 0.02
        card.mileageEstimatedValue = 0.5
        XCTAssertEqual(card.estimatedPrice(price: 100, sourceSymbol: "TWD"), 99.5, accuracy: 0.0001)
        XCTAssertEqual(card.estimatedPrice(price: 100, sourceSymbol: "USD"), 100.5, accuracy: 0.0001)
        XCTAssertEqual(card.estimateRewardAmount(price: 100, sourceSymbol: "TWD"), 1, accuracy: 0.0001)
        // CCS-26: the cross-currency reward remains a raw source-unit multiplication until its owner fixes it.
        XCTAssertEqual(card.estimateRewardAmount(price: 100, sourceSymbol: "USD"), 2, accuracy: 0.0001)
    }
}
