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
        let formatter = FormatStringDataManager.shared
        print("Start fetching FS...")
        formatter.GetAvailableStringEntities().forEach { (fs) in
            print(fs.format_string!)
        }
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
