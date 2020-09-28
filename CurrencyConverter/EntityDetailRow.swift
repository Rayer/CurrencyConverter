//
//  EntityDetailRow.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/24.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI

struct EntityDetailRow: View {
    var sourceUrl : String
    var sourceCurrency : String
    var destCurrencyWithFx : String
    var destCurrencyWithoutFx : String
    var ratio : String
    
    init(_ model: ConvertHistory) {
        sourceUrl = model.url!
        sourceCurrency = "\(model.fromAmount)\(model.fromSymbol ?? "---")"
        destCurrencyWithFx = "\(model.fromAmount * model.ratio * (1 + model.fxFee))\(model.toSymbol)"
        destCurrencyWithoutFx = "\(model.fromAmount * model.ratio)\(model.toSymbol)"
        ratio = "\(model.ratio)"
        
    }
    
    var body: some View {
        HStack {
            Text(sourceUrl)
                .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                .lineLimit(3)
            Text(sourceCurrency)
            Text(destCurrencyWithFx)
            Text(destCurrencyWithoutFx)
            Text(ratio)
            Button(action: {}, label: {
                Text("Go To Page")
            })
        }
    }
}

struct EntityDetailRow_Previews: PreviewProvider {

    static var previews: some View {
        EntityDetailRow(generateModel())
    }
}
