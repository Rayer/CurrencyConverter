import Foundation

enum RateDataSource: Equatable {
    case memory
    case defaults
    case web
}

enum RateDataError: Error, Equatable {
    case transport
    case httpStatus(Int)
    case decode
    case invalidPayload
    case missingRate(String)
    case unavailable

    var message: String {
        switch self {
        case .transport:
            return "Could not refresh exchange rates."
        case .httpStatus(let status):
            return "Rate service returned an HTTP \(status / 100)xx response."
        case .decode:
            return "Rate service returned unreadable data."
        case .invalidPayload:
            return "Rate service returned invalid data."
        case .missingRate:
            return "Requested currency rate unavailable."
        case .unavailable:
            return "Exchange rates unavailable."
        }
    }
}

struct RateDataStatus: Equatable {
    let source: RateDataSource?
    let isStale: Bool
    let lastUpdated: Date?
    let lastRefreshError: RateDataError?

    var message: String {
        guard source != nil else {
            return lastRefreshError?.message ?? RateDataError.unavailable.message
        }
        if isStale {
            return lastRefreshError == nil
                ? "Using saved rates; refresh pending."
                : "Using saved rates; refresh failed."
        }
        return lastRefreshError?.message ?? "Exchange rates are current."
    }
}

enum LegacyConversionMath {
    static func direct(unit: Float32, fromRate: Float32, toRate: Float32) -> Float32 {
        (unit / fromRate) * toRate
    }
}

enum LegacyCachePolicy {
    static let lifetime: TimeInterval = 24.0 * 60.0 * 60.0

    static func isFresh(lastUpdated: Date?, now: Date) -> Bool {
        guard let lastUpdated else { return false }
        return lastUpdated.addingTimeInterval(lifetime) > now
    }
}

enum LegacyContextMenuFXFeePolicy {
    static func rate(for index: Int) -> Float32 {
        switch index {
        case 1: return 0.015
        case 2: return 0.02
        default: return 0.0
        }
    }
}

struct LegacyContextMenuCalculation: Equatable {
    let finalAmount: Float32
    let appliedFXFee: Float32
    let ratio: Float32

    static func calculate(
        rawResult: Float32,
        unit: Float32,
        sourceCurrency: String,
        targetCurrency: String,
        feeIndex: Int
    ) -> LegacyContextMenuCalculation {
        let sameCurrency = sourceCurrency == targetCurrency
        let appliedFXFee = sameCurrency ? 0 : LegacyContextMenuFXFeePolicy.rate(for: feeIndex)
        return LegacyContextMenuCalculation(
            finalAmount: sameCurrency ? unit : rawResult * (1 + appliedFXFee),
            appliedFXFee: appliedFXFee,
            ratio: sameCurrency ? 1 : rawResult / unit
        )
    }
}

enum LegacyConvertHistoryCalculations {
    struct HistoryValues: Equatable {
        let fxFeeRate: Float
        let ratio: Float
    }

    static func normalizedHistoryValues(
        fromSymbol: String?,
        toSymbol: String?,
        fxFeeRate: Float,
        ratio: Float
    ) -> HistoryValues {
        guard let fromSymbol, let toSymbol,
              !fromSymbol.isEmpty, !toSymbol.isEmpty,
              fromSymbol == toSymbol else {
            return HistoryValues(fxFeeRate: fxFeeRate, ratio: ratio)
        }
        return HistoryValues(fxFeeRate: 0, ratio: 1)
    }

    static func toAmount(fromAmount: Float, ratio: Float) -> Float { fromAmount * ratio }
    static func fxFee(toAmount: Float, fxFeeRate: Float) -> Float { toAmount * fxFeeRate }
    static func toAmountWithFx(toAmount: Float, fxFeeRate: Float) -> Float {
        toAmount + fxFee(toAmount: toAmount, fxFeeRate: fxFeeRate)
    }
}

struct LastResult: Codable, Equatable {
    var resultString: String
    var convertFrom: String
    var convertTo: String
    var units: Float
    var fxRate: Float
    var ratio: Float
}

enum LegacyContextMenuPresentation {
    private static let titleLimit = 120
    private static let staleWarning = " — saved rates; refresh failed"

    static func menuTitle(resultString: String, status: RateDataStatus) -> String {
        let warning = status.isStale && status.lastRefreshError != nil ? staleWarning : ""
        let resultLimit = max(0, titleLimit - warning.count)
        return String(resultString.prefix(resultLimit)) + warning
    }
}

enum LastResultPersistence {
    static func encode(_ value: LastResult) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func decode(_ data: Data) throws -> LastResult {
        try JSONDecoder().decode(LastResult.self, from: data)
    }
}
