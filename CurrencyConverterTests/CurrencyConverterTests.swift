//
//  CurrencyConverterTests.swift
//  CurrencyConverterTests
//
//  Created by Rayer on 2019/11/5.
//  Copyright © 2019 Rayer. All rights reserved.
//

import XCTest
import CoreData
@testable import CurrencyConverter

class CurrencyConverterTests: XCTestCase {
    
    
    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testFormatter() {
        let manager = FormatStringDataManager(context: inMemoryContext())
        XCTAssertEqual(
            manager.PreviewString(string: "${from_symbol} ${from_amount} => ${to_symbol} ${to_amount}"),
            "TWD 2 => USD 62.14"
        )
    }

    func testBaselineSmoke() {
        let converter = CurrencyConverter(context: nil)
        converter.currencyRateEntity = CurrencyRateEntity(
            base: "EUR",
            date: "2026-07-18",
            rates: ["TWD": 4.0, "USD": 1.0],
            fetched_localtime: Date(),
            timestamp: 0
        )

        let expectation = expectation(description: "currency conversion")
        converter.convert(from: "TWD", to: "USD", unit: 2.0) { amount, error in
            XCTAssertNil(error)
            XCTAssertEqual(amount, 0.5, accuracy: 0.0001)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    private func inMemoryContext() -> NSManagedObjectContext {
        let model = NSManagedObjectModel.mergedModel(from: [Bundle(for: CurrencyConverterTests.self)])!
        let container = NSPersistentContainer(name: "CurrencyExchangeRate", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        let loadExpectation = expectation(description: "Persistent stores load")
        container.loadPersistentStores { _, error in
            loadError = error
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 1.0)
        XCTAssertNil(loadError)

        let seed = FormatString(context: container.viewContext)
        seed.id = UUID()
        seed.date = Date()
        seed.format_string = "seed"
        try! container.viewContext.save()
        return container.viewContext
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
