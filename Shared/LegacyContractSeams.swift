import Foundation

enum CurrencyInfoFeedConfigurationError: Error, Equatable {
    case missing
    case malformed
    case nonHTTPS
    case userinfo
    case query
    case fragment
}

struct CurrencyInfoFeedEndpoint: Equatable {
    let url: URL

    fileprivate init(url: URL) {
        self.url = url
    }
}

enum CurrencyInfoFeedConfiguration {
    typealias Resolution = Result<CurrencyInfoFeedEndpoint, CurrencyInfoFeedConfigurationError>
    static let infoDictionaryKey = "CurrencyInfoFeed"

    static func resolve(value: Any?) -> Resolution {
        guard let value = value as? String else {
            return .failure(value == nil ? .missing : .malformed)
        }
        guard !value.isEmpty else { return .failure(.missing) }
        guard let url = URL(string: value) else { return .failure(.malformed) }
        if let error = validate(url: url, rawValue: value) {
            return .failure(error)
        }
        return .success(CurrencyInfoFeedEndpoint(url: url))
    }

    static func resolve(bundle: Bundle) -> Resolution {
        resolve(value: bundle.object(forInfoDictionaryKey: infoDictionaryKey))
    }

    private static func validate(url: URL, rawValue: String) -> CurrencyInfoFeedConfigurationError? {
        guard !rawValue.isEmpty,
              rawValue == rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .malformed
        }
        guard let decoded = rawValue.removingPercentEncoding else {
            return .malformed
        }
        if decoded.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return .malformed
        }

        guard components.scheme?.lowercased() == "https" else {
            if let scheme = components.scheme, scheme.lowercased() != "https" {
                return .nonHTTPS
            }
            return .malformed
        }
        guard let host = components.host, !host.isEmpty else { return .malformed }
        if let port = components.port, !(1...65535).contains(port) {
            return .malformed
        }
        if components.user != nil || components.password != nil || authority(in: rawValue).contains("@") {
            return .userinfo
        }
        if rawValue.contains("?") || components.query != nil {
            return .query
        }
        if rawValue.contains("#") || components.fragment != nil {
            return .fragment
        }
        return nil
    }

    private static func authority(in value: String) -> String {
        guard let separator = value.range(of: "://") else { return "" }
        let authorityStart = separator.upperBound
        let remainder = value[authorityStart...]
        return String(remainder.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
    }
}

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
    case invalidConfiguration
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
        case .invalidConfiguration:
            return "Rate feed configuration is invalid."
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
