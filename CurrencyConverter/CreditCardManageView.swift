//
//  CreditCardManageView.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/20.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI

struct CreditCardManageView: View {
    @ObservedObject var model = CreditCardManagerViewModel()
    @State var creditCardTypeSelection = 1

    var body: some View {
        VStack {
            Picker(selection: self.$creditCardTypeSelection, label: Text("Credit Card Type")){
                Text("Cash-back based").tag(1)
                Text("Mileage or point based").tag(2)
            }.padding()
            
            VStack(alignment: .leading, spacing: 2, content: {
                Text("Card Identifier")
                TextField("Card identifier, must be unique", text: self.$model.creditCardName)
            }).padding()
             
            
            Picker(selection: self.$model.clearinghouseCurrency, label: Text("Clearinghouse Currency")){
                ForEach(self.model.clearinghouseCurrencyList, id:\.self) { (symbol) in
                    Text(symbol)
                }
            }.padding()
                
            
            if self.creditCardTypeSelection == 1 {
                VStack (alignment: .leading, spacing: 2, content: {
                    Text("Domenstic Cash-back Rate")
                    TextField("Cash Back rate while applying domenstic currency", text: self.$model.cbDomensticRate)
                }).padding()
                VStack (alignment: .leading, spacing: 2, content: {
                    Text("International Cash-back Rate")
                    TextField("Cash Back rate while applying foreign currency", text: self.$model.cbInternationalRate)
                }).padding()
                VStack (alignment: .leading, spacing: 2, content: {
                    Text("FX Rate")
                    TextField("International FX Rate", text: self.$model.FxRate)
                }).padding()
            } else if self.creditCardTypeSelection == 2 {
                
                VStack (alignment: .leading, spacing: 2, content: {
                    Text("Mileage / Point domenstic rate")
                    TextField("Mileage(Point) rate while applying domenstic currency", text: self.$model.mDomensticRate)
                }).padding()
                
                VStack (alignment: .leading, spacing: 2, content: {
                    Text("Mileage / Point international rate")
                    TextField("Mileage(Point) ratewhile applying international currency", text: self.$model.mInternationalRate)
                }).padding()
                
                VStack (alignment: .leading, spacing: 2, content: {
                    Text("FX Rate")
                    TextField("International FX Rate", text: self.$model.FxRate)
                }).padding()
                
                VStack (alignment: .leading, spacing: 2, content: {
                    Text("Estimated Mileage(point) value ")
                    TextField("Estimated Mileage(Point) value per point", text: self.$model.mEstimatedValuePerMile)
                }).padding()
                
            }
            Spacer()
            Button("Add Card!") {
                
            }
        }
    }
}



struct CreditCardManageView_Previews: PreviewProvider {
    static var previews: some View {
        CreditCardManageView()
    }
}
