//
//  CreditCardManagerViewModel.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/20.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation
import Combine

class CreditCardManagerViewModel : ObservableObject {
    @Published var creditCardName = ""
    @Published var clearinghouseCurrency = "TWD"
    var clearinghouseCurrencyList: [String] = []
    @Published var FxRate = "1.5"
    @Published var cbDomensticRate = ""
    @Published var cbInternationalRate = ""
    @Published var mDomensticRate = ""
    @Published var mInternationalRate = ""
    @Published var mEstimatedValuePerMile = ""
    
    
    init() {
        let c = CurrencyConverter.shared
        c.getSymbols { (symbols, error) in
            self.clearinghouseCurrencyList = symbols?.sorted() ?? [""]
        }
    }
    
}
