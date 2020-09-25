//
//  CCDataModel.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/25.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation

class CCDataModel : Identifiable {
    var uid : UUID = UUID.init()
    var url : String
    var sourceSymbol : String
    var destSymbol : String
    var ratio: Float32
    var fxRate : Float32
    var sourceAmount : Float32
    var destAmount : Float32
    init(url: String, sourceSymbol: String, destSymbol: String, ratio: Float32, fxRate: Float32, sourceAmount: Float32, destAmount: Float32) {
        self.url = url
        self.sourceSymbol = sourceSymbol
        self.destSymbol = destSymbol
        self.ratio = ratio
        self.fxRate = fxRate
        self.sourceAmount = sourceAmount
        self.destAmount = destAmount
    }
}
