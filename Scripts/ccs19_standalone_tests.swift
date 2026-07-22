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

func testExistingSelection() {
    let codes = ["USD", "EUR"]
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
        testExistingSelection()
        testAccessibilityAndMissingFlag()
        print("CCS-19 standalone picker checks passed (3 cases)")
    }
}
