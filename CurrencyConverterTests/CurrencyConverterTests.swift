//
//  CurrencyConverterTests.swift
//  CurrencyConverterTests
//
//  Created by Rayer on 2019/11/5.
//  Copyright © 2019 Rayer. All rights reserved.
//

import XCTest
import CoreData
import Foundation
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

    func testCCS29_LocalizationFilesContainSameKeysAndPlaceholderStructure() throws {
        let root = projectRoot()
        let appLocalizationEn = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter/en.lproj/Localizable.strings"))
        let appLocalizationZh = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter/zh-Hant.lproj/Localizable.strings"))
        let extensionLocalizationEn = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter Extension/en.lproj/Localizable.strings"))
        let extensionLocalizationZh = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter Extension/zh-Hant.lproj/Localizable.strings"))
        let appInfoPlistEn = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter/en.lproj/InfoPlist.strings"))
        let appInfoPlistZh = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter/zh-Hant.lproj/InfoPlist.strings"))
        let extensionInfoPlistEn = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter Extension/en.lproj/InfoPlist.strings"))
        let extensionInfoPlistZh = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter Extension/zh-Hant.lproj/InfoPlist.strings"))
        let appXibLocale = try? loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter/en.lproj/Main.strings"))
        let extensionXibEn = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter Extension/en.lproj/SafariExtensionViewController.strings"))
        let extensionXibZh = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter Extension/zh-Hant.lproj/SafariExtensionViewController.strings"))

        XCTAssertGreaterThan(appLocalizationEn.count, 0)
        XCTAssertGreaterThan(extensionLocalizationEn.count, 0)
        assertLocaleParity(label: "App Localizable.strings", source: appLocalizationEn, target: appLocalizationZh)
        assertLocaleParity(label: "Extension Localizable.strings", source: extensionLocalizationEn, target: extensionLocalizationZh)
        assertLocaleParity(label: "App InfoPlist.strings", source: appInfoPlistEn, target: appInfoPlistZh, expectLocalizedTarget: true)
        assertLocaleParity(label: "Extension InfoPlist.strings", source: extensionInfoPlistEn, target: extensionInfoPlistZh, expectLocalizedTarget: true)
        assertLocaleParity(label: "Extension XIB strings", source: extensionXibEn, target: extensionXibZh, expectLocalizedTarget: true)
        XCTAssertNil(appXibLocale)
    }

    func testCCS29_LocalizedCallsitesAreFullyBackedByFallbackLocale() throws {
        let root = projectRoot()
        let sourceKeys = try collectLocalizedKeys(in: [
            root.appendingPathComponent("CurrencyConverter"),
            root.appendingPathComponent("Shared"),
            root.appendingPathComponent("CurrencyConverter Extension")
        ])
        let appLocalizationEn = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter/en.lproj/Localizable.strings"))

        XCTAssertGreaterThan(sourceKeys.count, 0)
        for key in sourceKeys {
            XCTAssertTrue(
                appLocalizationEn.keys.contains(key),
                "Missing fallback key for source callsite: \(key)"
            )
        }
    }

    func testCCS29_zhHantLocalizedValuesAreNotRawKeys() throws {
        let root = projectRoot()
        let appLocalizationZh = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter/zh-Hant.lproj/Localizable.strings"))
        let extensionLocalizationZh = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter Extension/zh-Hant.lproj/Localizable.strings"))
        let extensionXibZh = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter Extension/zh-Hant.lproj/SafariExtensionViewController.strings"))

        assertAllValuesAreTranslated(source: "App zh-Hant Localizable.strings", values: appLocalizationZh)
        assertAllValuesAreTranslated(source: "Extension zh-Hant Localizable.strings", values: extensionLocalizationZh)
        assertAllValuesAreTranslated(source: "Extension zh-Hant SafariExtensionViewController.strings", values: extensionXibZh)
    }

    func testCCS29_TargetedInventoryPathsAreLocalizedAndParitySafe() throws {
        let root = projectRoot()
        let appLocalizationEn = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter/en.lproj/Localizable.strings"))
        let appLocalizationZh = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter/zh-Hant.lproj/Localizable.strings"))
        let extensionLocalizationEn = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter Extension/en.lproj/Localizable.strings"))
        let extensionLocalizationZh = try loadLocalizationFile(at: root.appendingPathComponent("CurrencyConverter Extension/zh-Hant.lproj/Localizable.strings"))

        let targetedKeys = [
            "Safari did not provide more details.",
            " — saved rates; refresh failed",
            "Cashback",
            "%d points",
            "per Point",
            "per Dollar"
        ]
        let staleWarning = " — saved rates; refresh failed"

        for key in targetedKeys {
            XCTAssertNotNil(appLocalizationEn[key], "Missing app fallback key: \(key)")
            XCTAssertNotNil(appLocalizationZh[key], "Missing app zh-Hant key: \(key)")
            XCTAssertNotNil(extensionLocalizationEn[key], "Missing extension fallback key: \(key)")
            XCTAssertNotNil(extensionLocalizationZh[key], "Missing extension zh-Hant key: \(key)")
        }

        XCTAssertNotEqual(
            appLocalizationZh["Safari did not provide more details."],
            appLocalizationEn["Safari did not provide more details."],
            "App zh-Hant should not keep raw English fallback for error details"
        )
        XCTAssertNotEqual(
            extensionLocalizationZh["Safari did not provide more details."],
            extensionLocalizationEn["Safari did not provide more details."],
            "Extension zh-Hant should not keep raw English fallback for error details"
        )

        XCTAssertTrue(staleWarning.hasPrefix(" —"), "Stale warning should keep a leading separator")
        XCTAssertTrue(
            (appLocalizationZh[staleWarning]?.hasPrefix(" —")) == true,
            "App zh-Hant stale warning should keep leading separator"
        )
        XCTAssertTrue(
            (extensionLocalizationZh[staleWarning]?.hasPrefix(" —")) == true,
            "Extension zh-Hant stale warning should keep leading separator"
        )
        XCTAssertNotEqual(
            appLocalizationZh[staleWarning],
            appLocalizationEn[staleWarning],
            "App zh-Hant should not keep raw English stale warning"
        )
        XCTAssertNotEqual(
            extensionLocalizationZh[staleWarning],
            extensionLocalizationEn[staleWarning],
            "Extension zh-Hant should not keep raw English stale warning"
        )

        XCTAssertNotEqual(
            appLocalizationZh["Cashback"],
            appLocalizationEn["Cashback"],
            "App zh-Hant should not keep raw English Cashback"
        )
        XCTAssertNotEqual(
            extensionLocalizationZh["Cashback"],
            extensionLocalizationEn["Cashback"],
            "Extension zh-Hant should not keep raw English Cashback"
        )

        XCTAssertNotEqual(
            appLocalizationZh["%d points"],
            appLocalizationEn["%d points"],
            "App zh-Hant should not keep raw English points format"
        )
        XCTAssertNotEqual(
            extensionLocalizationZh["%d points"],
            extensionLocalizationEn["%d points"],
            "Extension zh-Hant should not keep raw English points format"
        )
        XCTAssertEqual(
            placeholders(in: appLocalizationEn["%d points"]!),
            placeholders(in: appLocalizationZh["%d points"]!)
        )
        XCTAssertEqual(
            placeholders(in: extensionLocalizationEn["%d points"]!),
            placeholders(in: extensionLocalizationZh["%d points"]!)
        )
        XCTAssertNotEqual(
            appLocalizationZh["per Point"],
            appLocalizationEn["per Point"],
            "App zh-Hant should not keep raw English per-Point suffix"
        )
        XCTAssertNotEqual(
            extensionLocalizationZh["per Point"],
            extensionLocalizationEn["per Point"],
            "Extension zh-Hant should not keep raw English per-Point suffix"
        )
        XCTAssertNotEqual(
            appLocalizationZh["per Dollar"],
            appLocalizationEn["per Dollar"],
            "App zh-Hant should not keep raw English per-Dollar suffix"
        )
        XCTAssertNotEqual(
            extensionLocalizationZh["per Dollar"],
            extensionLocalizationEn["per Dollar"],
            "Extension zh-Hant should not keep raw English per-Dollar suffix"
        )
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadLocalizationFile(at path: URL) throws -> [String: String] {
        let data = try Data(contentsOf: path)
        guard let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else {
            XCTFail("Unable to parse plist-like localization file: \(path.path)")
            return [:]
        }
        return object
    }

    private func assertLocaleParity(
        label: String,
        source: [String: String],
        target: [String: String],
        expectLocalizedTarget: Bool = false
    ) {
        XCTAssertEqual(Set(source.keys), Set(target.keys), "\(label) has mismatched keys")

        for key in source.keys {
            guard let sourceValue = source[key], let targetValue = target[key] else {
                XCTFail("\(label) key \(key) missing in one locale")
                continue
            }
            XCTAssertFalse(sourceValue.isEmpty, "\(label) source value is empty for key: \(key)")
            XCTAssertFalse(targetValue.isEmpty, "\(label) target value is empty for key: \(key)")
            XCTAssertEqual(
                placeholders(in: sourceValue),
                placeholders(in: targetValue),
                "Placeholder mismatch for key '\(key)' in \(label)"
            )
            if expectLocalizedTarget {
                XCTAssertNotEqual(
                    targetValue,
                    key,
                    "Potential raw-key fallback for '\(key)' in \(label) target"
                )
            }
        }
    }

    private func assertAllValuesAreTranslated(source: String, values: [String: String]) {
        for (key, value) in values {
            XCTAssertFalse(value.isEmpty, "\(source) has empty value for key: \(key)")
            XCTAssertNotEqual(value, key, "\(source) appears to contain raw key for: \(key)")
        }
    }

    private func collectLocalizedKeys(in folders: [URL]) throws -> Set<String> {
        var keys = Set<String>()
        let regex = try NSRegularExpression(pattern: "NSLocalizedString\\(\\s*\"([^\"]+)\"\\s*,", options: [])

        for folder in folders {
            let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension == "swift" else { continue }
                let text = try String(contentsOf: fileURL)
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    let keyRange = Range(match.range(at: 1), in: text)!
                    keys.insert(String(text[keyRange]))
                }
            }
        }

        return keys
    }

    private func placeholders(in value: String) -> [String] {
        let placeholderPatterns = [
            #"(%%|%\d+\$?[-+ #0-9.]*[A-Za-z@])"#,
            #"\$\{[^\}]+\}"#
        ].compactMap { try? NSRegularExpression(pattern: $0, options: []) }

        var findings: [(Int, String)] = []

        for regex in placeholderPatterns {
            let matches = regex.matches(in: value, options: [], range: NSRange(value.startIndex..., in: value))
            for match in matches {
                if match.range.location == NSNotFound { continue }
                let formatToken = String(value[Range(match.range, in: value)!])
                if formatToken.contains("%%") {
                    continue
                }
                findings.append((match.range.location, formatToken))
            }
        }

        return findings.sorted { $0.0 < $1.0 }.map { $0.1 }
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
