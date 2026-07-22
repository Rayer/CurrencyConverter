import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func testDeterministicOrdering() {
    require(
        CurrencyPickerPresentation.sortedCodes(["USD", "AED", "TWD", "AED"]) == ["AED", "TWD", "USD"],
        "codes must be sorted and deduplicated"
    )
}

func testTPrefixSequence() {
    let codes = ["TWD", "AED", "TRY", "THB", "USD", "TJS", "TND", "TOP", "TTD", "TZS"]
    require(
        CurrencyPickerPresentation.matchingCodes(for: "T", in: codes) == ["THB", "TJS", "TND", "TOP", "TRY", "TTD", "TWD", "TZS"],
        "T must match the alphabetical T-code sequence"
    )
}

func testExactCodeAndExistingSelection() {
    let codes = ["USD", "EUR"]
    require(CurrencyPickerPresentation.exactCode(for: "twd", in: codes + ["TWD"]) == "TWD", "full-code lookup must be exact")
    require(CurrencyPickerPresentation.sortedCodes(codes, including: "TWD") == ["EUR", "TWD", "USD"], "selected profile code must remain selectable")
}

func testAccessibilityAndMissingFlag() {
    let item = CurrencyPickerPresentation.items(for: ["ZZZ"], flagProvider: { _ in " " }).first!
    require(item.label == "ZZZ", "missing flags must not change visible code identity")
    require(item.accessibilityLabel == "ZZZ", "accessibility must remain code-first")
}

@main
struct CCS19StandaloneTests {
    static func main() {
        testDeterministicOrdering()
        testTPrefixSequence()
        testExactCodeAndExistingSelection()
        testAccessibilityAndMissingFlag()
        print("CCS-19 standalone picker checks passed (4 cases)")
    }
}
