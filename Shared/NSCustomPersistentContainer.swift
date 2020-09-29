//
//  NSCustomPersistentContainer.swift
//  Utilplugin
//
//  Created by Rayer on 2019/11/2.
//  Copyright © 2019 Rayer. All rights reserved.
//

import Foundation
import CoreData

class NSCustomPersistentContainer: NSPersistentContainer {

    override open class func defaultDirectoryURL() -> URL {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "8AA96R6MF3.com.rayer.CurrencyConverter")!
        //storeURL = storeURL?.appendingPathComponent("CurrencyConverter.sqlite")
        //return storeURL!
    }
}

// MARK: - Core Data stack
var persistentContainer: NSPersistentContainer = {
    /*
     The persistent container for the application. This implementation
     creates and returns a container, having loaded the store for the
     application to it. This property is optional since there are legitimate
     error conditions that could cause the creation of the store to fail.
     */
    let container = NSCustomPersistentContainer(name: "CurrencyExchangeRate")
    let description = container.persistentStoreDescriptions.first
    description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
    description?.setOption(true as NSNumber, forKey: "NSPersistentStoreRemoteChangeNotificationOptionKey")
    //let container = NSPersistentContainer(name: "CurrencyExchangeRate")

    container.loadPersistentStores(completionHandler: { (storeDescription, error) in
        if let error = error as NSError? {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            
            /*
             Typical reasons for an error here include:
             * The parent directory does not exist, cannot be created, or disallows writing.
             * The persistent store is not accessible, due to permissions or data protection when the device is locked.
             * The device is out of space.
             * The store could not be migrated to the current model version.
             Check the error message to determine what the actual problem was.
             */
            fatalError("Unresolved error \(error), \(error.userInfo)")
        }
    })
    return container
}()

// MARK: - Core Data Saving support

func saveContext () {
    let context = persistentContainer.viewContext
    if context.hasChanges {
        do {
            try context.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nserror = error as NSError
            fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
        }
    }
}

func readFromCore() -> [ConvertHistory]? {
    let vc = persistentContainer.viewContext
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
    let vc = persistentContainer.viewContext
    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ConvertHistory")
    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
    try! vc.execute(deleteRequest)
}

