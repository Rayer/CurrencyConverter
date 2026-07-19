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

    // Renew owns this private queue/context. It must never save or roll back the UI viewContext.
    private let context: NSManagedObjectContext
    private let saveOperation: (() throws -> Void)?

    init(context: NSManagedObjectContext? = nil, saveOperation: (() throws -> Void)? = nil) {
        self.context = context ?? sharedPersistentContainer.newBackgroundContext()
        self.saveOperation = saveOperation
    }

    private func ensurePermanentIDs(for objects: [ConvertHistory]) throws {
        let temporaryObjects = objects.filter { $0.objectID.isTemporaryID }
        if !temporaryObjects.isEmpty {
            try context.obtainPermanentIDs(for: temporaryObjects)
        }
    }
    
    func wipeAll() {
        let vc = context
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ConvertHistory")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        vc.performAndWait {
            try! vc.execute(deleteRequest)
        }
    }
    
    func wipeById(_ at: UUID) {
        let vc = context
        vc.performAndWait {
            do {
                let businessIDRequest = NSFetchRequest<ConvertHistory>(entityName: "ConvertHistory")
                businessIDRequest.predicate = NSPredicate(format: "id == %@", at as CVarArg)
                let businessIDMatches = try vc.fetch(businessIDRequest)
                if !businessIDMatches.isEmpty {
                    businessIDMatches.forEach { vc.delete($0) }
                    try vc.save()
                    return
                }

                let nilIDRequest = NSFetchRequest<ConvertHistory>(entityName: "ConvertHistory")
                nilIDRequest.predicate = NSPredicate(format: "id == nil")
                let nilIDRows = try vc.fetch(nilIDRequest)
                try ensurePermanentIDs(for: nilIDRows)
                guard let fallbackMatch = nilIDRows.first(where: { object in
                    RenewPresentationIdentity.id(
                        businessID: object.id,
                        objectIDURI: object.objectID.uriRepresentation().absoluteString
                    ) == at
                }) else {
                    return
                }
                vc.delete(fallbackMatch)
                try vc.save()
            } catch {
                vc.rollback()
            }
        }
    }

    
}

extension CHDataManager: AtomicRenewStore {
    func snapshotForRenew(completion: @escaping (Result<[RenewRowSnapshot], Error>) -> Void) {
        context.perform {
            do {
                let request = NSFetchRequest<ConvertHistory>(entityName: "ConvertHistory")
                request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
                let objects = try self.context.fetch(request)
                try self.ensurePermanentIDs(for: objects)
                completion(.success(objects.map { object in
                    RenewRowSnapshot(
                        objectID: object.objectID.uriRepresentation().absoluteString,
                        businessID: object.id,
                        fromSymbol: object.fromSymbol,
                        toSymbol: object.toSymbol,
                        fromAmount: object.fromAmount,
                        ratio: object.ratio
                    )
                }))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func applyRenew(updates: [RenewUpdate], completion: @escaping (RenewApplyOutcome) -> Void) {
        context.perform {
            do {
                let request = NSFetchRequest<ConvertHistory>(entityName: "ConvertHistory")
                let objects = try self.context.fetch(request)
                var byObjectID: [String: ConvertHistory] = [:]
                for object in objects {
                    byObjectID[object.objectID.uriRepresentation().absoluteString] = object
                }

                var changedObjects: [(ConvertHistory, Float32)] = []
                var matchedObjectIDs = Set<String>()
                for update in updates {
                    guard matchedObjectIDs.insert(update.objectID).inserted,
                          let object = byObjectID[update.objectID],
                          object.objectID.uriRepresentation().absoluteString == update.objectID,
                          object.id == update.businessID,
                          !object.isDeleted else {
                        continue
                    }
                    if object.ratio != update.ratio {
                        changedObjects.append((object, object.ratio))
                        object.ratio = update.ratio
                    }
                }

                guard !changedObjects.isEmpty else {
                    completion(RenewApplyOutcome(appliedCount: 0, changedCount: 0, saveError: nil))
                    return
                }

                do {
                    if let saveOperation = self.saveOperation {
                        try saveOperation()
                    } else {
                        try self.context.save()
                    }
                    completion(RenewApplyOutcome(
                        appliedCount: changedObjects.count,
                        changedCount: changedObjects.count,
                        saveError: nil
                    ))
                } catch {
                    for (object, oldRatio) in changedObjects {
                        object.ratio = oldRatio
                    }
                    self.context.rollback()
                    completion(RenewApplyOutcome(appliedCount: 0, changedCount: 0, saveError: error))
                }
            } catch {
                completion(RenewApplyOutcome(appliedCount: 0, changedCount: 0, saveError: error))
            }
        }
    }

    func readHistory(completion: @escaping ([RenewHistoryValue]) -> Void) {
        context.perform {
            let values: [RenewHistoryValue]
            do {
                let request = NSFetchRequest<ConvertHistory>(entityName: "ConvertHistory")
                request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
                let objects = try self.context.fetch(request)
                try self.ensurePermanentIDs(for: objects)
                values = objects.map { object in
                    RenewHistoryValue(
                        objectID: object.objectID.uriRepresentation().absoluteString,
                        id: object.id,
                        title: object.title,
                        url: object.url,
                        fromSymbol: object.fromSymbol,
                        toSymbol: object.toSymbol,
                        fromAmount: object.fromAmount,
                        fxFee: object.fxFee,
                        ratio: object.ratio
                    )
                }
            } catch {
                values = []
            }
            completion(values)
        }
    }
}
