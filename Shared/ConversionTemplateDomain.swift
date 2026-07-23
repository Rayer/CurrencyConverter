//
//  ConversionTemplateDomain.swift
//  CurrencyConverter
//

import Foundation

struct ConversionTemplate: Identifiable, Equatable {
    let id: UUID
    let text: String
    let date: Date?
}

enum ConversionTemplateCatalog {
    static let defaultTexts: [String] = [
        "${to_amount} ${to_symbol}",
        "${to_amount}",
        "${from_amount} ${from_symbol} => ${to_amount} ${to_symbol}",
        "(${from_symbol}) ${from_amount} => (${to_symbol}) ${to_amount}"
    ]

    // These IDs are the compatibility contract for the four original formats.
    static let defaultIDs: [UUID] = [
        UUID(uuid: (0x10, 0x7b, 0x5e, 0x01, 0x6d, 0x4a, 0x4d, 0x6a, 0x9a, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01)),
        UUID(uuid: (0x10, 0x7b, 0x5e, 0x01, 0x6d, 0x4a, 0x4d, 0x6a, 0x9a, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02)),
        UUID(uuid: (0x10, 0x7b, 0x5e, 0x01, 0x6d, 0x4a, 0x4d, 0x6a, 0x9a, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03)),
        UUID(uuid: (0x10, 0x7b, 0x5e, 0x01, 0x6d, 0x4a, 0x4d, 0x6a, 0x9a, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04))
    ]

    static var defaults: [ConversionTemplate] {
        zip(defaultIDs, defaultTexts).map { ConversionTemplate(id: $0.0, text: $0.1, date: nil) }
    }
}

enum ConversionTemplateValidationError: Error, Equatable, LocalizedError {
    case emptyTemplate
    case unknownPlaceholder(String)
    case malformedPlaceholder(String)

    var errorDescription: String? {
        switch self {
        case .emptyTemplate:
            return NSLocalizedString("Enter a conversion template.", comment: "Empty conversion template validation error")
        case .unknownPlaceholder(let placeholder):
            return String(format: NSLocalizedString("Unknown placeholder: %@", comment: "Unknown conversion template placeholder validation error"), placeholder)
        case .malformedPlaceholder(let placeholder):
            return String(format: NSLocalizedString("Malformed placeholder: %@", comment: "Malformed conversion template placeholder validation error"), placeholder)
        }
    }
}

enum ConversionTemplateFormatError: Error, Equatable {
    case validation(ConversionTemplateValidationError)

    var errorDescription: String? {
        switch self {
        case .validation(let error): return error.errorDescription
        }
    }
}

struct ConversionTemplateValues: Equatable {
    let fromSymbol: String
    let fromAmount: Float32
    let toSymbol: String
    let toAmount: Float32
    let fromAmountText: String?

    init(fromSymbol: String, fromAmount: Float32, toSymbol: String, toAmount: Float32, fromAmountText: String? = nil) {
        self.fromSymbol = fromSymbol
        self.fromAmount = fromAmount
        self.toSymbol = toSymbol
        self.toAmount = toAmount
        self.fromAmountText = fromAmountText
    }
}

enum ConversionTemplateFormatter {
    static let fromAmountPlaceholder = "${from_amount}"
    static let toAmountPlaceholder = "${to_amount}"
    static let fromSymbolPlaceholder = "${from_symbol}"
    static let toSymbolPlaceholder = "${to_symbol}"
    static let allowedPlaceholders: Set<String> = [
        fromAmountPlaceholder,
        toAmountPlaceholder,
        fromSymbolPlaceholder,
        toSymbolPlaceholder
    ]

    static func validate(_ template: String) -> Result<Void, ConversionTemplateValidationError> {
        guard !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptyTemplate)
        }

        var scanStart = template.startIndex
        while scanStart < template.endIndex,
              let opening = template.range(of: "${", range: scanStart..<template.endIndex) {
            guard let closing = template.range(of: "}", range: opening.upperBound..<template.endIndex) else {
                return .failure(.malformedPlaceholder(String(template[opening.lowerBound..<template.endIndex])))
            }
            let placeholder = String(template[opening.lowerBound..<closing.upperBound])
            guard allowedPlaceholders.contains(placeholder) else {
                return .failure(.unknownPlaceholder(placeholder))
            }
            scanStart = closing.upperBound
        }
        return .success(())
    }

    static func format(_ template: String, values: ConversionTemplateValues) -> Result<String, ConversionTemplateFormatError> {
        switch validate(template) {
        case .failure(let error):
            return .failure(.validation(error))
        case .success:
            break
        }

        let replacements: [String: String] = [
            fromSymbolPlaceholder: values.fromSymbol,
            toSymbolPlaceholder: values.toSymbol,
            fromAmountPlaceholder: values.fromAmountText ?? String(describing: values.fromAmount),
            toAmountPlaceholder: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), values.toAmount)
        ]

        var result = ""
        var scanStart = template.startIndex
        while let opening = template.range(of: "${", range: scanStart..<template.endIndex) {
            result += template[scanStart..<opening.lowerBound]
            guard let closing = template.range(of: "}", range: opening.upperBound..<template.endIndex) else {
                return .failure(.validation(.malformedPlaceholder(String(template[opening.lowerBound..<template.endIndex]))) )
            }
            let placeholder = String(template[opening.lowerBound..<closing.upperBound])
            result += replacements[placeholder] ?? placeholder
            scanStart = closing.upperBound
        }
        result += template[scanStart..<template.endIndex]
        return .success(result)
    }

    static func preview(_ template: String) -> Result<String, ConversionTemplateFormatError> {
        format(template, values: ConversionTemplateValues(fromSymbol: "TWD", fromAmount: 2, toSymbol: "USD", toAmount: 62.14, fromAmountText: "2"))
    }
}

enum ConversionTemplateSelection {
    static let selectedIDKey = "ConversionTemplateSelectionID"
    static let legacyFormatIndexKey = "FormatIndex"

    static func legacyID(for formatIndex: Int?) -> UUID {
        guard let formatIndex, ConversionTemplateCatalog.defaultIDs.indices.contains(formatIndex) else {
            return ConversionTemplateCatalog.defaultIDs[0]
        }
        return ConversionTemplateCatalog.defaultIDs[formatIndex]
    }

    static func resolve(
        persistedID: UUID?,
        legacyFormatIndex: Int?,
        available: [ConversionTemplate]
    ) -> ConversionTemplate {
        if let persistedID, let selected = available.first(where: { $0.id == persistedID }) {
            return selected
        }
        let legacyID = legacyID(for: legacyFormatIndex)
        if let legacy = available.first(where: { $0.id == legacyID }) {
            return legacy
        }
        return available.first(where: { $0.id == ConversionTemplateCatalog.defaultIDs[0] })
            ?? ConversionTemplateCatalog.defaults[0]
    }
}

final class LatestRequestGate<Key: Equatable, Value> {
    struct Generation: Equatable {
        fileprivate let key: Key
        fileprivate let value: UInt64
        fileprivate let identity: UUID
    }

    private let lock = NSLock()
    private var generations: [(key: Key, value: UInt64, identity: UUID)] = []
    private var pending: [(key: Key, value: Value)] = []

    func begin(for key: Key) -> Generation {
        lock.lock()
        defer { lock.unlock() }
        let current = generations.first { $0.key == key }?.value ?? 0
        let next = current == UInt64.max ? UInt64.max : current + 1
        let identity = UUID()
        generations.removeAll { $0.key == key }
        generations.append((key, next, identity))
        pending.removeAll { $0.key == key }
        return Generation(key: key, value: next, identity: identity)
    }

    func publish(_ value: Value, generation requestGeneration: Generation) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generations.contains(where: {
            $0.key == requestGeneration.key
                && $0.value == requestGeneration.value
                && $0.identity == requestGeneration.identity
        }) else {
            return false
        }
        pending.removeAll { $0.key == requestGeneration.key }
        pending.append((requestGeneration.key, value))
        return true
    }

    func invalidate(_ requestGeneration: Generation) {
        lock.lock()
        defer { lock.unlock() }
        guard generations.contains(where: {
            $0.key == requestGeneration.key
                && $0.value == requestGeneration.value
                && $0.identity == requestGeneration.identity
        }) else {
            return
        }
        pending.removeAll { $0.key == requestGeneration.key }
    }

    func consume(for key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let candidate = pending.first(where: { $0.key == key }) else { return nil }
        pending.removeAll { $0.key == key }
        if let current = generations.first(where: { $0.key == key })?.value {
            generations.removeAll { $0.key == key }
            generations.append((key, current == UInt64.max ? UInt64.max : current + 1, UUID()))
        }
        return candidate.value
    }
}

final class OneShot<Value> {
    private let lock = NSLock()
    private var completed = false
    private let completion: (Value) -> Void

    init(_ completion: @escaping (Value) -> Void) {
        self.completion = completion
    }

    func call(_ value: Value) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        completion(value)
    }
}
