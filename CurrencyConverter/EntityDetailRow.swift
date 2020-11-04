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
    @Published var creditCardReward : [String] = []
    @Published var creditCardRewardWorth : [String] = []
    @Published var bestPrice : String = ""
    @Published var selectedCreditCardIndex = 0
    @Published var selectedCardRewardDetail = ""
    @Published var totalFxFee : [String] = []
    
}

struct EntityDetailRow: View {
    
    @ObservedObject var model = EntityDetailRowViewModel()
    @State var popoverFullUrl = false
    
    init(_ bean: ConvertHistoryUIBean) {
                
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        
        self.model.title = (bean.title == nil || bean.title!.count < 2) ? bean.url : bean.title!
        self.model.sourceUrl = bean.url
        self.model.sourceCurrency = FixedPercision(amount: bean.fromAmount, symbol: bean.fromSymbol)
        self.model.destCurrencyWithFx = FixedPercision(amount: bean.toAmountWithFx, symbol: bean.toSymbol)
        self.model.destCurrencyWithoutFx = FixedPercision(amount: bean.toAmount, symbol: bean.toSymbol)
        self.model.ratio = String(format:"%.3f", bean.ratio)
                
        var bestPrice : Float?
        FetchAllCreditCardProfiles().forEach { (profile) in
            let estimatedPrice = profile.estimatedPrice(price: bean.toAmount, sourceSymbol: bean.fromSymbol)
            self.model.creditCardInfo.append("\(profile.name) - \(FixedPercision(amount: estimatedPrice, symbol: profile.currencySymbol))")
            
            self.model.totalFxFee.append(FixedPercision(amount: profile.fxRate * bean.toAmount * 0.01, symbol: profile.currencySymbol))
            
            
            if profile.getType() == 0 {
                self.model.creditCardReward.append("Cashback")
                self.model.creditCardRewardWorth.append(FixedPercision(amount: profile.estimateRewardAmount(price: bean.toAmount, sourceSymbol: bean.fromSymbol), symbol: profile.currencySymbol))
                
            } else {
                let points = Int(profile.estimateRewardAmount(price: bean.toAmount, sourceSymbol: profile.currencySymbol))
                let value = (profile as! MileageCreditCardProfile).mileageEstimatedValue * Float(points)
                self.model.creditCardReward.append("\(points) points")
                self.model.creditCardRewardWorth.append(FixedPercision(amount: value, symbol: profile.currencySymbol))
            }
            

            if let b = bestPrice {
                if b > estimatedPrice {
                    bestPrice = estimatedPrice
                }
            } else {
                bestPrice = estimatedPrice
            }
            
            self.model.bestPrice = FixedPercision(amount: bestPrice!, symbol: bean.toSymbol)
        }
    }
    
    var body: some View {
        HStack {
            
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
                Picker(selection: $model.selectedCreditCardIndex, label: EmptyView()){
                    ForEach(model.creditCardInfo.indices, id: \.self) { (index) in
                        Text(model.creditCardInfo[index]).tag(index)
                    }
                }
                Text(model.bestPrice)
                    .font(.system(Font.TextStyle.caption, design: .rounded))
            }.frame(width: 120, height: 40, alignment: .trailing)
            VStack {
                Group {
                    Text(model.creditCardReward[model.selectedCreditCardIndex])
                    Text(model.creditCardRewardWorth[model.selectedCreditCardIndex])
                    Text(model.totalFxFee[model.selectedCreditCardIndex])
                }.frame(width: 120, height: 20, alignment: .trailing)
                 .font(.system(Font.TextStyle.caption, design: .rounded))
            }
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
            EntityDetailRow(ConvertHistoryUIBean(id: UUID(), title: "ExampleTitle", url: "https://example.com/it_is_a/very/long_url", fromSymbol: "USD", toSymbol: "TWD", fromAmount: 22.6, fxFeeRate: 0.02, ratio: 31.3))
        }
        //EmptyView()
    }
}

func FixedPercision(amount: Float, symbol: String) -> String {
    let symbols = CountryCurrency.shared
    return String(format: "%@ %.2f %@", symbols.getSymbolPrefix(symbol: symbol), amount, symbols.getFlag(symbol: symbol))
}
