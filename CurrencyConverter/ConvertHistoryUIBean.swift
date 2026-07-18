//
//  ConvertHistoryDM.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/28.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation

extension ConvertHistory: ConvertHistoryRecord {}

class ConvertHistoryDMCollection : ObservableObject {
    @Published var data : [ConvertHistoryUIBean] = []
    let dataManager = CHDataManager.shared
    
    @objc func reload() {
        self.data = []
        guard let cdList = dataManager.readFromCore() else {
            return
        }
        for entry in cdList {
            self.data.append(ConvertHistoryUIBean.fromCoreData(c: entry))
        }
    }
    func wipe() {
        dataManager.wipeAll()
        self.data = []
    }
    
    func wipeChecked() {
        data.enumerated()
            .filter { $0.element.isChecked }
            .forEach {
                dataManager.wipeById($0.element.id)
            }
        data = data.enumerated()
            .filter { $0.element.isChecked == false }
            .map { $0.element }
        
    }
    
    func renewFx() {
        dataManager.readFromCore()?.forEach({ (entity) in
            CurrencyConverter.shared.convert(from: entity.fromSymbol!, to: entity.toSymbol!, unit: entity.fromAmount) { (result, error) in
                entity.ratio = result / entity.fromAmount
            }
        })
        try! sharedPersistentContainer.viewContext.save()
        self.reload()
    }

}
