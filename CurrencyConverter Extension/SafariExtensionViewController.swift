//
//  SafariExtensionViewController.swift
//  Utilplugin Extension
//
//  Created by Rayer on 2019/10/28.
//  Copyright © 2019 Rayer. All rights reserved.
//

import SafariServices

class SafariExtensionViewController: SFSafariExtensionViewController {
    
    var symbols : [String]?
    
    static let shared: SafariExtensionViewController = {
        let shared = SafariExtensionViewController()
        shared.preferredContentSize = NSSize(width:330, height:150)
        return shared
    }()
    
    let cc = CurrencyConverter.shared
    private let templateManager = FormatStringDataManager.shared
    
    @IBOutlet weak var convertListBtn: NSPopUpButton!
    @IBOutlet weak var convertToListBtn: NSPopUpButton!
    
    @IBOutlet weak var formatterListBtn: NSPopUpButton!
    @IBOutlet weak var ratesText: NSTextField!
    @IBOutlet weak var statusText: NSTextField!
    
    var convertFromSym : String?
    var convertToSym : String?
    
    var creditCardFeeOpt: Bool?
    var creditCardFeeValue: Float?

    @IBOutlet weak var fxRateBtn0: NSButton!
    @IBOutlet weak var fxRateBtn15: NSButton!
    @IBOutlet weak var fxRateBtn2: NSButton!
    @IBOutlet weak var baseRateValueField: NSTextField!
    
    var fxRateBtnList : [NSButton] = []
    private var formatTemplates: [ConversionTemplate] = []
    private var formatterRequestGeneration: UInt64 = 0
    
    override func viewDidLoad() {
        
        fxRateBtnList = [fxRateBtn0, fxRateBtn15, fxRateBtn2]
        let fxRateIndex = sharedUserDefaults.value(forKey: "fxRateIndex") as? Int ?? 1
        fxRateBtnList.forEach { $0.state = .off }
        fxRateBtnList[fxRateIndex].state = .on
        
        let cc = CurrencyConverter.shared
        cc.getSymbols { (symbols, error) in
            DispatchQueue.main.async {
                self.statusText.stringValue = error.map { ($0 as? RateDataError)?.message ?? "Exchange rates unavailable." } ?? cc.rateDataStatus.message
                guard let symbols, !symbols.isEmpty else { return }
                self.symbols = symbols.sorted()
                self.convertListBtn.removeAllItems()
                self.convertToListBtn.removeAllItems()
                self.convertListBtn.addItems(withTitles: self.symbols ?? [])
                self.convertToListBtn.addItems(withTitles: self.symbols ?? [])
                self.convertFromSym = sharedUserDefaults.value(forKey: "convertFromSym") as? String ?? "USD"
                self.convertToSym = sharedUserDefaults.value(forKey: "convertToSym") as? String ?? "TWD"
                self.convertListBtn.selectItem(at: self.symbols?.firstIndex(of: self.convertFromSym ?? "USD") ?? 0)
                self.convertToListBtn.selectItem(at: self.symbols?.firstIndex(of: self.convertToSym ?? "TWD") ?? 0)
                self.baseRateValueField.floatValue = sharedUserDefaults.value(forKey: "baseRateValue") as? Float32 ?? 1.0
                self.UpdateFormatters()
                self.UpdateRates()
            }
        }
    }

    @IBAction func OnBaseRateValueChanged(_ sender: NSTextField) {
        let baseRateValue = sender.floatValue
        sharedUserDefaults.set(baseRateValue as Float32, forKey: "baseRateValue")
        UpdateRates()
    }
    
    @IBAction func OnConvertFromClicked(_ sender: NSPopUpButton) {
        guard let symbols, symbols.indices.contains(sender.indexOfSelectedItem) else { return }
        let selected = symbols[sender.indexOfSelectedItem]
        NSLog("ConvertFrom value selected : \(selected)")
        sharedUserDefaults.set(selected as String, forKey: "convertFromSym")
        convertFromSym = selected
        UpdateRates()
        UpdateFormatters()
    }
    
    @IBAction func OnConvertToClicked(_ sender: NSPopUpButton) {
        guard let symbols, symbols.indices.contains(sender.indexOfSelectedItem) else { return }
        let selected = symbols[sender.indexOfSelectedItem]
        NSLog("ConvertTo value selected : \(selected)")
        sharedUserDefaults.set(selected as String, forKey: "convertToSym")
        convertToSym = selected
        UpdateRates()
        UpdateFormatters()
    }
    
    @IBAction func OnFormatBtnClicked(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard formatTemplates.indices.contains(index) else { return }
        guard case .success(let selected) = templateManager.select(id: formatTemplates[index].id) else { return }
        if let legacyIndex = ConversionTemplateCatalog.defaultIDs.firstIndex(of: selected.id) {
            sharedUserDefaults.set(legacyIndex, forKey: ConversionTemplateSelection.legacyFormatIndexKey)
        }
    }
    
    @IBAction func OnFxRateBtnClicked(_ sender: NSButton) {
        let index = self.fxRateBtnList.firstIndex(of: sender)
        sharedUserDefaults.set(index, forKey: "fxRateIndex")
    }
    
    func UpdateRates() {
        let cc = CurrencyConverter.shared
        guard let convertFromSym, let convertToSym else { return }
        cc.convertWithStatus(from: convertFromSym, to: convertToSym, unit: baseRateValueField.floatValue) { result, status, error in
            DispatchQueue.main.async {
                self.statusText.stringValue = (error as? RateDataError)?.message ?? status.message
                guard error == nil else {
                    return
                }
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.alwaysShowsDecimalSeparator = true
                self.ratesText.stringValue = ":\(formatter.string(for: result) ?? "—")"
            }
        }
    }
    
    func UpdateFormatters() {
        guard let convertFromSym, let convertToSym else { return }
        formatterRequestGeneration &+= 1
        let requestGeneration = formatterRequestGeneration
        self.formatterListBtn.removeAllItems()
        self.formatTemplates = []
        guard case .success(let templates) = templateManager.availableTemplates() else {
            self.statusText.stringValue = NSLocalizedString("Conversion templates are unavailable.", comment: "Extension template repository error")
            return
        }
        self.formatTemplates = templates
        let selectedID: UUID? = {
            guard case .success(let template) = templateManager.selectedTemplate() else { return nil }
            return template.id
        }()
        cc.convertWithStatus(from: convertFromSym, to: convertToSym, unit: 1) { result, status, error in
            DispatchQueue.main.async {
                guard requestGeneration == self.formatterRequestGeneration else { return }
                self.statusText.stringValue = (error as? RateDataError)?.message ?? status.message
                guard error == nil else {
                  return
                }
                let cpf = ConvertPasteboardFormatter(fromSymbol: convertFromSym, fromAmount: 1, toSymbol: convertToSym, toAmount: result)
                let titles = cpf.getAllFormattedStrings(templates: templates)
                self.formatterListBtn.addItems(withTitles: titles)
                self.formatTemplates = templates
                let selectedIndex = selectedID.flatMap { id in templates.firstIndex { $0.id == id } } ?? 0
                self.formatterListBtn.selectItem(at: selectedIndex)
            }
        }
    }
}
