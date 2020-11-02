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

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 5.0) {
                    Picker(selection: self.$model.creditCardType, label: Text("Credit Card Type")){
                        Text("Cash-back based").tag(CreditCardType.CashBack)
                        Text("Mileage or point based").tag(CreditCardType.Mileage)
                    }
                    .pickerStyle(RadioGroupPickerStyle())
                    .padding()
                    
                    
                    UnifiedView(title: "Card Profile Name", description: "Card Indentifier, must be unique", bindedValue: self.$model.creditCardName, is2liner: false).padding()
                    
                    Picker(selection: self.$model.clearinghouseCurrency, label: Text("Clearinghouse Currency")){
                        ForEach(self.model.clearinghouseCurrencyList, id:\.self) { (symbol) in
                            Text("\(CountryCurrency.shared.getFlag(symbol: symbol)) \(symbol)").tag(symbol)
                        }
                    }.padding()
                    
                    Group {
                        if self.model.creditCardType == CreditCardType.CashBack {
                            UnifiedView(title: "Domestic Cash-Back Rate", description: "Cash Back rate while applying domestic currency", errorMessage: "Value must be a number", bindedValue: self.$model.cbDomesticRate, isValid: self.model.cbDomesticRateValidate, is2liner: true,                           textFieldWidth: 80)

                            UnifiedView(title: "International Cash-Back Rate", description: "Cash Back rate while applying foreign currency", errorMessage: "Value must be a number", bindedValue: self.$model.cbInternationalRate, isValid: self.model.cbInternationalRateValidate, is2liner: true,                           textFieldWidth: 80)

                            UnifiedView(title: "FX Rate", description: "International FX Rate", errorMessage: "Must be a number and between 0 and 100", bindedValue: self.$model.FxRate, isValid: self.model.FxRateValidate, is2liner: true,
                                textFieldWidth: 80)
                            
                            
                        } else if self.model.creditCardType == CreditCardType.Mileage {
                            
                            UnifiedView(title: "Mileage/Point domestic rate", description: "Mileage(Point) rate while applying domestic currency", errorMessage: "Value must be a number", bindedValue: self.$model.mDomesticRate, isValid: self.model.mDomesticRateValidate, is2liner: true,
                                textFieldWidth: 80)
                            UnifiedView(title: "Mileage / Point international rate", description: "Mileage(Point) ratewhile applying international currency", errorMessage: "Value must be a number", bindedValue: self.$model.mInternationalRate, isValid: self.model.mInternationalRateValidate, is2liner: true,
                                textFieldWidth: 80)

                            UnifiedView(title: "FX Rate", description: "International FX Rate", errorMessage: "Must be a number and between 0 and 100", bindedValue: self.$model.FxRate, isValid: self.model.FxRateValidate, is2liner: true,
                                textFieldWidth: 80)
                            UnifiedView(title: "Estimated Mileage(point) value", description: "Estimated Mileage(Point) value per point", errorMessage: "Must be a number!", bindedValue: self.$model.mEstimatedValuePerMile, isValid: self.model.mEstimatedValuePerMileValid, is2liner: true,                           textFieldWidth: 80)

                        }
                    }
                    .padding(.horizontal)
                }
                
                List(self.model.savedProfile, id: \.self) { (profile) in
                    Text(profile.name!)
                        .font(.caption)
                        .fontWeight(.light)
                        .onTapGesture {
                            model.loadProfile(profile)
                        }
                        .foregroundColor(profile.name! == self.model.creditCardName ? .red : .none)
                }
            }
            
            Spacer()

            HStack {
                
                Button(model.isUpdateCard ? "Update Card" : "Add Card") {
                    model.persist()
                }.padding()
                
                Button("Delete Card") {
                    model.deleteByCardName(model.creditCardName)
                }.disabled(!model.isUpdateCard)
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
    var is2liner = false
    var textFieldWidth : CGFloat?
    
    init(title: String, description: String, bindedValue: Binding<String>, is2liner: Bool) {
        self.title = title
        self.description = description
        self.bindedValue = bindedValue
        self.is2liner = is2liner
    }
    
    init(title: String, description: String, errorMessage: String, bindedValue: Binding<String>, isValid: Bool, is2liner: Bool, textFieldWidth: CGFloat? = nil) {
        self.title = title
        self.description = description
        self.bindedValue = bindedValue
        self.errorMessage = errorMessage
        self.isValid = isValid
        self.is2liner = is2liner
        self.textFieldWidth = textFieldWidth
    }
    
    var body: some View {
        VStack (alignment: .leading, spacing: 2, content: {
            if is2liner {
                HStack(alignment: .top) {
                    Text(title)
                    if let width = self.textFieldWidth {
                        Spacer()
                        TextField(description, text: bindedValue)
                            .frame(width: width, alignment: .trailing)
                    } else {
                        TextField(description, text: bindedValue)
                    }
                }
            } else {
                Text(title)
                TextField(description, text: bindedValue)
            }

            if !self.isValid {
                Text(errorMessage)
                    .foregroundColor(.red)
            } else {
                Text("")
            }
        })
    }
    
}
