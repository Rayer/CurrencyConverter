//
//  EntityDetailRow.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/24.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI
import Combine

class EntityDetailRowViewModel: ObservableObject{
    @Published var title: String = ""
    @Published var sourceUrl: String = ""
    @Published var sourceCurrency: String = ""
    @Published var destCurrencyWithFx: String = ""
    @Published var destCurrencyWithoutFx: String = ""
    @Published var ratio : String = ""
    @Published var creditCardInfo : [String] = []
    @Published var selectedCreditCard = 0
    
}

struct EntityDetailRow: View {
    
    @ObservedObject var model = EntityDetailRowViewModel()
    @State var popoverFullUrl = false
    
    init(_ model: ConvertHistoryUIBean) {
                
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        
        self.model.title = (model.title == nil || model.title!.count < 2) ? model.url : model.title!
        self.model.sourceUrl = model.url
        self.model.sourceCurrency = FixedPercision(amount: model.fromAmount, symbol: model.fromSymbol)
        self.model.destCurrencyWithFx = FixedPercision(amount: model.fromAmount * model.ratio * (1 + model.fxFee), symbol: model.toSymbol)
        self.model.destCurrencyWithoutFx = FixedPercision(amount: model.fromAmount * model.ratio, symbol: model.toSymbol)
        self.model.ratio = String(format:"%.3f", model.ratio)
        
        FetchAllCreditCardProfiles().forEach { (profile) in
            self.model.creditCardInfo.append("\(profile.name) - \(profile.estimatedPrice(price: model.ratio * model.fromAmount, targetSymbol: model.toSymbol))")
        }
    }
    
    var body: some View {
        HStack {
//            Toggle(isOn: self.$isChecked) {
//            }
//            .frame(alignment: .center)
//            .padding(.leading)
            
            
            Text(model.title)
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
                    Text(model.sourceUrl)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                })
            
            Divider()
            
            VStack(alignment: .leading) {
                Text(model.sourceCurrency)
                    .frame(width: 120, height: 20, alignment: .trailing)
                    .font(.system(Font.TextStyle.caption, design: .rounded))
                Text(model.destCurrencyWithoutFx)
                    .frame(width: 120, height: 20, alignment: .trailing)
                    .font(.system(Font.TextStyle.caption, design: .rounded))
                Text(model.destCurrencyWithFx)
                    .frame(width: 120, height: 20, alignment: .trailing)
                    .font(.system(Font.TextStyle.caption, design: .rounded))
            }

            Text(model.ratio)
                .frame(width: 60, height: 40, alignment: .trailing)
            VStack {
                Picker(selection: $model.selectedCreditCard, label: EmptyView()){
                    ForEach(model.creditCardInfo.indices, id: \.self) { (index) in
                        Text(model.creditCardInfo[index]).tag(index)
                    }

                }
                
                Text("------")
            }.frame(width: 100, height: 40, alignment: .trailing)
            Button(action: {
                guard let url = URL(string: model.sourceUrl) else {
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
            EntityDetailRow(ConvertHistoryUIBean(id: UUID(), title: "ExampleTitle", url: "https://example.com/it_is_a/very/long_url", fromSymbol: "USD", toSymbol: "TWD", fromAmount: 22.6, fxFee: 0.02, ratio: 31.3))
        }
        //EmptyView()
    }
}

func FixedPercision(amount: Float, symbol: String) -> String {
    let symbols = CountryCurrency.shared
    return String(format: "%@ %.2f %@", symbols.getSymbolPrefix(symbol: symbol), amount, symbols.getFlag(symbol: symbol))
}
