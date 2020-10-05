//
//  EntityDetailRow.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/24.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI
import Combine

struct EntityDetailRow: View {
    var title: String
    var sourceUrl : String
    var sourceCurrency : String
    var destCurrencyWithFx : String
    var destCurrencyWithoutFx : String
    var ratio : String
    @State var popoverFullUrl = false
    //@State var isChecked = false
    
    init(_ model: ConvertHistoryUIBean) {
                
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        
        title = (model.title == nil || model.title!.count < 2) ? model.url : model.title!
        sourceUrl = model.url
        sourceCurrency = FixedPercision(amount: model.fromAmount, symbol: model.fromSymbol)
        destCurrencyWithFx = FixedPercision(amount: model.fromAmount * model.ratio * (1 + model.fxFee), symbol: model.toSymbol)
        destCurrencyWithoutFx = FixedPercision(amount: model.fromAmount * model.ratio, symbol: model.toSymbol)
        ratio = String(format:"%.3f", model.ratio)
    }
    
    var body: some View {
        HStack {
//            Toggle(isOn: self.$isChecked) {
//            }
//            .frame(alignment: .center)
//            .padding(.leading)
            
            
            Text(title)
                .fontWeight(.semibold)
                .font(.system(.subheadline, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .frame(width: 300, alignment: .leading)
                .onHover(perform: { hovering in
                    popoverFullUrl = hovering
                })
                .popover(isPresented: $popoverFullUrl, content: {
                    Text(sourceUrl)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                })
            
            Divider()
            Text(sourceCurrency)
                .frame(width: 60, height: 40, alignment: .trailing)
            Text(destCurrencyWithFx)
                .frame(width: 60, height: 40, alignment: .trailing)
            Text(destCurrencyWithoutFx)
                .frame(width: 60, height: 40, alignment: .trailing)
            Text(ratio)
                .frame(width: 60, height: 40, alignment: .trailing)
            Button(action: {
                guard let url = URL(string: sourceUrl) else {
                    return
                }
                NSWorkspace.shared.open(url)
            }, label: {
                Text("Go To Page")
            })
                .padding()
        }
        
        
    }
}

struct EntityDetailRow_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            EntityDetailRow(generateModel())
        }
        //EmptyView()
    }
}

func FixedPercision(amount: Float, symbol: String) -> String {
    return String(format: "%.2f %@", amount, symbol)
}
