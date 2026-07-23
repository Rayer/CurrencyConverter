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
                    Picker(selection: self.$model.creditCardType, label: Text(NSLocalizedString("Credit Card Type", comment: "Credit card type picker label"))){
                        Text(NSLocalizedString("Cash-back based", comment: "Credit card type option")).tag(CreditCardType.CashBack)
                        Text(NSLocalizedString("Mileage or point based", comment: "Credit card type option")).tag(CreditCardType.Mileage)
                    }
                    .pickerStyle(RadioGroupPickerStyle())
                    .padding()
                    
                    UnifiedView(
                        title: NSLocalizedString("Card Profile Name", comment: "Credit card editor title"),
                        description: NSLocalizedString("Card Indentifier, must be unique and between length of 1 to 24", comment: "Credit card editor description"),
                        errorMessage: NSLocalizedString("Invalid name, it must be between 1-24", comment: "Credit card editor validation"),
                        bindedValue: self.$model.creditCardName,
                        isValid: self.model.creditCardNameValid,
                        is2liner: false
                    ).padding()
                    
                    Picker(selection: self.$model.clearinghouseCurrency, label: Text(NSLocalizedString("Clearinghouse Currency", comment: "Credit card editor label"))){
                        ForEach(CurrencyPickerPresentation.items(for: self.model.clearinghouseCurrencyList, flagProvider: { CountryCurrency.shared.getFlag(symbol: $0) }), id: \.code) { item in
                            Text(item.label)
                            .accessibility(label: Text(item.accessibilityLabel))
                            .tag(item.code)
                        }
                    }.padding()
                    
                    Group {
                        if self.model.creditCardType == CreditCardType.CashBack {
                            UnifiedView(
                                title: NSLocalizedString("Domestic Cash-Back Rate", comment: "Credit card editor title"),
                                description: NSLocalizedString("Cash Back rate while applying domestic currency", comment: "Credit card editor description"),
                                errorMessage: NSLocalizedString("Value must be a number", comment: "Credit card editor validation"),
                                bindedValue: self.$model.cbDomesticRate,
                                isValid: self.model.cbDomesticRateValidate,
                                is2liner: true,
                                textFieldWidth: 80,
                                withSuffix: "%"
                            )

                            UnifiedView(
                                title: NSLocalizedString("International Cash-Back Rate", comment: "Credit card editor title"),
                                description: NSLocalizedString("Cash Back rate while applying foreign currency", comment: "Credit card editor description"),
                                errorMessage: NSLocalizedString("Value must be a number", comment: "Credit card editor validation"),
                                bindedValue: self.$model.cbInternationalRate,
                                isValid: self.model.cbInternationalRateValidate,
                                is2liner: true,
                                textFieldWidth: 80,
                                withSuffix: "%"
                            )

                            UnifiedView(
                                title: NSLocalizedString("FX Rate", comment: "Credit card editor title"),
                                description: NSLocalizedString("International FX Rate", comment: "Credit card editor description"),
                                errorMessage: NSLocalizedString("Must be a number and between 0 and 100", comment: "Credit card editor validation"),
                                bindedValue: self.$model.FxRate,
                                isValid: self.model.FxRateValidate,
                                is2liner: true,
                                textFieldWidth: 80,
                                withSuffix: "%"
                            )
                            
                            
                        } else if self.model.creditCardType == CreditCardType.Mileage {
                            
                            Picker(selection: $model.mConvertType, label: Text(NSLocalizedString("Convert Type", comment: "Credit card editor label")), content:{
                                Text(NSLocalizedString("Dollars per point", comment: "Credit card editor option")).tag(0)
                                Text(NSLocalizedString("Points per dollar", comment: "Credit card editor option")).tag(1)
                            })
                            .pickerStyle(SegmentedPickerStyle())

                            
                            UnifiedView(
                                title: NSLocalizedString("Mileage/Point domestic rate", comment: "Credit card editor title"),
                                description: NSLocalizedString("Mileage(Point) rate while applying domestic currency", comment: "Credit card editor description"),
                                errorMessage: NSLocalizedString("Value must be a number", comment: "Credit card editor validation"),
                                bindedValue: self.$model.mDomesticRate,
                                isValid: self.model.mDomesticRateValidate,
                                is2liner: true,
                                textFieldWidth: 80,
                                withSuffix: model.mConvertType == 0
                                    ? NSLocalizedString("per Point", comment: "Mileage reward unit label")
                                    : NSLocalizedString("per Dollar", comment: "Mileage reward unit label")
                            )
                            UnifiedView(
                                title: NSLocalizedString("Mileage / Point international rate", comment: "Credit card editor title"),
                                description: NSLocalizedString("Mileage(Point) ratewhile applying international currency", comment: "Credit card editor description"),
                                errorMessage: NSLocalizedString("Value must be a number", comment: "Credit card editor validation"),
                                bindedValue: self.$model.mInternationalRate,
                                isValid: self.model.mInternationalRateValidate,
                                is2liner: true,
                                textFieldWidth: 80,
                                withSuffix: model.mConvertType == 0
                                    ? NSLocalizedString("per Point", comment: "Mileage reward unit label")
                                    : NSLocalizedString("per Dollar", comment: "Mileage reward unit label")
                            )

                            UnifiedView(
                                title: NSLocalizedString("FX Rate", comment: "Credit card editor title"),
                                description: NSLocalizedString("International FX Rate", comment: "Credit card editor description"),
                                errorMessage: NSLocalizedString("Must be a number and between 0 and 100", comment: "Credit card editor validation"),
                                bindedValue: self.$model.FxRate,
                                isValid: self.model.FxRateValidate,
                                is2liner: true,
                                textFieldWidth: 80,
                                withSuffix: "%"
                            )
                            UnifiedView(
                                title: NSLocalizedString("Estimated Mileage(point) value", comment: "Credit card editor title"),
                                description: NSLocalizedString("Estimated Mileage(Point) value per point", comment: "Credit card editor description"),
                                errorMessage: NSLocalizedString("Must be a number!", comment: "Credit card editor validation"),
                                bindedValue: self.$model.mEstimatedValuePerMile,
                                isValid: self.model.mEstimatedValuePerMileValid,
                                is2liner: true,
                                textFieldWidth: 80,
                                withSuffix: " "
                            )

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
                        .frame(minWidth: 100, idealWidth: 100, maxWidth: .infinity)
                }
            }
            
            Spacer()

            HStack {
                
                Button(model.isUpdateCard
                    ? NSLocalizedString("Update Card", comment: "Credit card action")
                    : NSLocalizedString("Add Card", comment: "Credit card action")
                ) {
                    model.persist()
                }.padding()
                
                Button(NSLocalizedString("Delete Card", comment: "Credit card action")) {
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
    var suffix : String?
    
    init(title: String, description: String, bindedValue: Binding<String>, is2liner: Bool) {
        self.title = title
        self.description = description
        self.bindedValue = bindedValue
        self.is2liner = is2liner
    }
    
    init(title: String, description: String, errorMessage: String, bindedValue: Binding<String>, isValid: Bool, is2liner: Bool, textFieldWidth: CGFloat? = nil, withSuffix: String? = nil) {
        self.title = title
        self.description = description
        self.bindedValue = bindedValue
        self.errorMessage = errorMessage
        self.isValid = isValid
        self.is2liner = is2liner
        self.textFieldWidth = textFieldWidth
        self.suffix = withSuffix
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
                    if let s = self.suffix {
                        Text(s)
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
