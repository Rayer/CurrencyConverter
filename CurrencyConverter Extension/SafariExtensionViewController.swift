//
//  SafariExtensionViewController.swift
//  CurrencyConverter Extension
//
//  Created by Rayer on 2019/11/5.
//  Copyright © 2019 Rayer. All rights reserved.
//

import SafariServices

class SafariExtensionViewController: SFSafariExtensionViewController {
    
    static let shared: SafariExtensionViewController = {
        let shared = SafariExtensionViewController()
        shared.preferredContentSize = NSSize(width:320, height:240)
        return shared
    }()

}
