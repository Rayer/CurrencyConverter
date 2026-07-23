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
        prepareResult(userInfo: userInfo) { preparation in
            switch preparation {
            case .success(let prepared):
                let title = LegacyContextMenuPresentation.menuTitle(
                    resultString: prepared.lastResult.resultString,
                    status: prepared.status
                )
                response.call((false, title))
            case .failure(let message):
                response.call((true, message))
            }
        }
    }
    
    override func contextMenuItemSelected(withCommand command: String, in page: SFSafariPage, userInfo: [String : Any]? = nil) {
        guard command == "CurrencyExchange" else { return }
        prepareResult(userInfo: userInfo) { preparation in
            guard case .success(let prepared) = preparation else {
                NSLog("CurrencyConverter context-menu preparation failed")
                return
            }
            DispatchQueue.main.async {
                guard self.persistHistory(lastResult: prepared.lastResult, userInfo: userInfo) else { return }
                let pasteBoard = NSPasteboard.general
                pasteBoard.clearContents()
                guard pasteBoard.setString(prepared.lastResult.resultString, forType: .string) else {
                    // History intentionally records the user action even when the system pasteboard rejects publication.
                    NSLog("CurrencyConverter pasteboard publication failed")
                    return
                }
            }
        }
    }

    private func prepareResult(
        userInfo: [String: Any]?,
        completion: @escaping (ContextMenuPreparation) -> Void
    ) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        guard let selected = formatter.number(from: userInfo?["selected"] as? String ?? "") else {
            completion(.failure(nil))
            return
        }

        let convertFromSym = sharedUserDefaults.value(forKey: "convertFromSym") as? String ?? "TWD"
        let convertToSym = sharedUserDefaults.value(forKey: "convertToSym") as? String ?? "TWD"
        let unit = Float32(truncating: selected)

        CurrencyConverter.shared.convertWithStatus(from: convertFromSym, to: convertToSym, unit: unit) { result, status, error in
            guard error == nil else {
                completion(.failure((error as? RateDataError)?.message ?? status.message))
                return
            }

            let fxIndex = sharedUserDefaults.value(forKey: "fxRateIndex") as? Int ?? 1
            let calculation = LegacyContextMenuCalculation.calculate(
                rawResult: result,
                unit: unit,
                sourceCurrency: convertFromSym,
                targetCurrency: convertToSym,
                feeIndex: fxIndex
            )
            let formatter = ConvertPasteboardFormatter(
                fromSymbol: convertFromSym,
                fromAmount: unit,
                toSymbol: convertToSym,
                toAmount: calculation.finalAmount
            )
            guard case .success(let template) = self.templateManager.selectedTemplate() else {
                completion(.failure(NSLocalizedString("Conversion templates are unavailable.", comment: "Context menu template repository error")))
                return
            }
            let resultString = formatter.getFormattedString(template: template)
            guard !resultString.isEmpty else {
                completion(.failure(NSLocalizedString("The selected conversion template is invalid.", comment: "Context menu selected template error")))
                return
            }
            let lastResult = LastResult(
                resultString: resultString,
                convertFrom: convertFromSym,
                convertTo: convertToSym,
                units: unit,
                fxRate: calculation.appliedFXFee,
                ratio: calculation.ratio
            )
            completion(.success(ContextMenuPreparedResult(lastResult: lastResult, status: status)))
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

private struct ContextMenuPreparedResult {
    let lastResult: LastResult
    let status: RateDataStatus
}

private enum ContextMenuPreparation {
    case success(ContextMenuPreparedResult)
    case failure(String?)
}
