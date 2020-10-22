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
            }
            .pickerStyle(RadioGroupPickerStyle())
            .padding()
            
             
            UnifiedView(title: "Card Profile Name", description: "Card Indentifier, must be unique", bindedValue: self.$model.creditCardName).padding()
            
            Picker(selection: self.$model.clearinghouseCurrency, label: Text("Clearinghouse Currency")){
                ForEach(self.model.clearinghouseCurrencyList, id:\.self) { (symbol) in
                    Text("\(CountryCurrency.shared.getFlag(symbol: symbol)) \(symbol)").tag(symbol)
                }
            }.padding()
            
            Group {
                if self.creditCardTypeSelection == 1 {
                    UnifiedView(title: "Domestic Cash-Back Rate", description: "Cash Back rate while applying domestic currency", errorMessage: "Value must be a number", bindedValue: self.$model.cbDomesticRate, isValid: self.model.cbDomesticRateValidate)
                    UnifiedView(title: "International Cash-Back Rate", description: "Cash Back rate while applying foreign currency", errorMessage: "Value must be a number", bindedValue: self.$model.cbInternationalRate, isValid: self.model.cbInternationalRateValidate)
                    UnifiedView(title: "FX Rate", description: "International FX Rate", errorMessage: "Must be a number and between 0 and 100", bindedValue: self.$model.FxRate, isValid: self.model.FxRateValidate)
                    
                    
                } else if self.creditCardTypeSelection == 2 {
                    
                    UnifiedView(title: "Mileage/Point domestic rate", description: "Mileage(Point) rate while applyiny domestic currency", errorMessage: "Value must be a number", bindedValue: self.$model.mDomesticRate, isValid: self.model.mDomesticRateValidate)
                    UnifiedView(title: "Mileage / Point international rate", description: "Mileage(Point) ratewhile applying international currency", errorMessage: "Value must be a number", bindedValue: self.$model.mInternationalRate, isValid: self.model.mInternationalRateValidate)
                    UnifiedView(title: "FX Rate", description: "International FX Rate", errorMessage: "Must be a number and between 0 and 100", bindedValue: self.$model.FxRate, isValid: self.model.FxRateValidate)
                    UnifiedView(title: "Estimated Mileage(point) value", description: "Estimated Mileage(Point) value per point", errorMessage: "Must be a number!", bindedValue: self.$model.mEstimatedValuePerMile, isValid: self.model.mEstimatedValuePerMileValid)
                }
            }.padding()

            Spacer()
            Button("Add Card!") {
                print("\(model.clearinghouseCurrency)")
            }
        }
    }
}



struct CreditCardManageView_Previews: PreviewProvider {
    static var previews: some View {
        CreditCardManageView()
    }
}

struct UnifiedView: View {
    
    var title: String
    var description: String
    var errorMessage: String = ""
    var bindedValue: Binding<String>
    var isValid: Bool = false
    
    init(title: String, description: String, bindedValue: Binding<String>) {
        self.title = title
        self.description = description
        self.bindedValue = bindedValue
    }
    
    init(title: String, description: String, errorMessage: String, bindedValue: Binding<String>, isValid: Bool) {
        self.title = title
        self.description = description
        self.bindedValue = bindedValue
        self.errorMessage = errorMessage
        self.isValid = isValid
    }
    var body: some View {
        VStack (alignment: .leading, spacing: 2, content: {
            Text(title)
            TextField(description, text: bindedValue)
            if !self.isValid {
                Text(errorMessage)
                    .foregroundColor(.red)
            } else {
                Text("")
            }
        })
    }
    
}
