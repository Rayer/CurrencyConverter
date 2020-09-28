//
//  EntityDetailRow.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/24.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI

struct EntityDetailRow: View {
    var title: String
    var sourceUrl : String
    var sourceCurrency : String
    var destCurrencyWithFx : String
    var destCurrencyWithoutFx : String
    var ratio : String
    @State var popoverFullUrl = false
    
    init(_ model: ConvertHistoryDM) {
        title = (model.title == nil || model.title!.count < 2) ? model.url : model.title!
        sourceUrl = model.url
        sourceCurrency = "\(model.fromAmount)\(model.fromSymbol )"
        destCurrencyWithFx = "\(model.fromAmount * model.ratio * (1 + model.fxFee))\(model.toSymbol)"
        destCurrencyWithoutFx = "\(model.fromAmount * model.ratio)\(model.toSymbol)"
        ratio = "\(model.ratio)"
    }
    
    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
                .font(.system(.subheadline, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .padding()
                .onHover(perform: { hovering in
                    popoverFullUrl = hovering
                })
                .popover(isPresented: $popoverFullUrl, content: {
                    Text(sourceUrl)
                })
            
                
            Text(sourceCurrency)
            Text(destCurrencyWithFx)
            Text(destCurrencyWithoutFx)
            Text(ratio)
            Button(action: {
                
            }, label: {
                Text("Go To Page")
            })
                .padding()
        }
    }
}

struct EntityDetailRow_Previews: PreviewProvider {

    static var previews: some View {
        EntityDetailRow(generateModel())
    }
}
