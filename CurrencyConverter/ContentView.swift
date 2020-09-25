//
//  ContentView.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/23.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    let previewTarget = [CCDataModel(url: "https://www.example.com/item/213", sourceSymbol: "USD", destSymbol: "TWD", ratio: 33.2, fxRate: 0.015, sourceAmount: 10.0, destAmount: 332.0),CCDataModel(url: "https://www.example.com/item/214", sourceSymbol: "USD", destSymbol: "TWD", ratio: 33.2, fxRate: 0.015, sourceAmount: 10.0, destAmount: 332.0),CCDataModel(url: "https://www.example.com/item/215", sourceSymbol: "USD", destSymbol: "TWD", ratio: 33.2, fxRate: 0.015, sourceAmount: 10.0, destAmount: 332.0)]

    var body: some View {
        List(previewTarget, id: \.id) { c in
            EntityDetailRow(c)
        }
    }
}


struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView()
            
    }
}
