//
//  ConvertHistoryDM.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/28.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation

//Can't use CoreData in Preview, so we need adapt it.

struct ConvertHistoryUIBean : Identifiable {
    var id: UUID
    var title: String?
    var url: String
    var fromSymbol: String
    var toSymbol: String
    var fromAmount: Float
    
    var toAmount : Float {
        get {
            return LegacyConvertHistoryCalculations.toAmount(fromAmount: fromAmount, ratio: ratio)
        }
    }
    
    var fxFee : Float {
        get {
            return LegacyConvertHistoryCalculations.fxFee(toAmount: toAmount, fxFeeRate: fxFeeRate)
        }
    }
    
    var toAmountWithFx : Float {
        get {
            return LegacyConvertHistoryCalculations.toAmountWithFx(toAmount: toAmount, fxFeeRate: fxFeeRate)
        }
    }
    
    var fxFeeRate: Float
    var ratio: Float
    var isChecked = false
    
    static func fromCoreData(c: ConvertHistoryRecord) -> ConvertHistoryUIBean{
        //due to some migration concern, entity still "fxFee" to represent "fxFeeRate"
        return make(
            id: c.id, title: c.title, url: c.url,
            fromSymbol: c.fromSymbol, toSymbol: c.toSymbol,
            fromAmount: c.fromAmount, fxFeeRate: c.fxFee, ratio: c.ratio
        )
    }

    private static func make(
        id: UUID?, title: String?, url: String?, fromSymbol: String?, toSymbol: String?,
        fromAmount: Float, fxFeeRate: Float, ratio: Float
    ) -> ConvertHistoryUIBean {
        let values = LegacyConvertHistoryCalculations.normalizedHistoryValues(
            fromSymbol: fromSymbol, toSymbol: toSymbol, fxFeeRate: fxFeeRate, ratio: ratio
        )
        return ConvertHistoryUIBean(
            id: id ?? UUID(), title: title ?? "", url: url ?? "",
            fromSymbol: fromSymbol ?? "", toSymbol: toSymbol ?? "", fromAmount: fromAmount,
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

extension ConvertHistory: ConvertHistoryRecord {}

class ConvertHistoryDMCollection : ObservableObject {
    @Published var data : [ConvertHistoryUIBean] = []
    let dataManager = CHDataManager.shared
    
    @objc func reload() {
        self.data = []
        guard let cdList = dataManager.readFromCore() else {
            return
        }
        for entry in cdList {
            self.data.append(ConvertHistoryUIBean.fromCoreData(c: entry))
        }
    }
    func wipe() {
        dataManager.wipeAll()
        self.data = []
    }
    
    func wipeChecked() {
        data.enumerated()
            .filter { $0.element.isChecked }
            .forEach {
                dataManager.wipeById($0.element.id)
            }
        data = data.enumerated()
            .filter { $0.element.isChecked == false }
            .map { $0.element }
        
    }
    
    func renewFx() {
        dataManager.readFromCore()?.forEach({ (entity) in
            CurrencyConverter.shared.convert(from: entity.fromSymbol!, to: entity.toSymbol!, unit: entity.fromAmount) { (result, error) in
                entity.ratio = result / entity.fromAmount
            }
        })
        try! sharedPersistentContainer.viewContext.save()
        self.reload()
    }

}
