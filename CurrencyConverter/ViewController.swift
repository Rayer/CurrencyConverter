//
//  ViewController.swift
//  CurrencyConverter
//
//  Created by Rayer on 2019/11/5.
//  Copyright © 2019 Rayer. All rights reserved.
//

import Cocoa
import SafariServices.SFSafariApplication

class ViewController: NSViewController {

    @IBOutlet var appNameLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.appNameLabel.stringValue = "CurrencyConverter";
    }
    
    @IBAction func openSafariExtensionPreferences(_ sender: AnyObject?) {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: "com.rayer.CurrencyConverter-Extension") { error in
            if let _ = error {
                // Insert code to inform the user that something went wrong.

            }
        }
    }

}
