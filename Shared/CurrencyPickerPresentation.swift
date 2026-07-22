import Foundation

struct CurrencyPickerItem: Equatable {
    let code: String
    let flag: String

    var label: String {
        flag.isEmpty ? code : "\(code) \(flag)"
    }

    var accessibilityLabel: String {
        code
    }
}

enum CurrencyPickerPresentation {
    static func sortedCodes(_ codes: [String], including selectedCode: String? = nil) -> [String] {
        var uniqueCodes = Set(codes.filter { !$0.isEmpty })
        if let selectedCode = selectedCode, !selectedCode.isEmpty {
            uniqueCodes.insert(selectedCode)
        }
        return uniqueCodes.sorted()
    }

    static func items(for codes: [String], flagProvider: (String) -> String) -> [CurrencyPickerItem] {
        sortedCodes(codes).map { code in
            CurrencyPickerItem(code: code, flag: flagProvider(code))
        }
    }

    static func matchingCodes(for typedText: String, in codes: [String]) -> [String] {
        let query = typedText.uppercased()
        guard !query.isEmpty else { return [] }
        return sortedCodes(codes).filter { $0.hasPrefix(query) }
    }

    static func exactCode(for typedText: String, in codes: [String]) -> String? {
        let query = typedText.uppercased()
        guard !query.isEmpty else { return nil }
        return sortedCodes(codes).first { $0 == query }
    }
}
