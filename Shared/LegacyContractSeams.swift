import Foundation

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

enum LegacyConvertHistoryCalculations {
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

enum LastResultPersistence {
    static func encode(_ value: LastResult) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func decode(_ data: Data) throws -> LastResult {
        try JSONDecoder().decode(LastResult.self, from: data)
    }
}
