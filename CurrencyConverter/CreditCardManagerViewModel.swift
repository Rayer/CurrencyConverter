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
    @Published var FxRateValidate = true
    @Published var cbDomesticRate = ""
    @Published var cbDomesticRateValidate = true
    @Published var cbInternationalRate = ""
    @Published var cbInternationalRateValidate = true
    @Published var mDomesticRate = ""
    @Published var mDomesticRateValidate = true
    @Published var mInternationalRate = ""
    @Published var mInternationalRateValidate = true
    @Published var mEstimatedValuePerMile = ""
    @Published var mEstimatedValuePerMileValid = true
    private var cancellableSet: Set<AnyCancellable> = []
    
    
    init() {
        let c = CurrencyConverter.shared
        c.getSymbols { (symbols, error) in
            self.clearinghouseCurrencyList = symbols?.sorted() ?? [""]
        }
        
        self.$FxRate
            .receive(on: RunLoop.main)
            .map(self.isPercentNumber(input:))
            .assign(to: \.FxRateValidate, on: self)
            .store(in: &cancellableSet)
        
        self.$cbDomesticRate
            .receive(on: RunLoop.main)
            .map(self.isNumber(input:))
            .assign(to: \.cbDomesticRateValidate, on: self)
            .store(in: &cancellableSet)
        
        self.$cbInternationalRate
            .receive(on: RunLoop.main)
            .map(self.isNumber(input:))
            .assign(to: \.cbInternationalRateValidate, on: self)
            .store(in: &cancellableSet)
        
        self.$mDomesticRate
            .receive(on: RunLoop.main)
            .map(self.isNumber(input:))
            .assign(to: \.mDomesticRateValidate, on: self)
            .store(in: &cancellableSet)
        
        self.$mInternationalRate
            .receive(on: RunLoop.main)
            .map(self.isNumber(input:))
            .assign(to: \.mInternationalRateValidate, on: self)
            .store(in: &cancellableSet)
        
        self.$mEstimatedValuePerMile
            .receive(on: RunLoop.main)
            .map(self.isNumber(input:))
            .assign(to: \.mEstimatedValuePerMileValid, on: self)
            .store(in: &cancellableSet)
    }
    
    func isNumber(input: String) -> Bool {
        guard Float(input) != nil else {
            return false
        }
        return true
    }
    
    func isPercentNumber(input: String) -> Bool {
        guard let r = Float(self.FxRate) else {
            return false
        }
        
        guard r <= 100 && r >= 0 else {
            return false
        }
        
        return true
    }
    
}
