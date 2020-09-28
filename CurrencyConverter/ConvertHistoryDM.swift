//
//  ConvertHistoryDM.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/28.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation

//Can't use CoreData in Preview, so we need adapt it.

struct ConvertHistoryDM {
    var title: String
    var url: String
    var fromSymbol: String
    var toSymbol: String
    var fromAmount: Float
    var fxFee: Float
    var ratio: Float
    
    static func fromCoreData(c: ConvertHistory) -> ConvertHistoryDM{
        return ConvertHistoryDM(title: c.title ?? "", url: c.url ?? "", fromSymbol: c.fromSymbol ?? "", toSymbol: c.toSymbol ?? "", fromAmount: c.fxFee, fxFee: c.fxFee, ratio: c.ratio)
    }
    
}
