//
//  PreviewConvertHistory.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/28.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation
import CoreData

func generateModel() -> ConvertHistory {
    let model = ConvertHistory()
    model.date = Date()
    model.fromAmount = 10
    model.fromSymbol = "TWD"
    model.fxFee = 0.015
    model.ratio = 31.1
    model.title = "OMG"
    model.toSymbol = "USD"
    model.url = "http://hi.com.tw"
    return model
}

func readFromCore() -> [ConvertHistory]? {
    let vc = persistentContainer.viewContext
    let fetchRequst = NSFetchRequest<NSManagedObject>(entityName: "ConvertHistory")
    let objects = try? vc.fetch(fetchRequst) as? [ConvertHistory]
    return objects
}

