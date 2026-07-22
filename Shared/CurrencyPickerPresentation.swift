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
            CurrencyPickerItem(
                code: code,
                flag: flagProvider(code).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

}
