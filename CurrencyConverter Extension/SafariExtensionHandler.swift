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
        // This method will be called when a content script provided by your extension calls safari.extension.dispatchMessage("message").
//        page.getPropertiesWithCompletionHandler { properties in
//            NSLog("The extension received a message (\(messageName)) from a script injected into (\(String(describing: properties?.url))) with userInfo (\(userInfo ?? [:]))")
//        }
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
            if let selected = formatter.number(from: userInfo?["selected"] as! String) {
                let convertFromSym = UserDefaults.standard.value(forKey: "convertFromSym") as! String? ?? "TWD"
                let convertToSym = UserDefaults.standard.value(forKey: "convertToSym") as! String? ?? "TWD"
                CurrencyConverter.shared.convert(from: convertFromSym, to: convertToSym, unit: Float32(truncating: selected)) { (result, error) in
                    validationHandler(false, "\(convertFromSym)=>\(convertToSym) : \(result)")
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
            CurrencyConverter.shared.convert(from: "TWD", to: "JPY", unit: 1.0) { (result, error) in
                let result = ["from": "TWD", "to": "JPY", "unit": 1.0, "converted": result] as [String : Any]
                NSLog("Currency result : \(String(describing: result))")
                page.dispatchMessageToScript(withName: "CurrencyExchangeResult", userInfo: result)
            }
        }
    }
}
