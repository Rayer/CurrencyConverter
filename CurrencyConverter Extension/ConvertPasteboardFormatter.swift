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
    
    init(fromSymbol : String, fromAmount : Float32, toSymbol : String, toAmount : Float32) {
        self.fromSymbol = fromSymbol
        self.fromAmount = fromAmount
        self.toSymbol = toSymbol
        self.toAmount = toAmount
    }
    
    func getFormattedString(formatIndex: Int) -> String{
        guard ConversionTemplateCatalog.defaultIDs.indices.contains(formatIndex) else { return "" }
        return getFormattedString(template: ConversionTemplateCatalog.defaults[formatIndex])
    }
    
    func getFormattedString(template: ConversionTemplate) -> String {
        let values = ConversionTemplateValues(
            fromSymbol: fromSymbol,
            fromAmount: fromAmount,
            toSymbol: toSymbol,
            toAmount: toAmount
        )
        guard case .success(let formatted) = ConversionTemplateFormatter.format(template.text, values: values) else {
            return ""
        }
        return formatted
    }

    func getAllFormattedStrings(templates: [ConversionTemplate] = ConversionTemplateCatalog.defaults) -> [String] {
        templates.map { getFormattedString(template: $0) }
    }
}
