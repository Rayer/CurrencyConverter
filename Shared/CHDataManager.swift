//
//  CHDataManager.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/5.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation
import CoreData

class CHDataManager {
    static let shared = CHDataManager()
    
    func readFromCore() -> [ConvertHistory]? {
        let vc = sharedPersistentContainer.viewContext
        let fetchRequst = NSFetchRequest<NSManagedObject>(entityName: "ConvertHistory")
        let sort = NSSortDescriptor(keyPath: \ConvertHistory.date, ascending: false)
        fetchRequst.sortDescriptors = [sort]
        let objects = try? vc.fetch(fetchRequst) as? [ConvertHistory]
        
        if let objects = objects {
            for i in objects.indices {
                if objects[i].id == nil {
                    objects[i].id = UUID()
                }
            }
            return objects
        }
        
        return nil
    }
    
    func wipeAll() {
        let vc = sharedPersistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ConvertHistory")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        try! vc.execute(deleteRequest)
    }
    
    func wipeById(_ at: UUID) {
        let vc = sharedPersistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ConvertHistory")
        let predicate = NSPredicate(format: "id = '\(at)'")
        fetchRequest.predicate = predicate
        if let result = try? vc.fetch(fetchRequest) {
            for object in result {
                vc.delete(object as! NSManagedObject)
            }
        }
        try! vc.save()
    }

    
}
