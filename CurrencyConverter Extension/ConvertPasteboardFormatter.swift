//
//  ConvertPasteboardFormatter.swift
//  CurrencyConverter Extension
//
//  Created by Rayer on 2019/11/16.
//  Copyright © 2019 Rayer. All rights reserved.
//

import Foundation

class ConvertPasteboardFormatter {
    var fromSymbol : String
    var fromAmount : Float32
    var toSymbol : String
    var toAmount : Float32
    
    let ToAmountPH = "${to_amount}"
    let FromAmountPH = "${from_amount}"
    let ToSymbolPH = "${to_symbol}"
    let FromSymbolPH = "${from_symbol}"
    
    static let defaultFormattingString : [String] = [
        "${to_amount} ${to_symbol}",
        "${to_amount}",
        "${from_amount} ${from_symbol} => ${to_amount} ${to_symbol}",
        "(${from_symbol}) ${from_amount} => (${to_symbol}) ${to_amount}"
    ]
    
    init(fromSymbol : String, fromAmount : Float32, toSymbol : String, toAmount : Float32) {
        self.fromSymbol = fromSymbol
        self.fromAmount = fromAmount
        self.toSymbol = toSymbol
        self.toAmount = toAmount
    }
    
    func getFormattedString(formatIndex: Int) -> String{
        var ret = ConvertPasteboardFormatter.defaultFormattingString[formatIndex]
        ret = ret.replacingOccurrences(of: FromSymbolPH, with: self.fromSymbol)
        ret = ret.replacingOccurrences(of: ToSymbolPH, with: self.toSymbol)
        
        let toAmountFixed = String(format: "%.2f", self.toAmount)
        ret = ret.replacingOccurrences(of: FromAmountPH, with: String(describing: self.fromAmount))
        ret = ret.replacingOccurrences(of: ToAmountPH, with: toAmountFixed)
        
        return ret
    }
    
    func getAllFormattedStrings() -> [String] {
        var ret : [String] = []
        for x in 0...(ConvertPasteboardFormatter.defaultFormattingString.count - 1) {
            ret.insert(getFormattedString(formatIndex: x), at: x)
        }
        return ret
    }
}
