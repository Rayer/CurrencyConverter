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
    
    init(_ model: CCDataModel) {
        sourceUrl = model.url
        sourceCurrency = "\(model.sourceAmount)\(model.sourceSymbol)"
        destCurrencyWithFx = "\(model.destAmount * (1 + model.fxRate))\(model.destSymbol)"
        destCurrencyWithoutFx = "\(model.destAmount)\(model.destSymbol)"
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
    static let model = CCDataModel(url: "https://www.example.com/item/213", sourceSymbol: "USD", destSymbol: "TWD", ratio: 33.2, fxRate: 0.015, sourceAmount: 10.0, destAmount: 332.0)
    static var previews: some View {
        EntityDetailRow(model)
    }
}
