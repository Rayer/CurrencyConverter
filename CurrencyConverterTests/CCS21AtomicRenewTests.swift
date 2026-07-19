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
    var snapshotError: Error?
    var reloadError: Error?
    var duplicateSnapshotCallback = false
    var duplicateApplyCallback = false
    var duplicateReadCallback = false
    var suppressSnapshotCallback = false
    var suppressApplyCallback = false
    var suppressReadCallback = false
    var snapshotCompletion: ((Result<[RenewRowSnapshot], Error>) -> Void)?
    var applyCompletion: ((RenewApplyOutcome) -> Void)?
    var readCompletion: ((Result<[RenewHistoryValue], Error>) -> Void)?
    var onApply: (() -> Void)?
    var onRead: (() -> Void)?

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
        snapshotCompletion = completion
        lock.unlock()
        if suppressSnapshotCallback { return }
        let result = snapshotError.map { Result<[RenewRowSnapshot], Error>.failure($0) }
            ?? .success(snapshot)
        completion(result)
        if duplicateSnapshotCallback { completion(result) }
    }

    func applyRenew(updates: [RenewUpdate], completion: @escaping (RenewApplyOutcome) -> Void) {
        lock.lock()
        storedApplyCount += 1
        storedLastUpdates = updates
        storedEvents.append(.apply(updates))
        let outcome = applyOutcomes.isEmpty ? RenewApplyOutcome(appliedCount: updates.count, changedCount: updates.count, saveError: nil) : applyOutcomes.removeFirst()
        applyCompletion = completion
        if outcome.saveError == nil {
            for update in updates {
                if let index = storedRows.firstIndex(where: { $0.objectID == update.objectID }) {
                    let row = storedRows[index]
                    if row.businessID == update.businessID,
                       row.fromSymbol == update.originalFromSymbol,
                       row.toSymbol == update.originalToSymbol,
                       row.fromAmount.bitPattern == update.originalFromAmountBitPattern,
                       row.ratio.bitPattern == update.originalRatioBitPattern {
                        storedRows[index] = RenewRowSnapshot(
                            objectID: row.objectID, businessID: row.businessID,
                            fromSymbol: row.fromSymbol, toSymbol: row.toSymbol,
                            fromAmount: row.fromAmount, ratio: update.ratio
                        )
                    }
                }
            }
        }
        lock.unlock()
        onApply?()
        if suppressApplyCallback { return }
        completion(outcome)
        if duplicateApplyCallback { completion(outcome) }
    }

    func readHistory(completion: @escaping (Result<[RenewHistoryValue], Error>) -> Void) {
        lock.lock()
        storedReloadCount += 1
        storedEvents.append(.reload)
        readCompletion = completion
        lock.unlock()
        onRead?()
        if suppressReadCallback { return }
        let result = reloadError.map { Result<[RenewHistoryValue], Error>.failure($0) }
            ?? .success(reloadValues)
        completion(result)
        if duplicateReadCallback { completion(result) }
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

private final class CCS21ManualRenewScheduler: AtomicRenewScheduler {
    private final class Task: AtomicRenewScheduledTask {
        let action: () -> Void
        private(set) var isCancelled = false

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }

        func fire() {
            action()
        }
    }

    private let lock = NSLock()
    private var storedTasks: [Task] = []

    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> AtomicRenewScheduledTask {
        _ = delay
        let task = Task(action: action)
        lock.lock()
        storedTasks.append(task)
        lock.unlock()
        return task
    }

    func fire() {
        lock.lock()
        let task = storedTasks.first
        lock.unlock()
        task?.fire()
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
        let workflow = AtomicRenewWorkflow(store: store, converter: converter)

        let finished = expectation(description: "renew finished")
        let requestReady = expectation(description: "conversion requested")
        converter.onRequest = { requestReady.fulfill() }
        XCTAssertTrue(workflow.renew { _, _ in finished.fulfill() })
        XCTAssertEqual(store.events, [.snapshot])
        wait(for: [requestReady], timeout: 1)
        XCTAssertEqual(converter.requestCount, 1)

        converter.finish(0, amount: 80)
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(store.events.count, 3)
        XCTAssertEqual(store.events[0], .snapshot)
        XCTAssertEqual(store.events[2], .reload)
    }

    func testDuplicateSnapshotApplyAndReadCallbacksSettleExactlyOnce() {
        let row = RenewRowSnapshot(objectID: "row", businessID: UUID(), fromSymbol: "USD", toSymbol: "USD", fromAmount: 2, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        store.duplicateSnapshotCallback = true
        store.duplicateApplyCallback = true
        store.duplicateReadCallback = true
        let workflow = AtomicRenewWorkflow(store: store, converter: CCS21ConverterFixture())
        let finished = expectation(description: "renew finished")
        var completionCount = 0

        XCTAssertTrue(workflow.renew { _, values in
            completionCount += 1
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertNotNil(values)
            finished.fulfill()
        })
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(store.snapshotCount, 1)
        XCTAssertEqual(store.applyCount, 1)
        XCTAssertEqual(store.reloadCount, 1)
    }

    func testWorkflowRemainsInFlightUntilCompletionCallbackReturns() {
        let row = RenewRowSnapshot(
            objectID: "row", businessID: UUID(),
            fromSymbol: "USD", toSymbol: "USD", fromAmount: 2, ratio: 4
        )
        let store = CCS21StoreFixture(rows: [row])
        let workflow = AtomicRenewWorkflow(store: store, converter: CCS21ConverterFixture())
        let firstFinished = expectation(description: "first completion")
        let overlapRejected = expectation(description: "completion-time overlap rejected")
        var overlapWasAccepted = true

        XCTAssertTrue(workflow.renew { _, _ in
            overlapWasAccepted = workflow.renew { result, values in
                XCTAssertFalse(result.accepted)
                XCTAssertNil(values)
                overlapRejected.fulfill()
            }
            firstFinished.fulfill()
        })
        wait(for: [firstFinished, overlapRejected], timeout: 1)
        XCTAssertFalse(overlapWasAccepted)

        let nextFinished = expectation(description: "next run after callback")
        XCTAssertTrue(workflow.renew { result, _ in
            XCTAssertTrue(result.accepted)
            nextFinished.fulfill()
        })
        wait(for: [nextFinished], timeout: 1)
    }

    func testMissingSnapshotConverterAndApplyCallbacksTimeoutAndIgnoreLateCallbacks() {
        let row = RenewRowSnapshot(objectID: "row", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, ratio: 4)
        let scheduler = CCS21ManualRenewScheduler()
        let store = CCS21StoreFixture(rows: [row])
        store.suppressSnapshotCallback = true
        let converter = CCS21ConverterFixture()
        var workflow: AtomicRenewWorkflow? = AtomicRenewWorkflow(
            store: store, converter: converter, scheduler: scheduler
        )
        let snapshotFinished = expectation(description: "snapshot timeout")
        var snapshotResult: RenewRunResult?
        XCTAssertTrue(workflow!.renew { result, values in
            snapshotResult = result
            XCTAssertNil(values)
            snapshotFinished.fulfill()
        })
        scheduler.fire()
        wait(for: [snapshotFinished], timeout: 1)
        XCTAssertEqual(snapshotResult?.timeoutError, .expired(.snapshot))
        XCTAssertEqual(store.applyCount, 0)
        store.snapshotCompletion?(.success([row]))
        XCTAssertEqual(store.applyCount, 0)

        let converterScheduler = CCS21ManualRenewScheduler()
        let converterStore = CCS21StoreFixture(rows: [row])
        let converterWorkflow = AtomicRenewWorkflow(
            store: converterStore, converter: converter, scheduler: converterScheduler
        )
        let converterFinished = expectation(description: "converter timeout")
        let converterRequested = expectation(description: "converter requested")
        converter.onRequest = { converterRequested.fulfill() }
        var converterResult: RenewRunResult?
        XCTAssertTrue(converterWorkflow.renew { result, values in
            converterResult = result
            XCTAssertNil(values)
            converterFinished.fulfill()
        })
        wait(for: [converterRequested], timeout: 1)
        XCTAssertEqual(converter.requestCount, 1)
        converterScheduler.fire()
        wait(for: [converterFinished], timeout: 1)
        XCTAssertEqual(converterResult?.timeoutError, .expired(.conversion))
        converter.finish(0, amount: 10)
        XCTAssertEqual(converterStore.applyCount, 0)

        let applyScheduler = CCS21ManualRenewScheduler()
        let applyStore = CCS21StoreFixture(rows: [RenewRowSnapshot(objectID: "same", businessID: nil, fromSymbol: "USD", toSymbol: "USD", fromAmount: 2, ratio: 4)])
        applyStore.suppressApplyCallback = true
        let applyWorkflow = AtomicRenewWorkflow(
            store: applyStore, converter: CCS21ConverterFixture(), scheduler: applyScheduler
        )
        let applyFinished = expectation(description: "apply timeout")
        let applyStarted = expectation(description: "apply started")
        applyStore.onApply = { applyStarted.fulfill() }
        var applyResult: RenewRunResult?
        XCTAssertTrue(applyWorkflow.renew { result, values in
            applyResult = result
            XCTAssertNil(values)
            applyFinished.fulfill()
        })
        wait(for: [applyStarted], timeout: 1)
        XCTAssertEqual(applyStore.applyCount, 1)
        applyScheduler.fire()
        wait(for: [applyFinished], timeout: 1)
        XCTAssertEqual(applyResult?.timeoutError, .expired(.apply))
        applyStore.applyCompletion?(RenewApplyOutcome(appliedCount: 1, changedCount: 1, saveError: nil))
        XCTAssertEqual(applyStore.reloadCount, 0)

        workflow = nil
    }

    func testWorkflowRetainsOperationUntilTimeoutThenReleasesWorkflow() {
        let row = RenewRowSnapshot(objectID: "row", businessID: nil, fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        store.suppressSnapshotCallback = true
        let scheduler = CCS21ManualRenewScheduler()
        weak var weakWorkflow: AtomicRenewWorkflow?
        var workflow: AtomicRenewWorkflow? = AtomicRenewWorkflow(
            store: store, converter: CCS21ConverterFixture(), scheduler: scheduler
        )
        weakWorkflow = workflow
        let finished = expectation(description: "retained workflow finished")
        XCTAssertTrue(workflow!.renew { _, _ in finished.fulfill() })
        workflow = nil
        XCTAssertNotNil(weakWorkflow)
        scheduler.fire()
        wait(for: [finished], timeout: 1)
        XCTAssertNil(weakWorkflow)
    }

    func testOverlapRemainsRejectedUntilDelayedReadSettles() {
        let row = RenewRowSnapshot(objectID: "row", businessID: nil, fromSymbol: "USD", toSymbol: "USD", fromAmount: 2, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        store.suppressReadCallback = true
        let readStarted = expectation(description: "read started")
        store.onRead = { readStarted.fulfill() }
        let workflow = AtomicRenewWorkflow(store: store, converter: CCS21ConverterFixture())
        let firstFinished = expectation(description: "first renew")
        XCTAssertTrue(workflow.renew { _, _ in firstFinished.fulfill() })
        wait(for: [readStarted], timeout: 1)
        XCTAssertEqual(store.reloadCount, 1)

        let overlapFinished = expectation(description: "overlap rejected")
        var overlapResult: RenewRunResult?
        XCTAssertFalse(workflow.renew { result, _ in
            overlapResult = result
            overlapFinished.fulfill()
        })
        wait(for: [overlapFinished], timeout: 1)
        XCTAssertFalse(overlapResult?.accepted ?? true)
        XCTAssertEqual(store.snapshotCount, 1)

        store.readCompletion?(.success(store.reloadValues))
        wait(for: [firstFinished], timeout: 1)
    }

    func testOutOfOrderCallbacksApplyEachOriginalRowOnceAndReloadOnce() {
        let first = RenewRowSnapshot(objectID: "row-1", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, ratio: 3)
        let second = RenewRowSnapshot(objectID: "row-2", businessID: UUID(), fromSymbol: "JPY", toSymbol: "USD", fromAmount: 100, ratio: 4)
        let store = CCS21StoreFixture(rows: [first, second])
        let converter = CCS21ConverterFixture()
        let workflow = AtomicRenewWorkflow(store: store, converter: converter)

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
        XCTAssertTrue(workflow.renew { _, _ in finished.fulfill() })
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
        let workflow = AtomicRenewWorkflow(store: store, converter: converter)
        let first = expectation(description: "first renew")
        XCTAssertTrue(workflow.renew { _, _ in first.fulfill() })
        wait(for: [first], timeout: 1)
        let firstIDs = store.lastUpdates.map(\.objectID)

        let second = expectation(description: "second renew")
        XCTAssertTrue(workflow.renew { _, _ in second.fulfill() })
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
        let workflow = AtomicRenewWorkflow(store: store, converter: converter)
        let finished = expectation(description: "renew finished")
        let requestReady = expectation(description: "failed conversion requested")
        converter.onRequest = { requestReady.fulfill() }
        XCTAssertTrue(workflow.renew { _, _ in finished.fulfill() })
        wait(for: [requestReady], timeout: 1)
        converter.finish(0, amount: .nan, error: CCS21TestError.conversion)
        converter.finish(0, amount: 10)
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(store.lastUpdates.count, 1)
        XCTAssertEqual(store.lastUpdates[0].objectID, "same")
        XCTAssertEqual(store.lastUpdates[0].ratio, 1, accuracy: 0.0001)
        XCTAssertEqual(converter.requestCount, 1)
    }

    func testZeroConvertedAmountLeavesRowUnchanged() {
        let row = RenewRowSnapshot(objectID: "zero-result", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, ratio: 9)
        let store = CCS21StoreFixture(rows: [row])
        let converter = CCS21ConverterFixture()
        let workflow = AtomicRenewWorkflow(store: store, converter: converter)
        let requestReady = expectation(description: "conversion requested")
        let finished = expectation(description: "renew finished")
        converter.onRequest = { requestReady.fulfill() }

        XCTAssertTrue(workflow.renew { _, _ in finished.fulfill() })
        wait(for: [requestReady], timeout: 1)
        converter.finish(0, amount: 0)
        wait(for: [finished], timeout: 1)

        XCTAssertTrue(store.lastUpdates.isEmpty)
        XCTAssertEqual(store.rows, [row])
    }

    func testSignInconsistentConvertedAmountLeavesRowUnchanged() {
        let row = RenewRowSnapshot(objectID: "sign-inconsistent", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: -2, ratio: 9)
        let store = CCS21StoreFixture(rows: [row])
        let converter = CCS21ConverterFixture()
        let workflow = AtomicRenewWorkflow(store: store, converter: converter)
        let requestReady = expectation(description: "conversion requested")
        let finished = expectation(description: "renew finished")
        converter.onRequest = { requestReady.fulfill() }

        XCTAssertTrue(workflow.renew { _, _ in finished.fulfill() })
        wait(for: [requestReady], timeout: 1)
        converter.finish(0, amount: 10)
        wait(for: [finished], timeout: 1)

        XCTAssertTrue(store.lastUpdates.isEmpty)
        XCTAssertEqual(store.rows, [row])
    }

    func testNegativeSourceAndNegativeConvertedAmountProducesPositiveRatio() {
        let row = RenewRowSnapshot(objectID: "negative-ratio", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: -2, ratio: 9)
        let store = CCS21StoreFixture(rows: [row])
        let converter = CCS21ConverterFixture()
        let workflow = AtomicRenewWorkflow(store: store, converter: converter)
        let requestReady = expectation(description: "conversion requested")
        let finished = expectation(description: "renew finished")
        converter.onRequest = { requestReady.fulfill() }

        XCTAssertTrue(workflow.renew { _, _ in finished.fulfill() })
        wait(for: [requestReady], timeout: 1)
        converter.finish(0, amount: -10)
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(store.lastUpdates.count, 1)
        XCTAssertEqual(store.lastUpdates[0].ratio, 5, accuracy: 0.0001)
    }

    func testSameCurrencyDoesNotCallConverterAndCallbackIsConsumedOnce() {
        let row = RenewRowSnapshot(objectID: "same", businessID: UUID(), fromSymbol: "USD", toSymbol: "USD", fromAmount: 20, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        let converter = CCS21ConverterFixture()
        let workflow = AtomicRenewWorkflow(store: store, converter: converter)
        let finished = expectation(description: "renew finished")
        XCTAssertTrue(workflow.renew { _, _ in finished.fulfill() })
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(converter.requestCount, 0)
        XCTAssertEqual(store.lastUpdates.count, 1)
        XCTAssertEqual(store.lastUpdates[0].ratio, 1, accuracy: 0.0001)
    }

    func testSameCurrencyZeroAndNonFiniteSourcesStillNormalizeToOneWithoutConverter() {
        let rows = [
            RenewRowSnapshot(objectID: "zero-same", businessID: nil, fromSymbol: "USD", toSymbol: "USD", fromAmount: 0, ratio: 7),
            RenewRowSnapshot(objectID: "nan-same", businessID: nil, fromSymbol: "EUR", toSymbol: "EUR", fromAmount: .nan, ratio: 8),
            RenewRowSnapshot(objectID: "infinity-same", businessID: nil, fromSymbol: "JPY", toSymbol: "JPY", fromAmount: .infinity, ratio: 9)
        ]
        let store = CCS21StoreFixture(rows: rows)
        let converter = CCS21ConverterFixture()
        let workflow = AtomicRenewWorkflow(store: store, converter: converter)
        let finished = expectation(description: "same-currency exception finished")
        XCTAssertTrue(workflow.renew { _, _ in finished.fulfill() })
        wait(for: [finished], timeout: 1)

        XCTAssertEqual(converter.requestCount, 0)
        XCTAssertEqual(store.lastUpdates.map(\.ratio), [1, 1, 1])
    }

    func testSaveFailureIsReportedAndReloadStillOccursOnce() {
        let row = RenewRowSnapshot(objectID: "row", businessID: UUID(), fromSymbol: "USD", toSymbol: "USD", fromAmount: 2, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        store.applyOutcomes = [RenewApplyOutcome(appliedCount: 0, changedCount: 0, saveError: CCS21TestError.save)]
        let workflow = AtomicRenewWorkflow(store: store, converter: CCS21ConverterFixture())
        let finished = expectation(description: "renew finished")
        var result: RenewRunResult?
        XCTAssertTrue(workflow.renew { renewResult, _ in
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

    func testReadFailureIsTypedAndNeverPublishedAsEmptyHistory() {
        let row = RenewRowSnapshot(objectID: "row", businessID: nil, fromSymbol: "USD", toSymbol: "USD", fromAmount: 2, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        store.reloadValues = [RenewHistoryValue(
            objectID: "persistent-row", id: nil, title: nil, url: nil,
            fromSymbol: "USD", toSymbol: "USD", fromAmount: 2, fxFee: 0, ratio: 4
        )]
        store.reloadError = CCS21TestError.save
        let workflow = AtomicRenewWorkflow(store: store, converter: CCS21ConverterFixture())
        let finished = expectation(description: "read failure finished")
        var result: RenewRunResult?
        var history: [RenewHistoryValue]?
        XCTAssertTrue(workflow.renew { renewResult, values in
            result = renewResult
            history = values
            finished.fulfill()
        })
        wait(for: [finished], timeout: 1)

        XCTAssertNotNil(result?.historyError)
        XCTAssertNil(history)
        XCTAssertNil(result?.saveError)
        XCTAssertEqual(store.reloadCount, 1)

        let reloaded = expectation(description: "ordinary reload failure")
        var ordinaryReload: Result<[ConvertHistoryUIBean], Error>?
        RenewPresentationOrchestration.reload(from: store) {
            ordinaryReload = $0
            reloaded.fulfill()
        }
        wait(for: [reloaded], timeout: 1)
        if case .success = ordinaryReload {
            XCTFail("read failure must not publish an empty successful history")
        }
    }

    func testSnapshotFailureIsTypedAndSkipsApplyAndHistory() {
        let row = RenewRowSnapshot(objectID: "row", businessID: nil, fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        store.snapshotError = CCS21TestError.save
        let workflow = AtomicRenewWorkflow(store: store, converter: CCS21ConverterFixture())
        let finished = expectation(description: "snapshot failure finished")
        var result: RenewRunResult?
        var history: [RenewHistoryValue]?
        XCTAssertTrue(workflow.renew { renewResult, values in
            result = renewResult
            history = values
            finished.fulfill()
        })
        wait(for: [finished], timeout: 1)

        XCTAssertNotNil(result?.snapshotError)
        XCTAssertNil(result?.saveError)
        XCTAssertNil(history)
        XCTAssertEqual(store.applyCount, 0)
        XCTAssertEqual(store.reloadCount, 0)
    }

    func testOverlappingRenewIsRejectedWithoutSecondSnapshot() {
        let row = RenewRowSnapshot(objectID: "row", businessID: UUID(), fromSymbol: "USD", toSymbol: "TWD", fromAmount: 2, ratio: 4)
        let store = CCS21StoreFixture(rows: [row])
        let converter = CCS21ConverterFixture()
        let workflow = AtomicRenewWorkflow(store: store, converter: converter)
        let requestReady = expectation(description: "conversion requested")
        converter.onRequest = { requestReady.fulfill() }
        let first = expectation(description: "first renew")
        XCTAssertTrue(workflow.renew { _, _ in first.fulfill() })
        wait(for: [requestReady], timeout: 1)

        let overlap = expectation(description: "overlap rejected")
        var overlapResult: RenewRunResult?
        XCTAssertFalse(workflow.renew { rejectedResult, _ in
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
        manager.applyRenew(updates: [RenewUpdate(row: row, ratio: 2)]) { outcome in
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
        manager.applyRenew(updates: [RenewUpdate(row: row, ratio: 2)]) { outcome in
            XCTAssertEqual(outcome.changedCount, 0)
            repeated.fulfill()
        }
        wait(for: [repeated], timeout: 1)
        saveLock.lock()
        XCTAssertEqual(saveCalls, 1)
        saveLock.unlock()
    }

    func testRenewUpdateCapturesImmutableSourceFixture() {
        let businessID = UUID()
        let row = RenewRowSnapshot(
            objectID: "object", businessID: businessID, fromSymbol: "USD", toSymbol: "TWD",
            fromAmount: -0.0, ratio: .nan
        )
        let update = RenewUpdate(row: row, ratio: 2)

        XCTAssertEqual(update.objectID, row.objectID)
        XCTAssertEqual(update.businessID, businessID)
        XCTAssertEqual(update.originalFromSymbol, row.fromSymbol)
        XCTAssertEqual(update.originalToSymbol, row.toSymbol)
        XCTAssertEqual(update.originalFromAmountBitPattern, row.fromAmount.bitPattern)
        XCTAssertEqual(update.originalRatioBitPattern, row.ratio.bitPattern)
    }

    func testExternalSymbolAmountAndRatioEditsSkipOnlyStaleRows() {
        let container = makeContainer()
        let seedContext = container.viewContext
        let symbolID = UUID()
        let amountID = UUID()
        let ratioID = UUID()
        seedHistory(in: seedContext, id: symbolID, ratio: 4)
        seedHistory(in: seedContext, id: amountID, ratio: 5)
        seedHistory(in: seedContext, id: ratioID, ratio: 6)

        let renewContext = container.newBackgroundContext()
        let manager = CHDataManager(context: renewContext)
        let snapshotFinished = expectation(description: "snapshot")
        var rows: [RenewRowSnapshot] = []
        manager.snapshotForRenew {
            if case .success(let snapshot) = $0 { rows = snapshot }
            snapshotFinished.fulfill()
        }
        wait(for: [snapshotFinished], timeout: 1)
        XCTAssertEqual(rows.count, 3)

        let external = container.newBackgroundContext()
        external.performAndWait {
            let request = NSFetchRequest<ConvertHistory>(entityName: "ConvertHistory")
            let objects = try! external.fetch(request)
            objects.first { $0.id == symbolID }?.fromSymbol = "EUR"
            objects.first { $0.id == amountID }?.fromAmount = 9
            objects.first { $0.id == ratioID }?.ratio = 10
            try! external.save()
        }

        let applied = expectation(description: "stale rows skipped")
        manager.applyRenew(updates: rows.map { RenewUpdate(row: $0, ratio: $0.ratio + 1) }) { outcome in
            XCTAssertEqual(outcome.appliedCount, 0)
            XCTAssertEqual(outcome.changedCount, 0)
            XCTAssertNil(outcome.saveError)
            applied.fulfill()
        }
        wait(for: [applied], timeout: 1)

        let reloaded = expectation(description: "external edits remain")
        manager.readHistory { result in
            guard case .success(let values) = result else {
                XCTFail("external edits should remain readable")
                reloaded.fulfill()
                return
            }
            XCTAssertEqual(values.first { $0.id == symbolID }?.fromSymbol, "EUR")
            XCTAssertEqual(values.first { $0.id == amountID }?.fromAmount, 9)
            XCTAssertEqual(values.first { $0.id == ratioID }?.ratio, 10)
            reloaded.fulfill()
        }
        wait(for: [reloaded], timeout: 1)
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
        manager.applyRenew(updates: [RenewUpdate(row: row, ratio: 2)]) { outcome in
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

    func testPresentationIdentityIsStableAndIndependentOfBusinessID() {
        let objectID = "x-coredata://store/ConvertHistory/p1"
        let fallbackID = RenewPresentationIdentity.id(objectIDURI: objectID)
        XCTAssertEqual(fallbackID, RenewPresentationIdentity.id(objectIDURI: objectID))
        XCTAssertNotEqual(
            fallbackID,
            RenewPresentationIdentity.id(objectIDURI: "x-coredata://store/ConvertHistory/p2")
        )
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
        RenewPresentationOrchestration.reload(from: store) { result in
            if case .success(let beans) = result { firstBeans = beans }
            firstReload.fulfill()
        }
        wait(for: [firstReload], timeout: 1)
        let firstID = firstBeans.first?.id

        let secondReload = expectation(description: "second reload")
        var secondBeans: [ConvertHistoryUIBean] = []
        RenewPresentationOrchestration.reload(from: store) { result in
            if case .success(let beans) = result { secondBeans = beans }
            secondReload.fulfill()
        }
        wait(for: [secondReload], timeout: 1)

        XCTAssertEqual(store.reloadCount, 2)
        XCTAssertEqual(secondBeans.first?.id, firstID)
        XCTAssertEqual(secondBeans.first?.id, RenewPresentationIdentity.id(objectIDURI: objectID))
    }

    func testPresentationIDDeletesExactRowEvenWhenBusinessIDsAreNil() {
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
        manager.readHistory { result in
            guard case .success(let history) = result else {
                reloaded.fulfill()
                return
            }
            values = history
            RenewPresentationOrchestration.reload(from: manager) { presented in
                if case .success(let presented) = presented { beans = presented }
                reloaded.fulfill()
            }
        }
        wait(for: [reloaded], timeout: 1)

        let nilValues = values.filter { $0.id == nil }
        XCTAssertEqual(nilValues.count, 2)
        let deletedValue = try! XCTUnwrap(nilValues.first)
        let deletedFallbackID = try! XCTUnwrap(beans.first { $0.id == RenewPresentationIdentity.id(objectIDURI: deletedValue.objectID) }?.id)
        manager.wipeById(deletedFallbackID)

        let afterFallbackDelete = expectation(description: "fallback row deleted")
        var remainingAfterFallback: [RenewHistoryValue] = []
        manager.readHistory {
            if case .success(let values) = $0 { remainingAfterFallback = values }
            afterFallbackDelete.fulfill()
        }
        wait(for: [afterFallbackDelete], timeout: 1)
        XCTAssertEqual(remainingAfterFallback.count, 2)
        XCTAssertFalse(remainingAfterFallback.contains { $0.objectID == deletedValue.objectID })
        XCTAssertEqual(remainingAfterFallback.filter { $0.id == nil }.count, 1)

        let businessValue = try! XCTUnwrap(values.first { $0.id == businessID })
        let businessPresentationID = RenewPresentationIdentity.id(objectIDURI: businessValue.objectID)
        manager.wipeById(businessPresentationID)
        let afterBusinessDelete = expectation(description: "business row deleted")
        var remainingAfterBusinessDelete: [RenewHistoryValue] = []
        manager.readHistory {
            if case .success(let values) = $0 { remainingAfterBusinessDelete = values }
            afterBusinessDelete.fulfill()
        }
        wait(for: [afterBusinessDelete], timeout: 1)
        XCTAssertEqual(remainingAfterBusinessDelete.count, 1)
        XCTAssertNil(remainingAfterBusinessDelete.first?.id)
    }

    func testDuplicateBusinessUUIDsHaveDistinctPresentationIDsAndExactDeletion() {
        let container = makeContainer()
        let context = container.newBackgroundContext()
        let businessID = UUID()
        seedHistory(in: context, id: businessID, ratio: 1)
        seedHistory(in: context, id: businessID, ratio: 2)
        let manager = CHDataManager(context: context)

        let loaded = expectation(description: "duplicate rows loaded")
        var values: [RenewHistoryValue] = []
        manager.readHistory { result in
            if case .success(let resultValues) = result { values = resultValues }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 1)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(Set(values.map(\.id)).count, 1)

        let beans = RenewPresentationOrchestration.beans(from: values)
        XCTAssertEqual(Set(beans.map(\.id)).count, 2)
        let deletedObjectID = values[0].objectID
        let deletedPresentationID = try! XCTUnwrap(
            beans.first { $0.id == RenewPresentationIdentity.id(objectIDURI: deletedObjectID) }?.id
        )
        manager.wipeById(deletedPresentationID)

        let remaining = expectation(description: "one duplicate remains")
        var remainingValues: [RenewHistoryValue] = []
        manager.readHistory { result in
            if case .success(let resultValues) = result { remainingValues = resultValues }
            remaining.fulfill()
        }
        wait(for: [remaining], timeout: 1)
        XCTAssertEqual(remainingValues.count, 1)
        XCTAssertEqual(remainingValues.first?.id, businessID)
        XCTAssertNotEqual(remainingValues.first?.objectID, deletedObjectID)
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
        manager.applyRenew(updates: [RenewUpdate(row: row, ratio: 2)]) { outcome in
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
        manager.applyRenew(updates: [RenewUpdate(row: updateRow, ratio: 2)]) { outcome in
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
        manager.applyRenew(updates: [RenewUpdate(row: updateRow, ratio: 2)]) { outcome in
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
        let workflow = AtomicRenewWorkflow(store: manager, converter: CCS21ConverterFixture())

        let firstRenew = expectation(description: "first renew")
        var firstResult: RenewRunResult?
        var firstBeans: [ConvertHistoryUIBean] = []
        XCTAssertTrue(workflow.renew { result, values in
            firstResult = result
            guard let values else {
                XCTFail("successful renew should return history")
                firstRenew.fulfill()
                return
            }
            firstBeans = RenewPresentationOrchestration.beans(from: values)
            firstRenew.fulfill()
        })
        wait(for: [firstRenew], timeout: 1)
        XCTAssertEqual(firstResult?.changedCount, 2)
        let firstIDs = firstBeans.map(\.id)
        XCTAssertEqual(Set(firstIDs).count, 2)
        XCTAssertNotEqual(Set(firstIDs), Set([firstID, secondID]))

        let secondRenew = expectation(description: "second renew")
        var secondResult: RenewRunResult?
        var secondBeans: [ConvertHistoryUIBean] = []
        XCTAssertTrue(workflow.renew { result, values in
            secondResult = result
            guard let values else {
                XCTFail("successful renew should return history")
                secondRenew.fulfill()
                return
            }
            secondBeans = RenewPresentationOrchestration.beans(from: values)
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
