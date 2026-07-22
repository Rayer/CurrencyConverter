import XCTest
@testable import CurrencyConverter

final class CCS19CurrencyPickerTests: XCTestCase {
    func testCodesAreDeterministicallySortedAndDeduplicated() {
        XCTAssertEqual(
            CurrencyPickerPresentation.sortedCodes(["USD", "AED", "TWD", "AED"]),
            ["AED", "TWD", "USD"]
        )
    }

    func testExistingSelectedCodeIsKeptWhenRateDataOmitsIt() {
        XCTAssertEqual(
            CurrencyPickerPresentation.sortedCodes(["USD", "EUR"], including: "TWD"),
            ["EUR", "TWD", "USD"]
        )
    }

    func testCodeComesFirstAndFlagIsDecorativeForAccessibility() {
        let item = CurrencyPickerPresentation.items(for: ["TWD"], flagProvider: { _ in "🇹🇼" }).first!

        XCTAssertEqual(item.label, "TWD 🇹🇼")
        XCTAssertEqual(item.accessibilityLabel, "TWD")
    }

    func testMissingFlagFallsBackWithoutChangingCodeIdentity() {
        let item = CurrencyPickerPresentation.items(for: ["ZZZ"], flagProvider: { _ in " " }).first!

        XCTAssertEqual(item.code, "ZZZ")
        XCTAssertEqual(item.label, "ZZZ")
        XCTAssertEqual(item.accessibilityLabel, "ZZZ")
    }
}
