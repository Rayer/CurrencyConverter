//
//  SafariExtensionViewController.swift
//  Utilplugin Extension
//
//  Created by Rayer on 2019/10/28.
//  Copyright © 2019 Rayer. All rights reserved.
//

import SafariServices

class SafariExtensionViewController: SFSafariExtensionViewController, NSComboBoxDataSource, NSComboBoxDelegate {
    
    var symbols : [String]?
    
    static let shared: SafariExtensionViewController = {
        let shared = SafariExtensionViewController()
        shared.preferredContentSize = NSSize(width:330, height:120)
        return shared
    }()
    
    let cc = CurrencyConverter.shared
    
    @IBOutlet weak var convertListBtn: NSPopUpButton!
    @IBOutlet weak var convertToListBtn: NSPopUpButton!
    
    var convertFromSym : String?
    var convertToSym : String?
    
    var creditCardFeeOpt: Bool?
    var creditCardFeeValue: Float?

    override func viewDidLoad() {
        let cc = CurrencyConverter.shared
        cc.getSymbols { (symbols, error) in
            self.symbols = symbols?.sorted()
            self.convertListBtn.removeAllItems()
            self.convertToListBtn.removeAllItems()
            self.convertListBtn.addItems(withTitles: self.symbols!)
            self.convertToListBtn.addItems(withTitles: self.symbols!)
            self.convertFromSym = UserDefaults.standard.value(forKey: "convertFromSym") as! String? ?? "USD"
            self.convertToSym = UserDefaults.standard.value(forKey: "convertToSym") as! String? ?? "TWD"
            self.convertListBtn.selectItem(at: self.symbols!.firstIndex(of: self.convertFromSym ?? "USD") ?? 0)
            self.convertToListBtn.selectItem(at: self.symbols!.firstIndex(of: self.convertToSym ?? "TWD") ?? 0)
        }
    }
    @IBAction func OnConvertFromClicked(_ sender: NSPopUpButton) {
        let selected = symbols![sender.indexOfSelectedItem]
        NSLog("ConvertFrom value selected : \(selected)")
        UserDefaults.standard.set(selected as String, forKey: "convertFromSym")
        convertFromSym = selected
    }
    
    @IBAction func OnConvertToClicked(_ sender: NSPopUpButton) {
        let selected = symbols![sender.indexOfSelectedItem]
        NSLog("ConvertTo value selected : \(selected)")
        UserDefaults.standard.set(selected as String, forKey: "convertToSym")
        convertToSym = selected
    }
}
