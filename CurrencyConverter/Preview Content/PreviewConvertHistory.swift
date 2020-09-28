//
//  PreviewConvertHistory.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/28.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation
import CoreData

func generateModel() -> ConvertHistoryDM {
    return ConvertHistoryDM(title: "ExampleTitle", url: "https://example.com", fromSymbol: "USD", toSymbol: "TWD", fromAmount: 22.6, fxFee: 0.02, ratio: 31.3)
}

func readFromCore() -> [ConvertHistory]? {
    let vc = persistentContainer.viewContext
    let fetchRequst = NSFetchRequest<NSManagedObject>(entityName: "ConvertHistory")
    let objects = try? vc.fetch(fetchRequst) as? [ConvertHistory]
    return objects
}

