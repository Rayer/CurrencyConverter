import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("CCS-15 standalone test failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct CCS15StandaloneTests {
    static func main() {
        require(ConversionTemplateCatalog.defaultTexts.count == 4, "bundled default count changed")
        require(ConversionTemplateSelection.legacyID(for: 2) == ConversionTemplateCatalog.defaultIDs[2], "legacy mapping changed")
        switch ConversionTemplateFormatter.validate(" ") {
        case .failure(.emptyTemplate): break
        default: require(false, "empty validation missing")
        }
        switch ConversionTemplateFormatter.validate("${unknown}") {
        case .failure(.unknownPlaceholder("${unknown}")): break
        default: require(false, "unknown validation missing")
        }

        let values = ConversionTemplateValues(fromSymbol: "TWD", fromAmount: 2, toSymbol: "USD", toAmount: 62.14)
        let output: String
        do {
            output = try ConversionTemplateFormatter.format(
                "${to_amount} ${to_amount} ${to_symbol} ${to_symbol}",
                values: values
            ).get()
        } catch {
            require(false, "formatting unexpectedly failed")
            output = ""
        }
        require(output == "62.14 62.14 USD USD", "all occurrences were not formatted")

        let gate = LatestRequestGate<String, Int>()
        let stale = gate.begin()
        let current = gate.begin()
        require(!gate.publish(1, for: "old", generation: stale), "stale request published")
        require(gate.publish(2, for: "current", generation: current), "current request was rejected")
        require(gate.consume(for: "old") == nil, "wrong request consumed a result")
        require(gate.consume(for: "current") == 2, "current result was not consumed")
        require(gate.consume(for: "current") == nil, "result was consumed more than once")
        print("CCS-15 standalone domain checks passed")
    }
}
