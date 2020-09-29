//
//  ConvertHistoryDM.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/28.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation

//Can't use CoreData in Preview, so we need adapt it.

struct ConvertHistoryUIBean : Identifiable {
    var id: UUID
    var title: String?
    var url: String
    var fromSymbol: String
    var toSymbol: String
    var fromAmount: Float
    var fxFee: Float
    var ratio: Float
    var isChecked = false
    
    static func fromCoreData(c: ConvertHistory) -> ConvertHistoryUIBean{
        return ConvertHistoryUIBean(id: c.id ?? UUID(), title: c.title ?? "", url: c.url ?? "", fromSymbol: c.fromSymbol ?? "", toSymbol: c.toSymbol ?? "", fromAmount: c.fromAmount, fxFee: c.fxFee, ratio: c.ratio)
    }
    
}

class ConvertHistoryDMCollection : ObservableObject {
    @Published var data : [ConvertHistoryUIBean] = []
    @objc func reload() {
        self.data = []
        guard let cdList = readFromCore() else {
            return
        }
        for entry in cdList {
            self.data.append(ConvertHistoryUIBean.fromCoreData(c: entry))
        }
    }
    func wipe() {
        wipeAll()
        self.data = []
    }
    
    func wipeChecked() {
        for i in data.indices {
            if data[i].isChecked {
                data.remove(at: i)
                wipeById(data[i].id)
            }
        }
        
    }

}
