//
//  CurrencyConverterTests.swift
//  CurrencyConverterTests
//
//  Created by Rayer on 2019/11/5.
//  Copyright © 2019 Rayer. All rights reserved.
//

import XCTest
@testable import CurrencyConverter

class CurrencyConverterTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testFormatter() {
        let formatter = ConvertPasteboardFormatter(fromSymbol: "USD", fromAmount: 1, toSymbol: "JPY", toAmount: 110)
        for x in 0...3 {
            print(formatter.getFormattedString(formatIndex: x))
        }
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
