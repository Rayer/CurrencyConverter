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
    
    static let formatterString : [String] = [
        "12345.67 BBB",
        "12345.67",
        "890.1 AAA => 12345.67 BBB",
        "(AAA) 890.1 => (BBB) 12345.67"
    ]
    
    init(fromSymbol : String, fromAmount : Float32, toSymbol : String, toAmount : Float32) {
        self.fromSymbol = fromSymbol
        self.fromAmount = fromAmount
        self.toSymbol = toSymbol
        self.toAmount = toAmount
    }
    
    func getFormattedString(formatIndex: Int) -> String{
        var ret = ConvertPasteboardFormatter.formatterString[formatIndex]
        ret = ret.replacingOccurrences(of: "AAA", with: self.fromSymbol)
        ret = ret.replacingOccurrences(of: "BBB", with: self.toSymbol)
        ret = ret.replacingOccurrences(of: "890.1", with: String(describing: self.fromAmount))
        ret = ret.replacingOccurrences(of: "12345.67", with: String(describing: self.toAmount))
        
        return ret
    }
    
    
    
}
