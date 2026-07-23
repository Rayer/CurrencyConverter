//
//  SafariExtensionHandler.swift
//  Utilplugin Extension
//
//  Created by Rayer on 2019/10/28.
//  Copyright © 2019 Rayer. All rights reserved.
//

import SafariServices

class SafariExtensionHandler: SFSafariExtensionHandler {
    private let templateManager = FormatStringDataManager.shared
    
    override func messageReceived(withName messageName: String, from page: SFSafariPage, userInfo: [String : Any]?) {
        if messageName == "CCInitialize" {
            CurrencyConverter.shared.loadData { _ in
            }
        }
    }
    
    override func toolbarItemClicked(in window: SFSafariWindow) {
        // This method will be called when your toolbar item is clicked.
        //NSLog("The extension's toolbar item was clicked")
    }
    
    override func validateToolbarItem(in window: SFSafariWindow, validationHandler: @escaping ((Bool, String) -> Void)) {
        // This is called when Safari's state changed in some way that would require the extension's toolbar item to be validated again.
        validationHandler(true, "")
    }
    
    override func popoverViewController() -> SFSafariExtensionViewController {
        return SafariExtensionViewController.shared
    }
        
    override func validateContextMenuItem(withCommand command: String, in page: SFSafariPage, userInfo: [String : Any]? = nil, validationHandler: @escaping (Bool, String?) -> Void) {
        NSLog("validateContextMenuItem : Command: \(command), userInfo: \(String(describing: userInfo)), validationHandler: \(String(describing: validationHandler))")
        
        if command == "CurrencyExchange" {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if let selected = formatter.number(from: userInfo?["selected"] as? String ?? "") {
                
                let convertFromSym = sharedUserDefaults.value(forKey: "convertFromSym") as? String ?? "TWD"
                let convertToSym = sharedUserDefaults.value(forKey: "convertToSym") as? String ?? "TWD"
                let unit = Float32(truncating: selected)
                
                CurrencyConverter.shared.convertWithStatus(from: convertFromSym, to: convertToSym, unit: unit) { result, status, error in
                    guard error == nil else {
                        validationHandler(true, (error as? RateDataError)?.message ?? status.message)
                        return
                    }
                    
                    //Add credit card FX rate
                    let fxIndex = sharedUserDefaults.value(forKey: "fxRateIndex") as? Int ?? 1
                    let calculation = LegacyContextMenuCalculation.calculate(
                        rawResult: result,
                        unit: unit,
                        sourceCurrency: convertFromSym,
                        targetCurrency: convertToSym,
                        feeIndex: fxIndex
                    )
                    let price = calculation.finalAmount
                    
                    let formatter = ConvertPasteboardFormatter(fromSymbol: convertFromSym, fromAmount: unit, toSymbol: convertToSym, toAmount: price)
                    guard case .success(let template) = self.templateManager.selectedTemplate() else {
                        validationHandler(true, NSLocalizedString("Conversion templates are unavailable.", comment: "Context menu template repository error"))
                        return
                    }
                    let lastCurrencyExchangeStr = formatter.getFormattedString(template: template)
                    guard !lastCurrencyExchangeStr.isEmpty else {
                        validationHandler(true, NSLocalizedString("The selected conversion template is invalid.", comment: "Context menu selected template error"))
                        return
                    }
                    let lastResult = LastResult(resultString: lastCurrencyExchangeStr, convertFrom: convertFromSym, convertTo: convertToSym, units: unit, fxRate: calculation.appliedFXFee, ratio: calculation.ratio)
                    if let encoded = try? LastResultPersistence.encode(lastResult) {
                        sharedUserDefaults.set(encoded, forKey: "lastResult")
                    }
                    let title = LegacyContextMenuPresentation.menuTitle(resultString: lastCurrencyExchangeStr, status: status)
                    validationHandler(false, title)
                    
                }
            } else {
                validationHandler(true, nil)
            }
        }
    }
    
    override func contextMenuItemSelected(withCommand command: String, in page: SFSafariPage, userInfo: [String : Any]? = nil) {
        NSLog("contextMenuItemSelected : Command : \(command), UserInfo : \(String(describing: userInfo))")
        if command == "CurrencyExchange" {
            NSLog("Executing Currency Exchange")
            if let lastResultData = sharedUserDefaults.value(forKey: "lastResult") as? Data {
                guard let lastResult = try? LastResultPersistence.decode(lastResultData) else { return }
                let pasteBoard = NSPasteboard.general
                pasteBoard.clearContents()
                pasteBoard.setString(lastResult.resultString, forType: .string)
                NSLog("Copying to pasteboard : \(lastResult)")

                // Keep the shared Core Data context queue-confined in the extension.
                sharedPersistentContainer.performBackgroundTask { context in
                    let history = ConvertHistory(context: context)
                    history.title = userInfo?["title"] as? String
                    history.url = userInfo?["url"] as? String
                    history.date = Date()
                    history.fromAmount = lastResult.units
                    history.fromSymbol = lastResult.convertFrom
                    history.toSymbol = lastResult.convertTo
                    let values = LegacyConvertHistoryCalculations.normalizedHistoryValues(
                        fromSymbol: lastResult.convertFrom,
                        toSymbol: lastResult.convertTo,
                        fxFeeRate: lastResult.fxRate,
                        ratio: lastResult.ratio
                    )
                    history.fxFee = values.fxFeeRate
                    history.ratio = values.ratio
                    history.id = UUID()
                    try? context.save()
                }
            }
        }
    }
}
