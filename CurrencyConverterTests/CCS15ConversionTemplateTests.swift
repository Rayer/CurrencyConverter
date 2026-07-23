import CoreData
import XCTest
@testable import CurrencyConverter

final class CCS15ConversionTemplateTests: XCTestCase {
    func testFormatterReplacesEveryAllowedPlaceholderAndKeepsLiteralText() {
        let template = "${from_symbol}/${from_symbol} ${from_amount} ${from_amount} -> ${to_symbol}/${to_symbol} ${to_amount} ${to_amount} [$]"
        let values = ConversionTemplateValues(fromSymbol: "JPY", fromAmount: 2, toSymbol: "USD", toAmount: 62.14)

        let result = ConversionTemplateFormatter.format(template, values: values)

        XCTAssertEqual(try? result.get(), "JPY/JPY 2.0 2.0 -> USD/USD 62.14 62.14 [$]")
    }

    func testValidationRejectsEmptyUnknownAndMalformedTemplates() {
        assertValidation(ConversionTemplateFormatter.validate(" \n\t"), equals: .emptyTemplate)
        assertValidation(ConversionTemplateFormatter.validate("${unknown}"), equals: .unknownPlaceholder("${unknown}"))
        assertValidation(ConversionTemplateFormatter.validate("before ${from_symbol"), equals: .malformedPlaceholder("${from_symbol"))
    }

    func testInvalidAddDoesNotMutateRepository() throws {
        let context = try makeContext()
        let defaults = try makeDefaults()
        let manager = FormatStringDataManager(context: context, defaults: defaults)
        let before = try XCTUnwrap(try manager.availableTemplates().get())

        let result = manager.add(template: "${not_allowed}")

        XCTAssertEqual(result, .failure(.validation(.unknownPlaceholder("${not_allowed}"))))
        XCTAssertEqual(try manager.availableTemplates().get(), before)
    }

    func testDefaultsHaveStableIDsAndResetIsIdempotent() throws {
        let context = try makeContext()
        let defaults = try makeDefaults()
        let manager = FormatStringDataManager(context: context, defaults: defaults)
        let initial = try XCTUnwrap(try manager.availableTemplates().get())

        XCTAssertEqual(initial.map(\.id), ConversionTemplateCatalog.defaultIDs)
        _ = manager.reset()
        XCTAssertEqual(try manager.availableTemplates().get().map(\.id), ConversionTemplateCatalog.defaultIDs)
        XCTAssertEqual(try manager.selectedTemplate().get().id, ConversionTemplateCatalog.defaultIDs[0])
    }

    func testLegacyFormatIndexMapsToBundledDefaultsDeterministically() throws {
        let context = try makeContext()
        let defaults = try makeDefaults()
        defaults.set(2, forKey: ConversionTemplateSelection.legacyFormatIndexKey)
        let manager = FormatStringDataManager(context: context, defaults: defaults)

        let selected = try manager.selectedTemplate().get()

        XCTAssertEqual(selected.id, ConversionTemplateCatalog.defaultIDs[2])
        XCTAssertEqual(defaults.string(forKey: ConversionTemplateSelection.selectedIDKey), selected.id.uuidString)
    }

    func testAddPreviewSelectAndActualFormatterOutput() throws {
        let context = try makeContext()
        let defaults = try makeDefaults()
        let manager = FormatStringDataManager(context: context, defaults: defaults)
        let added = try manager.add(template: "COPY ${to_symbol}: ${to_amount} ${to_amount}").get()

        XCTAssertEqual(try ConversionTemplateFormatter.preview(added.text).get(), "COPY USD: 62.14 62.14")
        XCTAssertEqual(try manager.select(id: added.id).get().id, added.id)
        let selected = try manager.selectedTemplate().get()
        let formatted = try ConversionTemplateFormatter.format(
            selected.text,
            values: ConversionTemplateValues(fromSymbol: "TWD", fromAmount: 1, toSymbol: "USD", toAmount: 10)
        ).get()

        XCTAssertEqual(formatted, "COPY USD: 10.00 10.00")
    }

    func testDeletingSelectedAndNonselectedTemplatesUsesSafeFallback() throws {
        let context = try makeContext()
        let defaults = try makeDefaults()
        let manager = FormatStringDataManager(context: context, defaults: defaults)
        let first = try manager.add(template: "first ${to_amount}").get()
        let second = try manager.add(template: "second ${to_amount}").get()
        _ = try manager.select(id: second.id).get()

        _ = try manager.delete(id: first.id).get()
        XCTAssertEqual(try manager.selectedTemplate().get().id, second.id)
        _ = try manager.delete(id: second.id).get()

        XCTAssertEqual(try manager.selectedTemplate().get().id, ConversionTemplateCatalog.defaultIDs[0])
        XCTAssertEqual(defaults.string(forKey: ConversionTemplateSelection.selectedIDKey), ConversionTemplateCatalog.defaultIDs[0].uuidString)
    }

    func testMissingAndCorruptSelectionFallsBackAndPersistsValidID() throws {
        let context = try makeContext()
        let defaults = try makeDefaults()
        let manager = FormatStringDataManager(context: context, defaults: defaults)
        defaults.set(UUID().uuidString, forKey: ConversionTemplateSelection.selectedIDKey)
        XCTAssertEqual(try manager.selectedTemplate().get().id, ConversionTemplateCatalog.defaultIDs[0])
        XCTAssertEqual(defaults.string(forKey: ConversionTemplateSelection.selectedIDKey), ConversionTemplateCatalog.defaultIDs[0].uuidString)

        let corrupt = try XCTUnwrap(
            NSEntityDescription.insertNewObject(forEntityName: "FormatString", into: context) as? FormatString
        )
        corrupt.id = UUID()
        corrupt.date = Date()
        corrupt.format_string = "${corrupt}"
        try context.save()
        defaults.set(corrupt.id?.uuidString, forKey: ConversionTemplateSelection.selectedIDKey)

        XCTAssertEqual(try manager.selectedTemplate().get().id, ConversionTemplateCatalog.defaultIDs[0])
        XCTAssertEqual(defaults.string(forKey: ConversionTemplateSelection.selectedIDKey), ConversionTemplateCatalog.defaultIDs[0].uuidString)
    }

    func testAppAndExtensionRepositoriesReadTheSameSelection() throws {
        let appContext = try makeContext()
        let extensionContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        extensionContext.persistentStoreCoordinator = appContext.persistentStoreCoordinator
        let defaults = try makeDefaults()
        let appRepository = FormatStringDataManager(context: appContext, defaults: defaults)
        let extensionRepository = FormatStringDataManager(context: extensionContext, defaults: defaults)
        let added = try appRepository.add(template: "shared ${from_symbol} ${to_amount}").get()
        _ = try appRepository.select(id: added.id).get()

        XCTAssertEqual(try extensionRepository.selectedTemplate().get(), added)
        XCTAssertEqual(try extensionRepository.availableTemplates().get(), try appRepository.availableTemplates().get())
    }

    func testRepositoryReportsCoreDataReadAndSaveFailures() throws {
        let emptyModelContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
        emptyModelContext.persistentStoreCoordinator = coordinator
        let readFailureManager = FormatStringDataManager(context: emptyModelContext, defaults: try makeDefaults())
        XCTAssertEqual(readFailureManager.availableTemplates(), .failure(.readFailed))

        let saveFailureManager = FormatStringDataManager(
            context: try makeContext(),
            defaults: try makeDefaults(),
            saveOperation: { throw ConversionTemplateRepositoryError.saveFailed }
        )
        XCTAssertEqual(saveFailureManager.availableTemplates(), .failure(.saveFailed))
    }

    func testRepairRemovesInvalidAndDuplicateIDsWithoutCollapsingEqualText() throws {
        let context = try makeContext()
        let duplicateID = UUID()
        let equalTextID = UUID()
        var insertionError: Error?
        context.performAndWait {
            do {
                try insertTemplate(id: nil, text: "${to_amount}", context: context)
                try insertTemplate(id: UUID(), text: "${invalid}", context: context)
                try insertTemplate(id: duplicateID, text: "first ${to_amount}", context: context)
                try insertTemplate(id: duplicateID, text: "second ${to_amount}", context: context)
                try insertTemplate(
                    id: ConversionTemplateCatalog.defaultIDs[0],
                    text: "corrupt default ${to_amount}",
                    context: context
                )
                try insertTemplate(id: equalTextID, text: ConversionTemplateCatalog.defaultTexts[0], context: context)
                try context.save()
            } catch {
                insertionError = error
            }
        }
        if let insertionError { throw insertionError }

        let manager = FormatStringDataManager(context: context, defaults: try makeDefaults())
        let templates = try manager.availableTemplates().get()

        XCTAssertEqual(templates.filter { $0.id == duplicateID }.count, 1)
        XCTAssertEqual(templates.first { $0.id == duplicateID }?.text, "first ${to_amount}")
        XCTAssertEqual(
            templates.first { $0.id == ConversionTemplateCatalog.defaultIDs[0] }?.text,
            ConversionTemplateCatalog.defaultTexts[0]
        )
        XCTAssertEqual(templates.first { $0.id == equalTextID }?.text, ConversionTemplateCatalog.defaultTexts[0])
        XCTAssertFalse(templates.contains { $0.text == "${invalid}" })
    }

    func testOneShotCallsCompletionOnce() {
        var values: [Int] = []
        let oneShot = OneShot<Int> { values.append($0) }

        oneShot.call(1)
        oneShot.call(2)

        XCTAssertEqual(values, [1])
    }


    func testConcurrentRepositoriesSeedOneStableDefaultPerID() throws {
        let seedContext = try makeContext()
        let firstContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        let secondContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        firstContext.persistentStoreCoordinator = seedContext.persistentStoreCoordinator
        secondContext.persistentStoreCoordinator = seedContext.persistentStoreCoordinator
        let defaults = try makeDefaults()
        let managers = [
            FormatStringDataManager(context: firstContext, defaults: defaults),
            FormatStringDataManager(context: secondContext, defaults: defaults)
        ]
        let resultLock = NSLock()
        var successfulCounts: [Int] = []
        let group = DispatchGroup()

        for manager in managers {
            group.enter()
            DispatchQueue.global().async {
                if case .success(let templates) = manager.availableTemplates() {
                    resultLock.lock()
                    successfulCounts.append(templates.count)
                    resultLock.unlock()
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(successfulCounts.sorted(), [4, 4])

        let templates = try managers[0].availableTemplates().get()
        for defaultID in ConversionTemplateCatalog.defaultIDs {
            XCTAssertEqual(templates.filter { $0.id == defaultID }.count, 1)
        }
    }


    private func makeContext() throws -> NSManagedObjectContext {
        guard let model = NSManagedObjectModel.mergedModel(from: [Bundle(for: CCS15ConversionTemplateTests.self)]) else {
            throw TestError.missingModel
        }
        let container = NSPersistentContainer(name: "CurrencyExchangeRate", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        let expectation = self.expectation(description: "load in-memory template store")
        container.loadPersistentStores { _, error in
            loadError = error
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        if let loadError { throw loadError }
        return container.viewContext
    }

    private func insertTemplate(
        id: UUID?,
        text: String,
        context: NSManagedObjectContext
    ) throws {
        let object = try XCTUnwrap(
            NSEntityDescription.insertNewObject(forEntityName: "FormatString", into: context) as? FormatString
        )
        object.id = id
        object.date = Date()
        object.format_string = text
    }

    private func assertValidation(
        _ result: Result<Void, ConversionTemplateValidationError>,
        equals expected: ConversionTemplateValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .failure(let error): XCTAssertEqual(error, expected, file: file, line: line)
        case .success: XCTFail("expected validation failure", file: file, line: line)
        }
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "CCS15-templates-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw TestError.missingDefaults }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private enum TestError: Error {
    case missingModel
    case missingDefaults
}
