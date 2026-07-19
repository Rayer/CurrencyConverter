import XCTest
import CoreData

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
    private let lock = NSLock()
    private var storedRows: [RenewRowSnapshot]
    private var storedEvents: [CCS21Event] = []
    private var storedSnapshotCount = 0
    private var storedApplyCount = 0
    private var storedReloadCount = 0
    private var storedLastUpdates: [RenewUpdate] = []
    var applyOutcomes: [RenewApplyOutcome] = []
    var reloadValues: [RenewHistoryValue] = []

    init(rows: [RenewRowSnapshot]) {
        self.storedRows = rows
    }

    var rows: [RenewRowSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return storedRows
    }

    var events: [CCS21Event] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    var snapshotCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshotCount
    }

    var applyCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedApplyCount
    }

    var reloadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedReloadCount
    }

    var lastUpdates: [RenewUpdate] {
        lock.lock()
        defer { lock.unlock() }
        return storedLastUpdates
    }

    func snapshotForRenew(completion: @escaping (Result<[RenewRowSnapshot], Error>) -> Void) {
        lock.lock()
        storedSnapshotCount += 1
        storedEvents.append(.snapshot)
        let snapshot = storedRows
        lock.unlock()
        completion(.success(snapshot))
    }

    func applyRenew(updates: [RenewUpdate], completion: @escaping (RenewApplyOutcome) -> Void) {
        lock.lock()
        storedApplyCount += 1
        storedLastUpdates = updates
        storedEvents.append(.apply(updates))
        let outcome = applyOutcomes.isEmpty ? RenewApplyOutcome(appliedCount: updates.count, changedCount: updates.count, saveError: nil) : applyOutcomes.removeFirst()
        if outcome.saveError == nil {
            for update in updates {
                if let index = storedRows.firstIndex(where: { $0.objectID == update.objectID }) {
                    let row = storedRows[index]
                    storedRows[index] = RenewRowSnapshot(
                        objectID: row.objectID, businessID: row.businessID,
                        fromSymbol: row.fromSymbol, toSymbol: row.toSymbol,
                        fromAmount: row.fromAmount, ratio: update.ratio
                    )
                }
            }
        }
        lock.unlock()
        completion(outcome)
    }

    func readHistory(completion: @escaping ([RenewHistoryValue]) -> Void) {
        lock.lock()
        storedReloadCount += 1
        storedEvents.append(.reload)
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
    private func makeContainer() -> NSPersistentContainer {
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
        return container
    }

    private func makeContext() -> NSManagedObjectContext {
        makeContainer().viewContext
    }

    @discardableResult
    private func renewAndReload(
        coordinator: AtomicRenewCoordinator,
        store: AtomicRenewStore,
        completion: @escaping (RenewRunResult, [ConvertHistoryUIBean]) -> Void
    ) -> Bool {
        coordinator.renew { result in
            guard result.accepted else {
                completion(result, [])
                return
            }
            RenewPresentationOrchestration.reload(from: store) { beans in
                completion(result, beans)
            }
        }
    }

    private func seedHistory(
        in context: NSManagedObjectContext,
        id: UUID?,
        ratio: Float32,
        fromSymbol: String = "USD",
        toSymbol: String = "TWD"
    ) {
        context.performAndWait {
            let object = NSEntityDescription.insertNewObject(forEntityName: "ConvertHistory", into: context)
            object.setValue(id, forKey: "id")
            object.setValue(Date(timeIntervalSince1970: 1), forKey: "date")
            object.setValue(fromSymbol, forKey: "fromSymbol")
            object.setValue(toSymbol, forKey: "toSymbol")
            object.setValue(Float32(2), forKey: "fromAmount")
            object.setValue(ratio, forKey: "ratio")
            object.setValue(Float32(0), forKey: "fxFee")
            try! context.save()
        }
    }

    func testRenewPublishesOneReloadAfterAtomicApply() {
        let row = RenewRowSnapshot(objectID: "row-1", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, ratio: 3)
        let store = CCS21StoreFixture(rows: [row])
        let converter = CCS21ConverterFixture()
        let coordinator = AtomicRenewCoordinator(store: store, converter: converter)

        let finished = expectation(description: "renew finished")
        let requestReady = expectation(description: "conversion requested")
        converter.onRequest = { requestReady.fulfill() }
        XCTAssertTrue(renewAndReload(coordinator: coordinator, store: store) { _, _ in finished.fulfill() })
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
        let coordinator = AtomicRenewCoordinator(store: store, converter: converter)

        let finished = expectation(description: "renew finished")
        let requestsReady = expectation(description: "conversions requested")
        let requestsReadyLock = NSLock()
        var requestsReadyFulfilled = false
        converter.onRequest = {
            guard converter.requestCount == 2 else { return }
            requestsReadyLock.lock()
            guard !requestsReadyFulfilled else {
                requestsReadyLock.unlock()
                return
            }
            requestsReadyFulfilled = true
            requestsReadyLock.unlock()
            requestsReady.fulfill()
        }
        XCTAssertTrue(renewAndReload(coordinator: coordinator, store: store) { _, _ in finished.fulfill() })
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
        let coordinator = AtomicRenewCoordinator(store: store, converter: converter)
        let first = expectation(description: "first renew")
        XCTAssertTrue(renewAndReload(coordinator: coordinator, store: store) { _, _ in first.fulfill() })
        wait(for: [first], timeout: 1)
        let firstIDs = store.lastUpdates.map(\.objectID)

        let second = expectation(description: "second renew")
        XCTAssertTrue(renewAndReload(coordinator: coordinator, store: store) { _, _ in second.fulfill() })
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
        let coordinator = AtomicRenewCoordinator(store: store, converter: converter)
        let finished = expectation(description: "renew finished")
        let requestReady = expectation(description: "failed conversion requested")
        converter.onRequest = { requestReady.fulfill() }
        XCTAssertTrue(renewAndReload(coordinator: coordinator, store: store) { _, _ in finished.fulfill() })
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
        let coordinator = AtomicRenewCoordinator(store: store, converter: converter)
        let finished = expectation(description: "renew finished")
        XCTAssertTrue(renewAndReload(coordinator: coordinator, store: store) { _, _ in finished.fulfill() })
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(converter.requestCount, 0)
        XCTAssertEqual(store.lastUpdates.count, 1)
        XCTAssertEqual(store.lastUpdates[0].ratio, 1, accuracy: 0.0001)
    }

    func testSaveFailureIsReportedAndReloadStillOccursOnce() {
        let row = RenewRowSnapshot(objectID: "row", businessID: UUID(), fromSymbol: "USD", toSymbol: "USD", fromAmount: 2, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        store.applyOutcomes = [RenewApplyOutcome(appliedCount: 0, changedCount: 0, saveError: CCS21TestError.save)]
        let coordinator = AtomicRenewCoordinator(store: store, converter: CCS21ConverterFixture())
        let finished = expectation(description: "renew finished")
        var result: RenewRunResult?
        XCTAssertTrue(renewAndReload(coordinator: coordinator, store: store) { renewResult, _ in
            result = renewResult
            finished.fulfill()
        })
        wait(for: [finished], timeout: 1)

        XCTAssertNotNil(result?.saveError)
        XCTAssertEqual(store.reloadCount, 1)
        XCTAssertEqual(store.rows, [row])
        XCTAssertEqual(store.rows.first?.businessID, row.businessID)
        XCTAssertEqual(store.rows.first?.ratio, row.ratio)
    }

    func testOverlappingRenewIsRejectedWithoutSecondSnapshot() {
        let row = RenewRowSnapshot(objectID: "row", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        let converter = CCS21ConverterFixture()
        let coordinator = AtomicRenewCoordinator(store: store, converter: converter)
        let requestReady = expectation(description: "conversion requested")
        converter.onRequest = { requestReady.fulfill() }
        let first = expectation(description: "first renew")
        XCTAssertTrue(renewAndReload(coordinator: coordinator, store: store) { _, _ in first.fulfill() })
        wait(for: [requestReady], timeout: 1)

        let overlap = expectation(description: "overlap rejected")
        var overlapResult: RenewRunResult?
        XCTAssertFalse(renewAndReload(coordinator: coordinator, store: store) { rejectedResult, _ in
            overlapResult = rejectedResult
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

    func testPresentationIdentityIsStableForNilBusinessIDAndPreservesBusinessID() {
        let businessID = UUID()
        let objectID = "x-coredata://store/ConvertHistory/p1"
        let fallbackID = RenewPresentationIdentity.id(businessID: nil, objectIDURI: objectID)
        XCTAssertEqual(fallbackID, RenewPresentationIdentity.id(businessID: nil, objectIDURI: objectID))
        XCTAssertNotEqual(
            fallbackID,
            RenewPresentationIdentity.id(businessID: nil, objectIDURI: "x-coredata://store/ConvertHistory/p2")
        )
        XCTAssertEqual(RenewPresentationIdentity.id(businessID: businessID, objectIDURI: objectID), businessID)
        XCTAssertEqual(fallbackID.uuid.6 & 0xF0, 0x80)
        XCTAssertEqual(fallbackID.uuid.8 & 0xC0, 0x80)
    }

    func testRepeatedReloadOfNilBusinessIDUsesStableObjectIDPresentationID() {
        let objectID = "x-coredata://store/ConvertHistory/p1"
        let store = CCS21StoreFixture(rows: [])
        store.reloadValues = [RenewHistoryValue(
            objectID: objectID, id: nil, title: nil, url: nil,
            fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, fxFee: 0, ratio: 4
        )]
        var firstBeans: [ConvertHistoryUIBean] = []
        let firstReload = expectation(description: "first reload")
        RenewPresentationOrchestration.reload(from: store) { beans in
            firstBeans = beans
            firstReload.fulfill()
        }
        wait(for: [firstReload], timeout: 1)
        let firstID = firstBeans.first?.id

        let secondReload = expectation(description: "second reload")
        var secondBeans: [ConvertHistoryUIBean] = []
        RenewPresentationOrchestration.reload(from: store) { beans in
            secondBeans = beans
            secondReload.fulfill()
        }
        wait(for: [secondReload], timeout: 1)

        XCTAssertEqual(store.reloadCount, 2)
        XCTAssertEqual(secondBeans.first?.id, firstID)
        XCTAssertEqual(secondBeans.first?.id, RenewPresentationIdentity.id(businessID: nil, objectIDURI: objectID))
    }

    func testNilBusinessIDReloadFallbackDeletesExactRowAndBusinessIDDeleteStillWorks() {
        let container = makeContainer()
        let context = container.newBackgroundContext()
        let businessID = UUID()
        seedHistory(in: context, id: nil, ratio: 1)
        seedHistory(in: context, id: nil, ratio: 2)
        seedHistory(in: context, id: businessID, ratio: 3)
        let manager = CHDataManager(context: context)

        let reloaded = expectation(description: "history reloaded")
        var values: [RenewHistoryValue] = []
        var beans: [ConvertHistoryUIBean] = []
        manager.readHistory { history in
            values = history
            RenewPresentationOrchestration.reload(from: manager) { presented in
                beans = presented
                reloaded.fulfill()
            }
        }
        wait(for: [reloaded], timeout: 1)

        let nilValues = values.filter { $0.id == nil }
        XCTAssertEqual(nilValues.count, 2)
        let deletedValue = try! XCTUnwrap(nilValues.first)
        let deletedFallbackID = try! XCTUnwrap(beans.first { $0.id == RenewPresentationIdentity.id(businessID: nil, objectIDURI: deletedValue.objectID) }?.id)
        manager.wipeById(deletedFallbackID)

        let afterFallbackDelete = expectation(description: "fallback row deleted")
        var remainingAfterFallback: [RenewHistoryValue] = []
        manager.readHistory { remainingAfterFallback = $0; afterFallbackDelete.fulfill() }
        wait(for: [afterFallbackDelete], timeout: 1)
        XCTAssertEqual(remainingAfterFallback.count, 2)
        XCTAssertFalse(remainingAfterFallback.contains { $0.objectID == deletedValue.objectID })
        XCTAssertEqual(remainingAfterFallback.filter { $0.id == nil }.count, 1)

        manager.wipeById(businessID)
        let afterBusinessDelete = expectation(description: "business row deleted")
        var remainingAfterBusinessDelete: [RenewHistoryValue] = []
        manager.readHistory { remainingAfterBusinessDelete = $0; afterBusinessDelete.fulfill() }
        wait(for: [afterBusinessDelete], timeout: 1)
        XCTAssertEqual(remainingAfterBusinessDelete.count, 1)
        XCTAssertNil(remainingAfterBusinessDelete.first?.id)
    }

    func testSnapshotMakesUnsavedInsertedRowPermanentWithoutAssigningBusinessID() {
        let container = makeContainer()
        let context = container.newBackgroundContext()
        context.performAndWait {
            let object = NSEntityDescription.insertNewObject(forEntityName: "ConvertHistory", into: context)
            object.setValue(nil, forKey: "id")
            object.setValue(Date(timeIntervalSince1970: 1), forKey: "date")
            object.setValue("USD", forKey: "fromSymbol")
            object.setValue("TWD", forKey: "toSymbol")
            object.setValue(Float32(2), forKey: "fromAmount")
            object.setValue(Float32(4), forKey: "ratio")
            object.setValue(Float32(0), forKey: "fxFee")
            XCTAssertTrue(object.objectID.isTemporaryID)
        }
        let manager = CHDataManager(context: context)

        let firstSnapshot = expectation(description: "permanent snapshot")
        var firstRow: RenewRowSnapshot?
        manager.snapshotForRenew {
            if case .success(let rows) = $0 { firstRow = rows.first }
            firstSnapshot.fulfill()
        }
        wait(for: [firstSnapshot], timeout: 1)
        let row = try! XCTUnwrap(firstRow)
        XCTAssertNil(row.businessID)

        let applied = expectation(description: "inserted row saved")
        manager.applyRenew(updates: [RenewUpdate(objectID: row.objectID, businessID: nil, ratio: 2)]) { outcome in
            XCTAssertEqual(outcome.changedCount, 1)
            XCTAssertNil(outcome.saveError)
            applied.fulfill()
        }
        wait(for: [applied], timeout: 1)

        let secondSnapshot = expectation(description: "saved snapshot")
        var secondRow: RenewRowSnapshot?
        manager.snapshotForRenew {
            if case .success(let rows) = $0 { secondRow = rows.first }
            secondSnapshot.fulfill()
        }
        wait(for: [secondSnapshot], timeout: 1)
        XCTAssertEqual(secondRow?.objectID, row.objectID)
        XCTAssertNil(secondRow?.businessID)
        XCTAssertEqual(secondRow?.ratio, 2)
    }

    func testDedicatedRenewSaveLeavesUnrelatedViewContextEditPending() {
        let container = makeContainer()
        let viewContext = container.viewContext
        let renewID = UUID()
        let unrelatedID = UUID()
        seedHistory(in: viewContext, id: renewID, ratio: 4)
        seedHistory(in: viewContext, id: unrelatedID, ratio: 8)
        viewContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ConvertHistory")
            request.predicate = NSPredicate(format: "id == %@", unrelatedID as CVarArg)
            try! viewContext.fetch(request).first!.setValue("pending", forKey: "title")
            XCTAssertTrue(viewContext.hasChanges)
        }

        let renewContext = container.newBackgroundContext()
        let manager = CHDataManager(context: renewContext)
        let snapshot = expectation(description: "snapshot")
        var row: RenewRowSnapshot?
        manager.snapshotForRenew {
            if case .success(let rows) = $0 { row = rows.first(where: { $0.businessID == renewID }) }
            snapshot.fulfill()
        }
        wait(for: [snapshot], timeout: 1)
        let updateRow = try! XCTUnwrap(row)

        let applied = expectation(description: "renew save")
        manager.applyRenew(updates: [RenewUpdate(objectID: updateRow.objectID, businessID: renewID, ratio: 2)]) { outcome in
            XCTAssertEqual(outcome.changedCount, 1)
            XCTAssertNil(outcome.saveError)
            applied.fulfill()
        }
        wait(for: [applied], timeout: 1)

        viewContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ConvertHistory")
            request.predicate = NSPredicate(format: "id == %@", unrelatedID as CVarArg)
            let object = try! viewContext.fetch(request).first
            XCTAssertEqual(object?.value(forKey: "title") as? String, "pending")
            XCTAssertTrue(viewContext.hasChanges)
        }
    }

    func testDedicatedRenewSaveFailureLeavesUnrelatedViewContextEditPending() {
        let container = makeContainer()
        let viewContext = container.viewContext
        let renewID = UUID()
        let unrelatedID = UUID()
        seedHistory(in: viewContext, id: renewID, ratio: 4)
        seedHistory(in: viewContext, id: unrelatedID, ratio: 8)
        viewContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ConvertHistory")
            request.predicate = NSPredicate(format: "id == %@", unrelatedID as CVarArg)
            try! viewContext.fetch(request).first!.setValue("pending", forKey: "title")
        }

        let renewContext = container.newBackgroundContext()
        let manager = CHDataManager(context: renewContext, saveOperation: { throw CCS21TestError.save })
        let snapshot = expectation(description: "snapshot")
        var row: RenewRowSnapshot?
        manager.snapshotForRenew {
            if case .success(let rows) = $0 { row = rows.first(where: { $0.businessID == renewID }) }
            snapshot.fulfill()
        }
        wait(for: [snapshot], timeout: 1)
        let updateRow = try! XCTUnwrap(row)

        let failed = expectation(description: "renew save failure")
        manager.applyRenew(updates: [RenewUpdate(objectID: updateRow.objectID, businessID: renewID, ratio: 2)]) { outcome in
            XCTAssertEqual(outcome.changedCount, 0)
            XCTAssertNotNil(outcome.saveError)
            failed.fulfill()
        }
        wait(for: [failed], timeout: 1)

        renewContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ConvertHistory")
            request.predicate = NSPredicate(format: "id == %@", renewID as CVarArg)
            let object = try! renewContext.fetch(request).first
            XCTAssertEqual(object?.value(forKey: "ratio") as? Float32, 4)
        }
        viewContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "ConvertHistory")
            request.predicate = NSPredicate(format: "id == %@", unrelatedID as CVarArg)
            let object = try! viewContext.fetch(request).first
            XCTAssertEqual(object?.value(forKey: "title") as? String, "pending")
            XCTAssertTrue(viewContext.hasChanges)
        }
    }

    func testCoreDataRepeatedRenewPreservesIdentityCountAndSavesOnlyChangedRatios() {
        let container = makeContainer()
        let context = container.newBackgroundContext()
        let firstID = UUID()
        let secondID = UUID()
        seedHistory(in: context, id: firstID, ratio: 4, fromSymbol: "USD", toSymbol: "USD")
        seedHistory(in: context, id: secondID, ratio: 8, fromSymbol: "USD", toSymbol: "USD")
        var saveCalls = 0
        let saveLock = NSLock()
        let manager = CHDataManager(context: context, saveOperation: {
            saveLock.lock()
            saveCalls += 1
            saveLock.unlock()
            try context.save()
        })
        let coordinator = AtomicRenewCoordinator(store: manager, converter: CCS21ConverterFixture())

        let firstRenew = expectation(description: "first renew")
        var firstResult: RenewRunResult?
        var firstBeans: [ConvertHistoryUIBean] = []
        XCTAssertTrue(renewAndReload(coordinator: coordinator, store: manager) {
            firstResult = $0
            firstBeans = $1
            firstRenew.fulfill()
        })
        wait(for: [firstRenew], timeout: 1)
        XCTAssertEqual(firstResult?.changedCount, 2)
        let firstIDs = firstBeans.map(\.id)
        XCTAssertEqual(Set(firstIDs), Set([firstID, secondID]))

        let secondRenew = expectation(description: "second renew")
        var secondResult: RenewRunResult?
        var secondBeans: [ConvertHistoryUIBean] = []
        XCTAssertTrue(renewAndReload(coordinator: coordinator, store: manager) {
            secondResult = $0
            secondBeans = $1
            secondRenew.fulfill()
        })
        wait(for: [secondRenew], timeout: 1)
        XCTAssertEqual(secondResult?.changedCount, 0)
        XCTAssertEqual(secondBeans.map(\.id), firstIDs)

        context.performAndWait {
            let objects = try! context.fetch(NSFetchRequest<NSManagedObject>(entityName: "ConvertHistory"))
            XCTAssertEqual(objects.count, 2)
            XCTAssertEqual(Set(objects.compactMap { $0.value(forKey: "id") as? UUID }), Set([firstID, secondID]))
        }
        saveLock.lock()
        XCTAssertEqual(saveCalls, 1)
        saveLock.unlock()
    }
}
