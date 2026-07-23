//
//  FormatStringDataManager.swift
//  CurrencyConverter
//

import CoreData
import Foundation

enum ConversionTemplateRepositoryError: Error, Equatable, LocalizedError {
    case readFailed
    case saveFailed
    case notFound

    var errorDescription: String? {
        switch self {
        case .readFailed:
            return NSLocalizedString("Could not read conversion templates.", comment: "Conversion template repository read error")
        case .saveFailed:
            return NSLocalizedString("Could not save conversion templates.", comment: "Conversion template repository save error")
        case .notFound:
            return NSLocalizedString("The conversion template is no longer available.", comment: "Missing conversion template repository error")
        }
    }
}

enum ConversionTemplateOperationError: Error, Equatable, LocalizedError {
    case validation(ConversionTemplateValidationError)
    case repository(ConversionTemplateRepositoryError)

    var errorDescription: String? {
        switch self {
        case .validation(let error): return error.errorDescription
        case .repository(let error): return error.errorDescription
        }
    }
}

final class FormatStringDataManager {
    static let shared = FormatStringDataManager()

    private let context: NSManagedObjectContext
    private let defaults: UserDefaults
    private let saveOperation: (() throws -> Void)?
    private var initializationError: ConversionTemplateRepositoryError? = nil

    init(
        context: NSManagedObjectContext = sharedPersistentContainer.viewContext,
        defaults: UserDefaults = sharedUserDefaults,
        saveOperation: (() throws -> Void)? = nil
    ) {
        self.context = context
        self.defaults = defaults
        self.saveOperation = saveOperation
        do {
            try performAndWait { try ensureBundledDefaults() }
        } catch {
            initializationError = Self.repositoryError(for: error)
        }
    }

    func availableTemplates() -> Result<[ConversionTemplate], ConversionTemplateRepositoryError> {
        repositoryResult {
            try ensureBundledDefaults()
            return try fetchTemplates()
        }
    }

    func selectedTemplate() -> Result<ConversionTemplate, ConversionTemplateRepositoryError> {
        repositoryResult {
            try ensureBundledDefaults()
            let templates = try fetchTemplates()
            let persistedID = defaults.string(forKey: ConversionTemplateSelection.selectedIDKey)
                .flatMap(UUID.init(uuidString:))
            let hasPersistedSelection = defaults.object(forKey: ConversionTemplateSelection.selectedIDKey) != nil
            let legacyIndex = hasPersistedSelection
                ? nil
                : defaults.object(forKey: ConversionTemplateSelection.legacyFormatIndexKey) as? Int
            let selected = ConversionTemplateSelection.resolve(
                persistedID: persistedID,
                legacyFormatIndex: legacyIndex,
                available: templates
            )
            if persistedID?.uuidString != selected.id.uuidString {
                defaults.set(selected.id.uuidString, forKey: ConversionTemplateSelection.selectedIDKey)
            }
            return selected
        }
    }

    @discardableResult
    func add(template text: String) -> Result<ConversionTemplate, ConversionTemplateOperationError> {
        switch ConversionTemplateFormatter.validate(text) {
        case .success:
            break
        case .failure(let error):
            return .failure(.validation(error))
        }
        return operationResult {
            let template = ConversionTemplate(id: UUID(), text: text, date: Date())
            let entity = FormatString(context: context)
            entity.id = template.id
            entity.date = template.date
            entity.format_string = template.text
            try save()
            return template
        }
    }

    @discardableResult
    func select(id: UUID) -> Result<ConversionTemplate, ConversionTemplateOperationError> {
        operationResult {
            try ensureBundledDefaults()
            guard let template = try fetchTemplates().first(where: { $0.id == id }) else {
                throw ConversionTemplateRepositoryError.notFound
            }
            // The repository has been read successfully before selection is published.
            defaults.set(template.id.uuidString, forKey: ConversionTemplateSelection.selectedIDKey)
            return template
        }
    }

    @discardableResult
    func delete(id: UUID) -> Result<ConversionTemplate, ConversionTemplateOperationError> {
        operationResult {
            try ensureBundledDefaults()
            let request = try formatStringFetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let matches = try context.fetch(request)
            guard let object = matches.sorted(by: Self.objectOrder).first else {
                throw ConversionTemplateRepositoryError.notFound
            }
            if ConversionTemplateCatalog.defaultIDs.contains(id) {
                let selected = try selectedTemplateValue(from: try fetchTemplates())
                defaults.set(selected.id.uuidString, forKey: ConversionTemplateSelection.selectedIDKey)
                return selected
            }
            context.delete(object)
            try save()
            let selected = try selectedTemplateValue(from: try fetchTemplates())
            defaults.set(selected.id.uuidString, forKey: ConversionTemplateSelection.selectedIDKey)
            return selected
        }
    }

    @discardableResult
    func reset() -> Result<[ConversionTemplate], ConversionTemplateOperationError> {
        operationResult {
            let request = try formatStringFetchRequest()
            let objects = try context.fetch(request)
            objects.forEach(context.delete)
            for (id, text) in zip(ConversionTemplateCatalog.defaultIDs, ConversionTemplateCatalog.defaultTexts) {
                let entity = FormatString(context: context)
                entity.id = id
                entity.date = Date()
                entity.format_string = text
            }
            try save()
            let templates = try fetchTemplates()
            let selected = templates.first(where: { $0.id == ConversionTemplateCatalog.defaultIDs[0] })
                ?? ConversionTemplateCatalog.defaults[0]
            defaults.set(selected.id.uuidString, forKey: ConversionTemplateSelection.selectedIDKey)
            return templates
        }
    }

    // Compatibility surface for existing app code and old callers.
    @discardableResult
    func AddString(string: String) -> Result<ConversionTemplate, ConversionTemplateOperationError> {
        add(template: string)
    }

    @discardableResult
    func DeleteString(uuid: UUID) -> Result<ConversionTemplate, ConversionTemplateOperationError> {
        delete(id: uuid)
    }

    func ResetDefault() {
        _ = reset()
    }

    func PreviewString(string: String) -> String {
        guard case .success(let preview) = ConversionTemplateFormatter.preview(string) else { return "" }
        return preview
    }

    func PreviewString(id: UUID) -> String {
        guard case .success(let templates) = availableTemplates(),
              let template = templates.first(where: { $0.id == id }) else { return "" }
        return PreviewString(string: template.text)
    }

    private func selectedTemplateValue(from templates: [ConversionTemplate]) throws -> ConversionTemplate {
        let hasPersistedSelection = defaults.object(forKey: ConversionTemplateSelection.selectedIDKey) != nil
        let selectedID = defaults.string(forKey: ConversionTemplateSelection.selectedIDKey)
            .flatMap(UUID.init(uuidString:))
        let legacyIndex = hasPersistedSelection
            ? nil
            : defaults.object(forKey: ConversionTemplateSelection.legacyFormatIndexKey) as? Int
        return ConversionTemplateSelection.resolve(
            persistedID: selectedID,
            legacyFormatIndex: legacyIndex,
            available: templates
        )
    }

    private func ensureBundledDefaults() throws {
        let request = try formatStringFetchRequest()
        let objects = try context.fetch(request)
        var changed = false
        for (defaultID, defaultText) in zip(ConversionTemplateCatalog.defaultIDs, ConversionTemplateCatalog.defaultTexts) {
            let matching = objects.filter { $0.format_string == defaultText }
                .sorted(by: Self.objectOrder)
            let canonical = matching.first(where: { $0.id == defaultID }) ?? matching.first
            if let canonical {
                if canonical.id != defaultID {
                    canonical.id = defaultID
                    changed = true
                }
                for duplicate in matching where duplicate.objectID != canonical.objectID {
                    context.delete(duplicate)
                    changed = true
                }
            } else {
                let entity = FormatString(context: context)
                entity.id = defaultID
                entity.date = Date()
                entity.format_string = defaultText
                changed = true
            }
        }
        if changed { try save() }
    }

    private func fetchTemplates() throws -> [ConversionTemplate] {
        let request = try formatStringFetchRequest()
        let objects = try context.fetch(request)
        return objects.compactMap { object in
            guard let id = object.id, let text = object.format_string,
                  case .success = ConversionTemplateFormatter.validate(text) else { return nil }
            return ConversionTemplate(id: id, text: text, date: object.date)
        }.sorted {
            if $0.date != $1.date { return ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func save() throws {
        do {
            if let saveOperation { try saveOperation() } else { try context.save() }
        } catch {
            context.rollback()
            throw ConversionTemplateRepositoryError.saveFailed
        }
    }

    private func formatStringFetchRequest() throws -> NSFetchRequest<FormatString> {
        guard context.persistentStoreCoordinator?.managedObjectModel.entitiesByName["FormatString"] != nil else {
            throw ConversionTemplateRepositoryError.readFailed
        }
        return NSFetchRequest<FormatString>(entityName: "FormatString")
    }

    private func repositoryResult<T>(_ work: () throws -> T) -> Result<T, ConversionTemplateRepositoryError> {
        if let initializationError { return .failure(initializationError) }
        do { return .success(try performAndWait { try work() }) }
        catch { return .failure(Self.repositoryError(for: error)) }
    }

    private func operationResult<T>(_ work: () throws -> T) -> Result<T, ConversionTemplateOperationError> {
        if let initializationError { return .failure(.repository(initializationError)) }
        do { return .success(try performAndWait { try work() }) }
        catch { return .failure(.repository(Self.repositoryError(for: error))) }
    }

    private func performAndWait<T>(_ work: () throws -> T) throws -> T {
        var result: Result<T, Error> = .failure(ConversionTemplateRepositoryError.readFailed)
        context.performAndWait {
            do { result = .success(try work()) }
            catch { result = .failure(error) }
        }
        return try result.get()
    }

    private static func repositoryError(for error: Error) -> ConversionTemplateRepositoryError {
        if let error = error as? ConversionTemplateRepositoryError { return error }
        return .readFailed
    }

    private static func objectOrder(_ lhs: FormatString, _ rhs: FormatString) -> Bool {
        if lhs.date != rhs.date { return (lhs.date ?? .distantPast) < (rhs.date ?? .distantPast) }
        return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
    }
}
