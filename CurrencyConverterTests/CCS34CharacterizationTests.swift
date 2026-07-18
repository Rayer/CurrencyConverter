import XCTest
@testable import CurrencyConverter

private final class TestConvertHistoryRecord: ConvertHistoryRecord {
    var id: UUID?
    var title: String?
    var url: String?
    var fromSymbol: String?
    var toSymbol: String?
    var fromAmount: Float
    var fxFee: Float
    var ratio: Float
    
    init(
        id: UUID? = UUID(),
        title: String? = "",
        url: String? = nil,
        fromSymbol: String?,
        toSymbol: String?,
        fromAmount: Float = 0,
        fxFee: Float = 0,
        ratio: Float = 1
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.fromSymbol = fromSymbol
        self.toSymbol = toSymbol
        self.fromAmount = fromAmount
        self.fxFee = fxFee
        self.ratio = ratio
    }
}

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

    func testSameCurrencyContextMenuIgnoresSelectedFXFee() {
        let sameCurrencyCases: [(feeIndex: Int, rawResult: Float32)] = [
            (0, 10),
            (1, 21),
            (2, 33)
        ]

        for testCase in sameCurrencyCases {
            let calculation = LegacyContextMenuCalculation.calculate(
                rawResult: testCase.rawResult,
                unit: 100,
                sourceCurrency: "USD",
                targetCurrency: "USD",
                feeIndex: testCase.feeIndex
            )

            XCTAssertEqual(calculation.finalAmount, 100, accuracy: 0.0001)
            XCTAssertEqual(calculation.appliedFXFee, 0, accuracy: 0.0001)
            XCTAssertEqual(calculation.ratio, 1, accuracy: 0.0001)
        }
    }

    func testCrossCurrencyContextMenuPreservesSelectedFXFee() {
        let crossCurrencyCases: [(feeIndex: Int, appliedFXFee: Float32, expectedFinalAmount: Float32)] = [
            (0, 0, 50),
            (1, 0.015, 50.75),
            (2, 0.02, 51)
        ]

        for testCase in crossCurrencyCases {
            let calculation = LegacyContextMenuCalculation.calculate(
                rawResult: 50,
                unit: 100,
                sourceCurrency: "USD",
                targetCurrency: "TWD",
                feeIndex: testCase.feeIndex
            )

            XCTAssertEqual(calculation.finalAmount, testCase.expectedFinalAmount, accuracy: 0.0001)
            XCTAssertEqual(calculation.appliedFXFee, testCase.appliedFXFee, accuracy: 0.0001)
            XCTAssertEqual(calculation.ratio, 0.5, accuracy: 0.0001)
        }
    }

    func testCrossCurrencyContextMenuRatioDivisionBehaviorWithZeroUnits() {
        let nonZeroRawResultForZeroUnit = [
            LegacyContextMenuCalculation.calculate(
                rawResult: 7,
                unit: 0,
                sourceCurrency: "USD",
                targetCurrency: "TWD",
                feeIndex: 1
            ),
            LegacyContextMenuCalculation.calculate(
                rawResult: 0,
                unit: 0,
                sourceCurrency: "USD",
                targetCurrency: "TWD",
                feeIndex: 2
            )
        ]

        XCTAssertTrue(nonZeroRawResultForZeroUnit[0].ratio.isInfinite)
        XCTAssertEqual(nonZeroRawResultForZeroUnit[0].finalAmount, 7.105, accuracy: 0.0001)
        XCTAssertEqual(nonZeroRawResultForZeroUnit[0].appliedFXFee, 0.015, accuracy: 0.0001)

        XCTAssertTrue(nonZeroRawResultForZeroUnit[1].ratio.isNaN)
        XCTAssertEqual(nonZeroRawResultForZeroUnit[1].finalAmount, 0, accuracy: 0.0001)
        XCTAssertEqual(nonZeroRawResultForZeroUnit[1].appliedFXFee, 0.02, accuracy: 0.0001)
    }

    func testSameCurrencyLastResultRoundTripsCalculationValues() throws {
        let calculation = LegacyContextMenuCalculation.calculate(
            rawResult: 100,
            unit: 100,
            sourceCurrency: "USD",
            targetCurrency: "USD",
            feeIndex: 2
        )
        let result = LastResult(
            resultString: "100.00 USD",
            convertFrom: "USD",
            convertTo: "USD",
            units: 100,
            fxRate: calculation.appliedFXFee,
            ratio: calculation.ratio
        )

        XCTAssertEqual(try LastResultPersistence.decode(LastResultPersistence.encode(result)), result)
        XCTAssertEqual(result.fxRate, 0, accuracy: 0.0001)
        XCTAssertEqual(result.ratio, 1, accuracy: 0.0001)
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
    func testSameCurrencyHistoryValuesAreNormalizedForNewWrites() {
        let values = LegacyConvertHistoryCalculations.normalizedHistoryValues(
            fromSymbol: "USD", toSymbol: "USD", fxFeeRate: 0.02, ratio: 0.5
        )

        XCTAssertEqual(values.fxFeeRate, 0, accuracy: 0.0001)
        XCTAssertEqual(values.ratio, 1, accuracy: 0.0001)
    }

    func testLegacySameCurrencyHistoryRecordIsNormalizedByUIBean() {
        let source = TestConvertHistoryRecord(
            fromSymbol: "USD",
            toSymbol: "USD",
            fromAmount: 200,
            fxFee: 0.02,
            ratio: 0.5
        )
        let sourceId = source.id
        let sourceTitle = source.title
        let sourceUrl = source.url
        let bean = ConvertHistoryUIBean.fromCoreData(c: source)

        XCTAssertEqual(bean.fxFeeRate, 0, accuracy: 0.0001)
        XCTAssertEqual(bean.ratio, 1, accuracy: 0.0001)
        XCTAssertEqual(bean.toAmount, bean.fromAmount, accuracy: 0.0001)
        XCTAssertEqual(bean.toAmountWithFx, bean.fromAmount, accuracy: 0.0001)
        XCTAssertEqual(source.id, sourceId)
        XCTAssertEqual(source.title, sourceTitle)
        XCTAssertEqual(source.url, sourceUrl)
        XCTAssertEqual(source.fromSymbol, "USD")
        XCTAssertEqual(source.toSymbol, "USD")
        XCTAssertEqual(source.fromAmount, 200, accuracy: 0.0001)
        XCTAssertEqual(source.fxFee, 0.02, accuracy: 0.0001)
        XCTAssertEqual(source.ratio, 0.5, accuracy: 0.0001)
    }

    func testLegacyOptionalAndUnknownSymbolShapesFollowSameCurrencyContract() {
        let cases: [(from: String?, to: String?, name: String)] = [
            (nil, nil, "nil-nil"),
            (nil, "", "nil-empty"),
            ("", "", "empty-empty"),
            ("US", "US", "short-equal"),
            ("USD ", "USD ", "whitespace-equal"),
            ("usd", "usd", "lowercase-equal"),
            ("???", "???", "punctuation-equal"),
            ("US", "TWD", "short-cross")
        ]

        for testCase in cases {
            let values = LegacyConvertHistoryCalculations.normalizedHistoryValues(
                fromSymbol: testCase.from, toSymbol: testCase.to, fxFeeRate: 0.02, ratio: 0.5
            )
            let shouldNormalize = testCase.from?.isEmpty == false && testCase.to?.isEmpty == false && testCase.from == testCase.to
            XCTAssertEqual(values.fxFeeRate, shouldNormalize ? 0 : 0.02, accuracy: 0.0001, testCase.name)
            XCTAssertEqual(values.ratio, shouldNormalize ? 1 : 0.5, accuracy: 0.0001, testCase.name)

            let row = TestConvertHistoryRecord(
                fromSymbol: testCase.from,
                toSymbol: testCase.to,
                fromAmount: 0.5,
                fxFee: 0.02,
                ratio: 0.5
            )
            let bean = ConvertHistoryUIBean.fromCoreData(c: row)

            XCTAssertEqual(row.fromSymbol, testCase.from, testCase.name)
            XCTAssertEqual(row.toSymbol, testCase.to, testCase.name)
            XCTAssertEqual(row.fxFee, 0.02, accuracy: 0.0001, testCase.name)
            XCTAssertEqual(row.ratio, 0.5, accuracy: 0.0001, testCase.name)
            XCTAssertEqual(row.fromAmount, 0.5, accuracy: 0.0001, testCase.name)
            XCTAssertEqual(bean.fxFeeRate, shouldNormalize ? 0 : 0.02, accuracy: 0.0001, testCase.name)
            XCTAssertEqual(bean.ratio, shouldNormalize ? 1 : 0.5, accuracy: 0.0001, testCase.name)
        }
    }

    func testEntityDetailRowPresentationUsesNormalizedProductionBeanAndBestPriceInputs() throws {
        let bean = ConvertHistoryUIBean(
            id: UUID(), title: "Product", url: "https://example.com", fromSymbol: "USD", toSymbol: "TWD",
            fromAmount: 200, fxFeeRate: 0.02, ratio: 31.3
        )
        var domestic = CashBackCreditCardProfile()
        domestic.name = "Domestic"
        domestic.currencySymbol = "TWD"
        domestic.fxRate = 1.5
        domestic.cashBackRateDomestic = 0.02
        domestic.cashBackRateInternational = 0.01
        var international = CashBackCreditCardProfile()
        international.name = "International"
        international.currencySymbol = "USD"
        international.fxRate = 0.5
        international.cashBackRateDomestic = 0.01
        international.cashBackRateInternational = 0.03

        let presentation = EntityDetailRowPresentationInput(bean: bean)
        XCTAssertEqual(presentation.sourceAmount, bean.fromAmount, accuracy: 0.0001)
        XCTAssertEqual(presentation.sourceSymbol, bean.fromSymbol)
        XCTAssertEqual(presentation.destinationAmount, bean.toAmount, accuracy: 0.0001)
        XCTAssertEqual(presentation.destinationAmountWithFee, bean.toAmountWithFx, accuracy: 0.0001)
        XCTAssertEqual(presentation.ratio, bean.ratio, accuracy: 0.0001)
        XCTAssertEqual(presentation.cardInputAmount, bean.toAmount, accuracy: 0.0001)
        let profiles: [CreditCardProfile] = [domestic, international]
        let estimatedPrices = profiles.map {
            $0.estimatedPrice(price: presentation.cardInputAmount, sourceSymbol: presentation.sourceSymbol)
        }
        XCTAssertEqual(estimatedPrices, profiles.map {
            $0.estimatedPrice(price: bean.toAmount, sourceSymbol: bean.fromSymbol)
        })
        let bestPrice = min(
            estimatedPrices[0], estimatedPrices[1]
        )
        XCTAssertEqual(bestPrice, estimatedPrices.min()!, accuracy: 0.0001)
    }

    func testCrossCurrencyHistoryValuesRemainUnchanged() {
        let values = LegacyConvertHistoryCalculations.normalizedHistoryValues(
            fromSymbol: "USD", toSymbol: "TWD", fxFeeRate: 0.015, ratio: 0.5
        )

        XCTAssertEqual(values.fxFeeRate, 0.015, accuracy: 0.0001)
        XCTAssertEqual(values.ratio, 0.5, accuracy: 0.0001)
    }

    func testSameCurrencyZeroAmountHistoryRemainsSafe() {
        let bean = ConvertHistoryUIBean(
            id: UUID(), title: nil, url: "", fromSymbol: "USD", toSymbol: "USD",
            fromAmount: 0, fxFeeRate: 0, ratio: 1
        )

        XCTAssertEqual(bean.toAmount, 0, accuracy: 0.0001)
        XCTAssertEqual(bean.fxFee, 0, accuracy: 0.0001)
        XCTAssertEqual(bean.toAmountWithFx, 0, accuracy: 0.0001)
    }

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
