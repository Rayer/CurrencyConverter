//
//  PreviewConvertHistory.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/28.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation
import CoreData

func generateModel() -> ConvertHistoryDM {
    return ConvertHistoryDM(id: UUID(), title: "ExampleTitle", url: "https://example.com/it_is_a/very/long_url", fromSymbol: "USD", toSymbol: "TWD", fromAmount: 22.6, fxFee: 0.02, ratio: 31.3)
}
