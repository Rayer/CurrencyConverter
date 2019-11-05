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
        shared.preferredContentSize = NSSize(width:320, height:240)
        return shared
    }()
    
    let cc = CurrencyConverter.shared
    
    @IBOutlet weak var convertCB: NSComboBox!
    @IBOutlet weak var convertToCB: NSComboBox!
    
    var convertFromSym : String?
    var convertToSym : String?
    @IBAction func OnSaveBtnClicked(_ sender: NSButton) {
    }
    
    override func viewDidLoad() {
        let cc = CurrencyConverter.shared
        cc.getSymbols { (symbols, error) in
            self.symbols = symbols?.sorted()
            self.convertToCB.dataSource = self
            self.convertCB.dataSource = self
            self.convertToCB.delegate = self
            self.convertCB.delegate = self
            self.convertFromSym = UserDefaults.standard.value(forKey: "convertFromSym") as! String?
            self.convertToSym = UserDefaults.standard.value(forKey: "convertToSym") as! String?
            self.convertCB.reloadData()
            self.convertToCB.reloadData()
            //self.convertCB.selectItem(at: self.symbols!.firstIndex(of: self.convertFromSym!)!)
            //self.convertToCB.selectItem(at: self.symbols!.firstIndex(of: self.convertToSym!)!)
        }
    }
    
    func numberOfItems(in comboBox: NSComboBox) -> Int {
        return symbols!.count
    }

    func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
        return symbols![index]
    }
    
    func comboBoxSelectionDidChange(_ notification: Notification) {
        let combobox = (notification.object as? NSComboBox)!
        NSLog("selection did change! \(notification) : \(String(describing: combobox.identifier?.rawValue))")
        
        if combobox.identifier?.rawValue == "convertFrom" {
            convertFromSym = symbols![combobox.indexOfSelectedItem]
        } else if combobox.identifier?.rawValue == "convertTo" {
            convertToSym = symbols![combobox.indexOfSelectedItem]
        }
        NSLog("Now ConvertFrom : \(String(describing: convertFromSym)) and ConvertTo : \(String(describing: convertToSym))")
        let defaults = UserDefaults.standard
        defaults.set(convertFromSym, forKey: "convertFromSym")
        defaults.set(convertToSym, forKey: "convertToSym")
        
    }
}
