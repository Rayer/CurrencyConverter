import Foundation

struct EntityDetailRowPresentationInput {
    let sourceAmount: Float
    let sourceSymbol: String
    let destinationAmount: Float
    let destinationAmountWithFee: Float
    let ratio: Float
    let cardInputAmount: Float

    init(bean: ConvertHistoryUIBean) {
        sourceAmount = bean.fromAmount
        sourceSymbol = bean.fromSymbol
        destinationAmount = bean.toAmount
        destinationAmountWithFee = bean.toAmountWithFx
        ratio = bean.ratio
        cardInputAmount = bean.toAmount
    }
}
