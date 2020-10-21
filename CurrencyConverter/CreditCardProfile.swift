//
//  CreditCardProfile.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/20.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation

protocol CreditCardProfile {
    var name : String {get}
    var currencySymbol: String {get}
    var internationalFxRate : Float? {get}
    func estimatedPrice(price: Float) -> Float
}

class CashBackCreditCardProfile : CreditCardProfile {
    var currencySymbol: String = "TWD"
    var internationalFxRate: Float?
    var name: String = ""
    var cashBackRateInternational: Float = 0.0
    var cashBackRateDomestic: Float = 0.0
    func estimatedPrice(price: Float) -> Float {
        guard let fxRate = internationalFxRate else {
            return price * cashBackRateDomestic
        }
        
        return price * fxRate * (1 - cashBackRateInternational)
    }
}

class MileageCreditCardProfile : CreditCardProfile {
    var currencySymbol: String = "TWD"
    var internationalFxRate: Float?
    var name: String = ""
    var mileageRatioInternational: Float = 0.0
    var mileageRatioDomestic: Float = 0.0
    var mileageEstimatedValue: Float = 0.0
    
    func estimatedPrice(price: Float) -> Float {
        guard let fxRate = internationalFxRate else {
            return price - (price * mileageRatioDomestic * mileageEstimatedValue)
        }
        
        return (price * fxRate) - (price * mileageRatioInternational * mileageEstimatedValue)
    }
}
