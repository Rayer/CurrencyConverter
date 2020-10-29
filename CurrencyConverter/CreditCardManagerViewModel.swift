//
//  CreditCardManagerViewModel.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/20.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation
import Combine

enum CreditCardType {
    case CashBack, Mileage
}

class CreditCardManagerViewModel : ObservableObject {
    @Published var creditCardType = CreditCardType.CashBack
    @Published var creditCardName = ""
    @Published var isUpdateCard = false
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
    @Published var savedProfile : [CreditCardProfileEntity] = []
    @Published var savedProfileOrder = -1
    private var cancellableSet: Set<AnyCancellable> = []
    
    
    init() {
        let c = CurrencyConverter.shared
        c.getSymbols { (symbols, error) in
            self.clearinghouseCurrencyList = symbols?.sorted() ?? [""]
        }
        
        self.savedProfile = FetchAllCreditCardProfileEntities()

        self.$creditCardName
            .receive(on: RunLoop.main)
            .map { (input: String) -> Bool in
                IsCardExist(name: input)
            }
            .assign(to: \.isUpdateCard, on: self)
            .store(in: &cancellableSet)
        
        self.$creditCardName
            .receive(on: RunLoop.main)
            .map { (input: String) -> Int in
                if let index = self.savedProfile.firstIndex(where: { $0.name == input }) {
                    return index
                }
                return -1
            }
            .assign(to: \.savedProfileOrder, on: self)
            .store(in: &cancellableSet)

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
    
    func persist() {
        
        if IsCardExist(name: self.creditCardName) {
            deleteByCardName(self.creditCardName)
        }
        
        switch self.creditCardType {
            case .CashBack:
                //Validate cashback
                if FxRateValidate && cbDomesticRateValidate && cbInternationalRateValidate {
                    let c = CashBackCreditCardProfile()
                    c.name = self.creditCardName
                    c.currencySymbol = self.clearinghouseCurrency
                    c.fxRate = Float(self.FxRate)!
                    c.cashBackRateDomestic = Float(cbDomesticRate)!
                    c.cashBackRateInternational = Float(cbInternationalRate)!
                    SaveCreditCardProfile(profile: c)
                }
            case .Mileage:
                //Validate mileage
                if FxRateValidate && mDomesticRateValidate && mInternationalRateValidate && mEstimatedValuePerMileValid {
                    let m = MileageCreditCardProfile()
                    m.name = self.creditCardName
                    m.currencySymbol = self.clearinghouseCurrency
                    m.fxRate = Float(self.FxRate)!
                    m.mileageRatioDomestic = Float(self.mDomesticRate)!
                    m.mileageRatioInternational = Float(self.mInternationalRate)!
                    m.mileageEstimatedValue = Float(self.mEstimatedValuePerMile)!
                    SaveCreditCardProfile(profile: m)
                }
        }
        self.savedProfile = FetchAllCreditCardProfileEntities()
    }
    
    func deleteByCardName(_ cardname: String) {
        DeleteCreditCard(name: cardname)
        self.savedProfile = FetchAllCreditCardProfileEntities()
    }

    func loadProfile(_ profile: CreditCardProfileEntity) {
        self.creditCardName = profile.name ?? "---"
        self.FxRate = "\(profile.fxRate)"
        self.clearinghouseCurrency = profile.clearinghouseCurrency ?? ""
        let decoder = JSONDecoder()
        switch profile.type {
        case 0:
            self.creditCardType = .CashBack
            let profile = try! decoder.decode(CashBackCreditCardProfile.self, from: (profile.properties?.data(using: .utf8))!)
            cbDomesticRate = "\(profile.cashBackRateDomestic)"
            cbInternationalRate = "\(profile.cashBackRateInternational)"
        case 1:
            self.creditCardType = .Mileage
            let profile = try! decoder.decode(MileageCreditCardProfile.self, from: (profile.properties?.data(using: .utf8))!)
            mDomesticRate = "\(profile.mileageRatioDomestic)"
            mInternationalRate = "\(profile.mileageRatioInternational)"
            mEstimatedValuePerMile = "\(profile.mileageEstimatedValue)"

        default:
            return
        }
    }
    
}
