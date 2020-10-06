//
//  FormatStringDataManager.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/5.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation
import CoreData

class FormatStringDataManager {
    let shared = FormatStringDataManager()
    private let view = sharedPersistentContainer.viewContext
    let ToAmountPH = "${to_amount}"
    let FromAmountPH = "${from_amount}"
    let ToSymbolPH = "${to_symbol}"
    let FromSymbolPH = "${from_symbol}"
    
    let defaultFormattingString : [String] = [
        "${to_amount} ${to_symbol}",
        "${to_amount}",
        "${from_amount} ${from_symbol} => ${to_amount} ${to_symbol}",
        "(${from_symbol}) ${from_amount} => (${to_symbol}) ${to_amount}"
    ]
    
    func ResetDefault() {
        wipeAll()
        defaultFormattingString.forEach { (s) in
            AddString(string: s)
        }
    }

    func AddString(string : String) {
        let entity = FormatStrings(context: view)
        entity.date = Date()
        entity.format_string = string
        entity.id = UUID()
        try! view.save()
    }

    func DeleteString(uuid : UUID) {
        let fr = NSFetchRequest<NSFetchRequestResult>(entityName: "FormatStrings")
        let p = NSPredicate(format: "id='\(uuid)'")
        fr.predicate = p
        if let result = try? view.fetch(fr) {
            for object in result {
                view.delete(object as! NSManagedObject)
            }
        }
        try! view.save()
    }

    func PreviewString(string : String) -> String {
        var ret = string
        ret = ret.replacingOccurrences(of: FromSymbolPH, with: "TWD")
        ret = ret.replacingOccurrences(of: ToSymbolPH, with: "USD")
        
        let toAmountFixed = String(format: "%.2f", 62.14)
        ret = ret.replacingOccurrences(of: FromAmountPH, with: String(describing: 2))
        ret = ret.replacingOccurrences(of: ToAmountPH, with: toAmountFixed)
        
        return ret
    }

    func PreviewString(id : UUID) -> String {
        let fr = NSFetchRequest<NSFetchRequestResult>(entityName: "FormatStrings")
        let p = NSPredicate(format: "id='\(id)'")
        fr.predicate = p
        if let result = try? view.fetch(fr) {
            for object in result {
                let entity = object as! FormatStrings
                return self.PreviewString(string: entity.format_string!)
            }
        }
        return "" //indicates not found
    }
    
    fileprivate func wipeAll() {
        //WipeAll
        let fr = NSFetchRequest<NSFetchRequestResult>(entityName: "FormatStrings")
        let dr = NSBatchDeleteRequest(fetchRequest: fr)
        try! view.execute(dr)
    }
}
