import Foundation

struct ConvertHistoryUIBean: Identifiable {
    var id: UUID
    var title: String?
    var url: String
    var fromSymbol: String
    var toSymbol: String
    var fromAmount: Float

    var toAmount: Float {
        LegacyConvertHistoryCalculations.toAmount(fromAmount: fromAmount, ratio: ratio)
    }

    var fxFee: Float {
        LegacyConvertHistoryCalculations.fxFee(toAmount: toAmount, fxFeeRate: fxFeeRate)
    }

    var toAmountWithFx: Float {
        LegacyConvertHistoryCalculations.toAmountWithFx(toAmount: toAmount, fxFeeRate: fxFeeRate)
    }

    var fxFeeRate: Float
    var ratio: Float
    var isChecked = false
}

enum RenewPresentationOrchestration {
    static func beans(from values: [RenewHistoryValue]) -> [ConvertHistoryUIBean] {
        values.map { value in
            let normalized = LegacyConvertHistoryCalculations.normalizedHistoryValues(
                fromSymbol: value.fromSymbol, toSymbol: value.toSymbol,
                fxFeeRate: value.fxFee, ratio: value.ratio
            )
            return ConvertHistoryUIBean(
                id: RenewPresentationIdentity.id(businessID: value.id, objectIDURI: value.objectID),
                title: value.title ?? "", url: value.url ?? "",
                fromSymbol: value.fromSymbol ?? "", toSymbol: value.toSymbol ?? "",
                fromAmount: value.fromAmount, fxFeeRate: normalized.fxFeeRate,
                ratio: normalized.ratio
            )
        }
    }

    static func reload(
        from store: AtomicRenewStore,
        completion: @escaping (Result<[ConvertHistoryUIBean], Error>) -> Void
    ) {
        store.readHistory { values in
            switch values {
            case .success(let values):
                completion(.success(beans(from: values)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

extension ConvertHistoryUIBean {
    static func fromCoreData(c: ConvertHistoryRecord) -> ConvertHistoryUIBean {
        let values = LegacyConvertHistoryCalculations.normalizedHistoryValues(
            fromSymbol: c.fromSymbol, toSymbol: c.toSymbol, fxFeeRate: c.fxFee, ratio: c.ratio
        )
        let presentationID = c.objectIDURI.map {
            RenewPresentationIdentity.id(businessID: c.id, objectIDURI: $0)
        } ?? c.id ?? UUID()
        return ConvertHistoryUIBean(
            id: presentationID, title: c.title ?? "", url: c.url ?? "",
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
    var objectIDURI: String? { get }
}

extension ConvertHistoryRecord {
    var objectIDURI: String? { nil }
}
