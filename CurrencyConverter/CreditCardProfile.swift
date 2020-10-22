//
//  CreditCardProfile.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/20.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation
import CoreData

protocol CreditCardProfile {
    var name : String {get set}
    var currencySymbol: String {get set}
    var fxRate : Float {get set}
    func estimatedPrice(price: Float, targetSymbol: String) -> Float
    func generateProperties() -> String
    func getType() -> Int
}

func LoadCreditCardProfile(name: String) -> CreditCardProfile? {
    let vc = sharedPersistentContainer.viewContext
    let fr = NSFetchRequest<NSFetchRequestResult>(entityName: "CreditCardProfileEntity")
    let pr = NSPredicate(format: "name='\(name)'")
    fr.predicate = pr
    let r = try! vc.fetch(fr) as! [CreditCardProfileEntity]
    
    guard r.count == 1 else {
        return nil
    }
    
    let entity = r[0]
    
    var ret : CreditCardProfile
    let decoder = JSONDecoder()
    
    if entity.type == 0 {
        ret = try! decoder.decode(CashBackCreditCardProfile.self, from: (entity.properties?.data(using: .utf8))!)
    } else if entity.type == 1 {
        ret = try! decoder.decode(MileageCreditCardProfile.self, from: (entity.properties?.data(using: .utf8))!)
    } else {
        return nil
    }
    ret.currencySymbol = entity.clearinghouseCurrency!
    ret.name = entity.name!
    ret.fxRate = entity.fxRate
    return ret
    
}

func FetchAllCreditCardProfiles() -> [CreditCardProfileEntity] {
    let vc = sharedPersistentContainer.viewContext
    let fr = NSFetchRequest<NSFetchRequestResult>(entityName: "CreditCardProfileEntity")
    let r = try! vc.fetch(fr) as! [CreditCardProfileEntity]
//    return r.map { (entity) -> CreditCardProfile in
//        var profile : CreditCardProfile
//        let decoder = JSONDecoder()
//        if entity.type == 0 {
//            profile = try! decoder.decode(CashBackCreditCardProfile.self, from: (entity.properties?.data(using: .utf8))!)
//        } else {
//            profile = try! decoder.decode(MileageCreditCardProfile.self, from: (entity.properties?.data(using: .utf8))!)
//        }
//        profile.name = entity.name!
//        profile.currencySymbol = entity.clearinghouseCurrency!
//        profile.fxRate = entity.fxRate
//        return profile
//    }
    return r
}

func SaveCreditCardProfile(profile: CreditCardProfile) {
    let vc = sharedPersistentContainer.viewContext
    let entity = CreditCardProfileEntity(context: vc)
    entity.name = profile.name
    entity.clearinghouseCurrency = profile.currencySymbol
    entity.fxRate = profile.fxRate
    entity.type = Int32(profile.getType())
    entity.properties = profile.generateProperties()
    do {
        try vc.save()
    } catch {
        print(error)
    }
    
}

class CashBackCreditCardProfile : CreditCardProfile, Codable {
    
    var currencySymbol: String = "TWD"
    var fxRate: Float = 1.5
    var name: String = ""
    var cashBackRateInternational: Float = 0.0
    var cashBackRateDomestic: Float = 0.0
    func estimatedPrice(price: Float, targetSymbol: String) -> Float {
        if targetSymbol == currencySymbol {
            return price * cashBackRateDomestic
        }
        return price * fxRate * (1 - cashBackRateInternational)
    }
    
    func generateProperties() -> String {
        return String(decoding: try! JSONEncoder().encode(self), as: UTF8.self)
    }
    func getType() -> Int {
        0
    }
}

class MileageCreditCardProfile : CreditCardProfile, Codable {
    var currencySymbol: String = "TWD"
    var fxRate: Float = 1.5
    var name: String = ""
    var mileageRatioInternational: Float = 0.0
    var mileageRatioDomestic: Float = 0.0
    var mileageEstimatedValue: Float = 0.0
    
    func estimatedPrice(price: Float, targetSymbol: String) -> Float {
        if targetSymbol == currencySymbol {
            return price - (price * mileageRatioDomestic * mileageEstimatedValue)
        }
        return (price * fxRate) - (price * mileageRatioInternational * mileageEstimatedValue)
    }
    
    func generateProperties() -> String {
        return String(decoding: try! JSONEncoder().encode(self), as: UTF8.self)
    }
    func getType() -> Int {
        1
    }
}
