import XCTest
import CoreData
@testable import CurrencyConverter

private enum CCS21Event: Equatable {
    case snapshot
    case apply([RenewUpdate])
    case reload
}

private enum CCS21TestError: Error {
    case conversion
    case save
}

private final class CCS21StoreFixture: AtomicRenewStore {
    var rows: [RenewRowSnapshot]
    private let lock = NSLock()
    var events: [CCS21Event] = []
    var applyOutcomes: [RenewApplyOutcome] = []
    var reloadValues: [RenewHistoryValue] = []
    var snapshotCount = 0
    var applyCount = 0
    var reloadCount = 0
    var lastUpdates: [RenewUpdate] = []

    init(rows: [RenewRowSnapshot]) {
        self.rows = rows
    }

    func snapshotForRenew(completion: @escaping (Result<[RenewRowSnapshot], Error>) -> Void) {
        lock.lock()
        snapshotCount += 1
        events.append(.snapshot)
        lock.unlock()
        completion(.success(rows))
    }

    func applyRenew(updates: [RenewUpdate], completion: @escaping (RenewApplyOutcome) -> Void) {
        lock.lock()
        applyCount += 1
        lastUpdates = updates
        events.append(.apply(updates))
        for update in updates {
            if let index = rows.firstIndex(where: { $0.objectID == update.objectID }) {
                let row = rows[index]
                rows[index] = RenewRowSnapshot(
                    objectID: row.objectID, businessID: row.businessID,
                    fromSymbol: row.fromSymbol, toSymbol: row.toSymbol,
                    fromAmount: row.fromAmount, ratio: update.ratio
                )
            }
        }
        let outcome = applyOutcomes.isEmpty ? RenewApplyOutcome(appliedCount: updates.count, changedCount: updates.count, saveError: nil) : applyOutcomes.removeFirst()
        lock.unlock()
        completion(outcome)
    }

    func readHistory(completion: @escaping ([RenewHistoryValue]) -> Void) {
        lock.lock()
        reloadCount += 1
        events.append(.reload)
        lock.unlock()
        completion(reloadValues)
    }

    func wipeAll() {}
    func wipeById(_ id: UUID) {}
}

private final class CCS21ConverterFixture: RenewConverter {
    struct Request {
        let from: String
        let to: String
        let unit: Float32
        let completion: (Float32, Error?) -> Void
    }

    var requests: [Request] = []
    private let lock = NSLock()
    var onRequest: (() -> Void)?

    func convert(from: String, to: String, unit: Float32, completionHandler: @escaping (Float32, Error?) -> Void) {
        lock.lock()
        requests.append(Request(from: from, to: to, unit: unit, completion: completionHandler))
        let callback = onRequest
        lock.unlock()
        callback?()
    }

    func finish(_ index: Int, amount: Float32, error: Error? = nil) {
        lock.lock()
        let completion = requests[index].completion
        lock.unlock()
        completion(amount, error)
    }

    func finish(from: String, to: String, amount: Float32, error: Error? = nil) {
        lock.lock()
        let completion = requests.first { $0.from == from && $0.to == to }!.completion
        lock.unlock()
        completion(amount, error)
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }
}

final class CCS21AtomicRenewTests: XCTestCase {
    private func makeContext() -> NSManagedObjectContext {
        let model = NSManagedObjectModel.mergedModel(from: [Bundle(for: CCS21AtomicRenewTests.self)])!
        let container = NSPersistentContainer(name: "CurrencyExchangeRate", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        let loaded = expectation(description: "in-memory store loaded")
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 1)
        XCTAssertNil(loadError)
        return container.viewContext
    }

    private func seedHistory(in context: NSManagedObjectContext, id: UUID?, ratio: Float32) {
        context.performAndWait {
            let object = NSEntityDescription.insertNewObject(forEntityName: "ConvertHistory", into: context)
            object.setValue(id, forKey: "id")
            object.setValue(Date(timeIntervalSince1970: 1), forKey: "date")
            object.setValue("USD", forKey: "fromSymbol")
            object.setValue("TWD", forKey: "toSymbol")
            object.setValue(Float32(2), forKey: "fromAmount")
            object.setValue(ratio, forKey: "ratio")
            object.setValue(Float32(0), forKey: "fxFee")
            try! context.save()
        }
    }

    func testLegacyOrderingCharacterizationIsRedUntilRenewIsWiredAtomically() {
        let row = RenewRowSnapshot(objectID: "row-1", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, ratio: 3)
        let store = CCS21StoreFixture(rows: [row])
        let converter = CCS21ConverterFixture()
        let collection = ConvertHistoryDMCollection(dataManager: store, converter: converter)

        let finished = expectation(description: "renew finished")
        let requestReady = expectation(description: "conversion requested")
        converter.onRequest = { requestReady.fulfill() }
        XCTAssertTrue(collection.renewFx { _ in finished.fulfill() })
        XCTAssertEqual(store.events, [.snapshot])
        wait(for: [requestReady], timeout: 1)
        XCTAssertEqual(converter.requestCount, 1)

        converter.finish(0, amount: 80)
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(store.events.count, 3)
        XCTAssertEqual(store.events[0], .snapshot)
        XCTAssertEqual(store.events[2], .reload)
    }

    func testOutOfOrderCallbacksApplyEachOriginalRowOnceAndReloadOnce() {
        let first = RenewRowSnapshot(objectID: "row-1", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, ratio: 3)
        let second = RenewRowSnapshot(objectID: "row-2", businessID: UUID(), fromSymbol: "JPY", toSymbol: "USD", fromAmount: 100, ratio: 4)
        let store = CCS21StoreFixture(rows: [first, second])
        let converter = CCS21ConverterFixture()
        let collection = ConvertHistoryDMCollection(dataManager: store, converter: converter)

        let finished = expectation(description: "renew finished")
        let requestsReady = expectation(description: "conversions requested")
        converter.onRequest = {
            if converter.requestCount == 2 { requestsReady.fulfill() }
        }
        XCTAssertTrue(collection.renewFx { _ in finished.fulfill() })
        XCTAssertEqual(store.events, [.snapshot])
        wait(for: [requestsReady], timeout: 1)
        converter.finish(from: "JPY", to: "USD", amount: 1)
        converter.finish(from: "USD", to: "TWD", amount: 10)
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(store.lastUpdates.map(\.objectID), [first.objectID, second.objectID])
        XCTAssertEqual(store.lastUpdates[0].ratio, 5, accuracy: 0.0001)
        XCTAssertEqual(store.lastUpdates[1].ratio, 0.01, accuracy: 0.0001)
        XCTAssertEqual(store.applyCount, 1)
        XCTAssertEqual(store.reloadCount, 1)
        XCTAssertEqual(store.events.count, 3)
    }

    func testRepeatedRenewPreservesExactIdentitySetAndCount() {
        let rows = [
            RenewRowSnapshot(objectID: "row-1", businessID: UUID(), fromSymbol: "USD", toSymbol: "USD", fromAmount: 0, ratio: 7),
            RenewRowSnapshot(objectID: "row-2", businessID: UUID(), fromSymbol: "JPY", toSymbol: "JPY", fromAmount: 100, ratio: 8)
        ]
        let store = CCS21StoreFixture(rows: rows)
        let converter = CCS21ConverterFixture()
        let collection = ConvertHistoryDMCollection(dataManager: store, converter: converter)
        let first = expectation(description: "first renew")
        XCTAssertTrue(collection.renewFx { _ in first.fulfill() })
        wait(for: [first], timeout: 1)
        let firstIDs = store.lastUpdates.map(\.objectID)

        let second = expectation(description: "second renew")
        XCTAssertTrue(collection.renewFx { _ in second.fulfill() })
        wait(for: [second], timeout: 1)

        XCTAssertEqual(store.rows.count, rows.count)
        XCTAssertEqual(store.rows.map(\.objectID), rows.map(\.objectID))
        XCTAssertEqual(store.rows.map(\.businessID), rows.map(\.businessID))
        XCTAssertEqual(firstIDs, rows.map(\.objectID))
        XCTAssertEqual(store.lastUpdates.map(\.objectID), rows.map(\.objectID))
        XCTAssertEqual(store.reloadCount, 2)
    }

    func testFailureMissingSymbolZeroAndNonFiniteLeaveRowsUnchanged() {
        let rows = [
            RenewRowSnapshot(objectID: "same", businessID: UUID(), fromSymbol: "USD", toSymbol: "USD", fromAmount: 0, ratio: 7),
            RenewRowSnapshot(objectID: "failed", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, ratio: 8),
            RenewRowSnapshot(objectID: "missing", businessID: UUID(), fromSymbol: nil, toSymbol: "TWD", fromAmount: 2, ratio: 9),
            RenewRowSnapshot(objectID: "zero", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: 0, ratio: 10),
            RenewRowSnapshot(objectID: "nan", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: .infinity, ratio: 11)
        ]
        let store = CCS21StoreFixture(rows: rows)
        let converter = CCS21ConverterFixture()
        let collection = ConvertHistoryDMCollection(dataManager: store, converter: converter)
        let finished = expectation(description: "renew finished")
        let requestReady = expectation(description: "failed conversion requested")
        converter.onRequest = { requestReady.fulfill() }
        XCTAssertTrue(collection.renewFx { _ in finished.fulfill() })
        wait(for: [requestReady], timeout: 1)
        converter.finish(0, amount: .nan, error: CCS21TestError.conversion)
        converter.finish(0, amount: 10)
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(store.lastUpdates.count, 1)
        XCTAssertEqual(store.lastUpdates[0].objectID, "same")
        XCTAssertEqual(store.lastUpdates[0].ratio, 1, accuracy: 0.0001)
        XCTAssertEqual(converter.requestCount, 1)
    }

    func testSameCurrencyDoesNotCallConverterAndCallbackIsConsumedOnce() {
        let row = RenewRowSnapshot(objectID: "same", businessID: UUID(), fromSymbol: "USD", toSymbol: "USD", fromAmount: 20, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        let converter = CCS21ConverterFixture()
        let collection = ConvertHistoryDMCollection(dataManager: store, converter: converter)
        let finished = expectation(description: "renew finished")
        XCTAssertTrue(collection.renewFx { _ in finished.fulfill() })
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(converter.requestCount, 0)
        XCTAssertEqual(store.lastUpdates.count, 1)
        XCTAssertEqual(store.lastUpdates[0].ratio, 1, accuracy: 0.0001)
    }

    func testSaveFailureIsReportedAndReloadStillOccursOnce() {
        let row = RenewRowSnapshot(objectID: "row", businessID: UUID(), fromSymbol: "USD", toSymbol: "USD", fromAmount: 2, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        store.applyOutcomes = [RenewApplyOutcome(appliedCount: 0, changedCount: 0, saveError: CCS21TestError.save)]
        let collection = ConvertHistoryDMCollection(dataManager: store, converter: CCS21ConverterFixture())
        let finished = expectation(description: "renew finished")
        var result: RenewRunResult?
        XCTAssertTrue(collection.renewFx {
            result = $0
            finished.fulfill()
        })
        wait(for: [finished], timeout: 1)

        XCTAssertNotNil(result?.saveError)
        XCTAssertEqual(store.reloadCount, 1)
        XCTAssertEqual(store.rows.count, 1)
    }

    func testOverlappingRenewIsRejectedWithoutSecondSnapshot() {
        let row = RenewRowSnapshot(objectID: "row", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        let converter = CCS21ConverterFixture()
        let collection = ConvertHistoryDMCollection(dataManager: store, converter: converter)
        let requestReady = expectation(description: "conversion requested")
        converter.onRequest = { requestReady.fulfill() }
        let first = expectation(description: "first renew")
        XCTAssertTrue(collection.renewFx { _ in first.fulfill() })
        wait(for: [requestReady], timeout: 1)

        let overlap = expectation(description: "overlap rejected")
        var overlapResult: RenewRunResult?
        XCTAssertFalse(collection.renewFx {
            overlapResult = $0
            overlap.fulfill()
        })
        wait(for: [overlap], timeout: 1)
        XCTAssertFalse(overlapResult?.accepted ?? true)
        XCTAssertEqual(store.snapshotCount, 1)

        converter.finish(0, amount: 10)
        wait(for: [first], timeout: 1)
    }

    func testCoreDataSnapshotAndApplyPreserveObjectIdentityAndMissingBusinessID() {
        let context = makeContext()
        seedHistory(in: context, id: nil, ratio: 4)
        var saveCalls = 0
        let saveLock = NSLock()
        let manager = CHDataManager(context: context, saveOperation: {
            saveLock.lock()
            saveCalls += 1
            saveLock.unlock()
            try context.save()
        })
        _ = manager.readFromCore()
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ConvertHistory")
            XCTAssertNil(try! context.fetch(request).first?.value(forKey: "id"))
        }
        let snapshotted = expectation(description: "snapshot")
        var snapshot: RenewRowSnapshot?
        manager.snapshotForRenew {
            if case .success(let rows) = $0 { snapshot = rows.first }
            snapshotted.fulfill()
        }
        wait(for: [snapshotted], timeout: 1)
        let row = try! XCTUnwrap(snapshot)
        XCTAssertNil(row.businessID)

        let applied = expectation(description: "apply")
        manager.applyRenew(updates: [RenewUpdate(objectID: row.objectID, businessID: nil, ratio: 2)]) { outcome in
            XCTAssertEqual(outcome.changedCount, 1)
            XCTAssertNil(outcome.saveError)
            applied.fulfill()
        }
        wait(for: [applied], timeout: 1)
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ConvertHistory")
            let objects = try! context.fetch(request)
            XCTAssertEqual(objects.count, 1)
            XCTAssertEqual(objects.first?.value(forKey: "ratio") as? Float32, 2)
            XCTAssertNil(objects.first?.value(forKey: "id"))
        }

        let repeated = expectation(description: "repeated apply")
        manager.applyRenew(updates: [RenewUpdate(objectID: row.objectID, businessID: nil, ratio: 2)]) { outcome in
            XCTAssertEqual(outcome.changedCount, 0)
            repeated.fulfill()
        }
        wait(for: [repeated], timeout: 1)
        saveLock.lock()
        XCTAssertEqual(saveCalls, 1)
        saveLock.unlock()
    }

    func testCoreDataSaveFailureRollsBackRenewRatios() {
        let context = makeContext()
        let id = UUID()
        seedHistory(in: context, id: id, ratio: 4)
        var saveCalls = 0
        let saveLock = NSLock()
        let manager = CHDataManager(context: context, saveOperation: {
            saveLock.lock()
            saveCalls += 1
            saveLock.unlock()
            throw CCS21TestError.save
        })
        let snapshotted = expectation(description: "snapshot")
        var snapshot: RenewRowSnapshot?
        manager.snapshotForRenew {
            if case .success(let rows) = $0 { snapshot = rows.first }
            snapshotted.fulfill()
        }
        wait(for: [snapshotted], timeout: 1)
        let row = try! XCTUnwrap(snapshot)

        let applied = expectation(description: "failed apply")
        manager.applyRenew(updates: [RenewUpdate(objectID: row.objectID, businessID: id, ratio: 2)]) { outcome in
            XCTAssertEqual(outcome.changedCount, 0)
            XCTAssertNotNil(outcome.saveError)
            applied.fulfill()
        }
        wait(for: [applied], timeout: 1)
        saveLock.lock()
        XCTAssertEqual(saveCalls, 1)
        saveLock.unlock()
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ConvertHistory")
            let object = try! context.fetch(request).first
            XCTAssertEqual(object?.value(forKey: "ratio") as? Float32, 4)
            XCTAssertEqual(object?.value(forKey: "id") as? UUID, id)
        }
    }
}
