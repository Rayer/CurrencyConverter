//
//  SafariExtensionHandler.swift
//  Utilplugin Extension
//
//  Created by Rayer on 2019/10/28.
//  Copyright © 2019 Rayer. All rights reserved.
//

import CoreData
import SafariServices

class SafariExtensionHandler: SFSafariExtensionHandler {
    private let templateManager = FormatStringDataManager.shared
    private let pendingResults = LatestRequestGate<ContextMenuRequestKey, LastResult>()
    
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
        let response = OneShot<(Bool, String?)> { validationHandler($0.0, $0.1) }
        guard command == "CurrencyExchange" else {
            response.call((true, nil))
            return
        }
        let requestKey = ContextMenuRequestKey(page: page, userInfo: userInfo)
        let requestGeneration = pendingResults.begin(for: requestKey)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if let selected = formatter.number(from: userInfo?["selected"] as? String ?? "") {
                
            let convertFromSym = sharedUserDefaults.value(forKey: "convertFromSym") as? String ?? "TWD"
            let convertToSym = sharedUserDefaults.value(forKey: "convertToSym") as? String ?? "TWD"
            let unit = Float32(truncating: selected)
                
            CurrencyConverter.shared.convertWithStatus(from: convertFromSym, to: convertToSym, unit: unit) { result, status, error in
                guard error == nil else {
                    self.pendingResults.invalidate(requestGeneration)
                    response.call((true, (error as? RateDataError)?.message ?? status.message))
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
                    self.pendingResults.invalidate(requestGeneration)
                    response.call((true, NSLocalizedString("Conversion templates are unavailable.", comment: "Context menu template repository error")))
                    return
                }
                let lastCurrencyExchangeStr = formatter.getFormattedString(template: template)
                guard !lastCurrencyExchangeStr.isEmpty else {
                    self.pendingResults.invalidate(requestGeneration)
                    response.call((true, NSLocalizedString("The selected conversion template is invalid.", comment: "Context menu selected template error")))
                    return
                }
                let lastResult = LastResult(resultString: lastCurrencyExchangeStr, convertFrom: convertFromSym, convertTo: convertToSym, units: unit, fxRate: calculation.appliedFXFee, ratio: calculation.ratio)
                guard self.pendingResults.publish(lastResult, generation: requestGeneration) else {
                    response.call((true, nil))
                    return
                }
                let title = LegacyContextMenuPresentation.menuTitle(resultString: lastCurrencyExchangeStr, status: status)
                response.call((false, title))
            }
        } else {
            pendingResults.invalidate(requestGeneration)
            response.call((true, nil))
        }
    }
    
    override func contextMenuItemSelected(withCommand command: String, in page: SFSafariPage, userInfo: [String : Any]? = nil) {
        if command == "CurrencyExchange" {
            if let lastResult = pendingResults.consume(for: ContextMenuRequestKey(page: page, userInfo: userInfo)) {
                guard persistHistory(lastResult: lastResult, userInfo: userInfo) else { return }
                let pasteBoard = NSPasteboard.general
                pasteBoard.clearContents()
                guard pasteBoard.setString(lastResult.resultString, forType: .string) else {
                    // History intentionally records the user action even when the system pasteboard rejects publication.
                    NSLog("CurrencyConverter pasteboard publication failed")
                    return
                }
            }
        }
    }

    private func persistHistory(lastResult: LastResult, userInfo: [String: Any]?) -> Bool {
        let context = sharedPersistentContainer.newBackgroundContext()
        context.undoManager = nil
        var saved = false
        context.performAndWait {
            guard let history = NSEntityDescription.insertNewObject(
                forEntityName: "ConvertHistory",
                into: context
            ) as? ConvertHistory else { return }
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
            do {
                try context.save()
                saved = true
            } catch {
                context.rollback()
                NSLog("CurrencyConverter history save failed")
            }
        }
        return saved
    }
}

private struct ContextMenuRequestKey: Equatable {
    let pageIdentifier: ObjectIdentifier
    let title: String?
    let url: String?

    init(page: SFSafariPage, userInfo: [String: Any]?) {
        pageIdentifier = ObjectIdentifier(page)
        title = userInfo?["title"] as? String
        url = userInfo?["url"] as? String
    }
}
