//
//  SafariExtensionHandler.swift
//  Utilplugin Extension
//
//  Created by Rayer on 2019/10/28.
//  Copyright © 2019 Rayer. All rights reserved.
//

import SafariServices

class SafariExtensionHandler: SFSafariExtensionHandler {
    
    override func messageReceived(withName messageName: String, from page: SFSafariPage, userInfo: [String : Any]?) {
        if messageName == "CCInitialize" {
            CurrencyConverter.shared.loadData { (Error) in
                print("CurrencyConverter Initialized")
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
            //let selected_string = (userInfo?["selected"] as! String)
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if let selected = formatter.number(from: userInfo?["selected"] as? String ?? "") {
                
                let convertFromSym = UserDefaults.standard.value(forKey: "convertFromSym") as! String? ?? "TWD"
                let convertToSym = UserDefaults.standard.value(forKey: "convertToSym") as! String? ?? "TWD"
                let unit = Float32(truncating: selected)
                
                CurrencyConverter.shared.convert(from: convertFromSym, to: convertToSym, unit: unit) { (result, error) in
                    
                    //Add credit card FX rate
                    let fxIndex = UserDefaults.standard.value(forKey: "fxRateIndex") as! Int? ?? 1
                    var fxRate : Float32 = 0.0
                    if fxIndex == 1 {
                        fxRate = 0.015
                    } else if fxIndex == 2 {
                        fxRate = 0.02
                    }
                    
                    let price = result * (1 + fxRate)
                    
                    let formatter = ConvertPasteboardFormatter.init(fromSymbol: convertFromSym, fromAmount: unit, toSymbol: convertToSym, toAmount: price)
                    let formattingIndex = UserDefaults.standard.value(forKey: "FormatIndex") as? Int ?? 0
                    let lastCurrencyExchangeStr = formatter.getFormattedString(formatIndex: formattingIndex)
                    validationHandler(false, lastCurrencyExchangeStr)
                    UserDefaults.standard.set(lastCurrencyExchangeStr as String, forKey: "lastResult")
                    
                    //If everything is fine, store to coredata
                    
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
            if let pasteStr = UserDefaults.standard.value(forKey: "lastResult") as? String {
                let pasteBoard = NSPasteboard.general
                pasteBoard.clearContents()
                pasteBoard.setString(pasteStr, forType: .string)
                NSLog("Copying to pasteboard : \(pasteStr)")
            }
        }
    }
}
