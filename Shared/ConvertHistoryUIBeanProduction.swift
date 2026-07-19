import Foundation

extension ConvertHistoryUIBean {
    static func fromCoreData(c: ConvertHistoryRecord) -> ConvertHistoryUIBean {
        let values = LegacyConvertHistoryCalculations.normalizedHistoryValues(
            fromSymbol: c.fromSymbol, toSymbol: c.toSymbol, fxFeeRate: c.fxFee, ratio: c.ratio
        )
        return ConvertHistoryUIBean(
            id: c.id ?? UUID(), title: c.title ?? "", url: c.url ?? "",
            fromSymbol: c.fromSymbol ?? "", toSymbol: c.toSymbol ?? "", fromAmount: c.fromAmount,
            fxFeeRate: values.fxFeeRate, ratio: values.ratio
        )
    }
}

protocol ConvertHistoryRecord {
    var id: UUID? { get }
    var title: String? { get }
    var url: String? { get }
    var fromSymbol: String? { get }
    var toSymbol: String? { get }
    var fromAmount: Float { get }
    var fxFee: Float { get }
    var ratio: Float { get }
}
