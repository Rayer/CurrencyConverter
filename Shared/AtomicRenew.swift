import Foundation
import CryptoKit

enum RenewPresentationIdentity {
    static func id(objectIDURI: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(objectIDURI.utf8)))
        // This is a deterministic SHA-256 construction, not RFC 4122 UUIDv5.
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
            bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

struct RenewRowSnapshot: Equatable {
    let objectID: String
    let businessID: UUID?
    let fromSymbol: String?
    let toSymbol: String?
    let fromAmount: Float32
    let ratio: Float32
}

struct RenewUpdate: Equatable {
    let objectID: String
    let businessID: UUID?
    let originalFromSymbol: String?
    let originalToSymbol: String?
    let originalFromAmountBitPattern: UInt32
    let originalRatioBitPattern: UInt32
    let ratio: Float32

    init(row: RenewRowSnapshot, ratio: Float32) {
        objectID = row.objectID
        businessID = row.businessID
        originalFromSymbol = row.fromSymbol
        originalToSymbol = row.toSymbol
        originalFromAmountBitPattern = row.fromAmount.bitPattern
        originalRatioBitPattern = row.ratio.bitPattern
        self.ratio = ratio
    }
}

struct RenewHistoryValue {
    let objectID: String
    let id: UUID?
    let title: String?
    let url: String?
    let fromSymbol: String?
    let toSymbol: String?
    let fromAmount: Float32
    let fxFee: Float32
    let ratio: Float32
}

struct RenewApplyOutcome {
    let appliedCount: Int
    let changedCount: Int
    let saveError: Error?
}

enum RenewTimeoutStage: Equatable {
    case snapshot
    case conversion
    case apply
    case history
}

enum RenewSnapshotError: Error {
    case failed(Error)

    var underlyingError: Error {
        switch self {
        case .failed(let error): return error
        }
    }
}

enum RenewTimeoutError: Error, Equatable {
    case expired(RenewTimeoutStage)
}

enum RenewSaveError: Error {
    case failed(Error)

    var underlyingError: Error {
        switch self {
        case .failed(let error): return error
        }
    }
}

enum RenewHistoryError: Error {
    case failed(Error)

    var underlyingError: Error {
        switch self {
        case .failed(let error): return error
        }
    }
}

struct RenewRunResult {
    let accepted: Bool
    let requestedCount: Int
    let successfulCalculationCount: Int
    let appliedCount: Int
    let changedCount: Int
    let snapshotError: RenewSnapshotError?
    let timeoutError: RenewTimeoutError?
    let saveError: RenewSaveError?
    let historyError: RenewHistoryError?

    static let rejected = RenewRunResult(
        accepted: false, requestedCount: 0, successfulCalculationCount: 0,
        appliedCount: 0, changedCount: 0, snapshotError: nil,
        timeoutError: nil, saveError: nil, historyError: nil
    )
}

protocol AtomicRenewStore: AnyObject {
    func snapshotForRenew(completion: @escaping (Result<[RenewRowSnapshot], Error>) -> Void)
    func applyRenew(updates: [RenewUpdate], completion: @escaping (RenewApplyOutcome) -> Void)
    func readHistory(completion: @escaping (Result<[RenewHistoryValue], Error>) -> Void)
    func wipeAll()
    func wipeById(_ id: UUID)
}

protocol RenewConverter: AnyObject {
    func convert(from: String, to: String, unit: Float32, completionHandler: @escaping (Float32, Error?) -> Void)
}

extension CurrencyConverter: RenewConverter {}

protocol AtomicRenewScheduledTask: AnyObject {
    func cancel()
}

protocol AtomicRenewScheduler: AnyObject {
    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> AtomicRenewScheduledTask
}

private final class DispatchRenewScheduledTask: AtomicRenewScheduledTask {
    private let item: DispatchWorkItem

    init(item: DispatchWorkItem) {
        self.item = item
    }

    func cancel() {
        item.cancel()
    }
}

private final class DispatchRenewScheduler: AtomicRenewScheduler {
    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> AtomicRenewScheduledTask {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: item)
        return DispatchRenewScheduledTask(item: item)
    }
}

private final class RenewOneShot<Value> {
    private let lock = NSLock()
    private var didConsume = false

    func consume(_ value: Value, action: (Value) -> Void) {
        lock.lock()
        guard !didConsume else {
            lock.unlock()
            return
        }
        didConsume = true
        lock.unlock()
        action(value)
    }
}

final class AtomicRenewWorkflow {
    private let stateLock = NSLock()
    private let store: AtomicRenewStore
    private let converter: RenewConverter
    private let timeout: TimeInterval
    private let scheduler: AtomicRenewScheduler
    private var activeOperation: AtomicRenewOperation?

    init(
        store: AtomicRenewStore,
        converter: RenewConverter,
        timeout: TimeInterval = 30,
        scheduler: AtomicRenewScheduler = DispatchRenewScheduler()
    ) {
        self.store = store
        self.converter = converter
        self.timeout = timeout
        self.scheduler = scheduler
    }

    @discardableResult
    func renew(completion: @escaping (RenewRunResult, [RenewHistoryValue]?) -> Void) -> Bool {
        stateLock.lock()
        guard activeOperation == nil else {
            stateLock.unlock()
            DispatchQueue.main.async { completion(.rejected, nil) }
            return false
        }

        let operation = AtomicRenewOperation(
            store: store, converter: converter, timeout: timeout, scheduler: scheduler,
            owner: self, completion: completion
        )
        activeOperation = operation
        stateLock.unlock()
        operation.start()
        return true
    }

    fileprivate func operationDidFinish(_ operation: AtomicRenewOperation) {
        stateLock.lock()
        if activeOperation === operation {
            activeOperation = nil
        }
        stateLock.unlock()
    }
}

private final class AtomicRenewOperation {
    private let stateLock = NSLock()
    private let store: AtomicRenewStore
    private let converter: RenewConverter
    private let timeout: TimeInterval
    private let scheduler: AtomicRenewScheduler
    private var owner: AtomicRenewWorkflow?
    private let completion: (RenewRunResult, [RenewHistoryValue]?) -> Void
    private let calculationQueue = DispatchQueue(label: "CurrencyConverter.atomic-renew.calculations", attributes: .concurrent)
    private var isActive = true
    private var stage: RenewTimeoutStage = .snapshot
    private var requestedCount = 0
    private var successfulCalculationCount = 0
    private var appliedCount = 0
    private var changedCount = 0
    private var timeoutTask: AtomicRenewScheduledTask?
    private var keepAlive: AtomicRenewOperation?

    init(
        store: AtomicRenewStore,
        converter: RenewConverter,
        timeout: TimeInterval,
        scheduler: AtomicRenewScheduler,
        owner: AtomicRenewWorkflow,
        completion: @escaping (RenewRunResult, [RenewHistoryValue]?) -> Void
    ) {
        self.store = store
        self.converter = converter
        self.timeout = timeout
        self.scheduler = scheduler
        self.owner = owner
        self.completion = completion
    }

    func start() {
        keepAlive = self
        let scheduled = scheduler.schedule(after: timeout) { [weak self] in
            self?.timeoutFired()
        }
        stateLock.lock()
        if isActive {
            timeoutTask = scheduled
            stateLock.unlock()
        } else {
            stateLock.unlock()
            scheduled.cancel()
        }

        let snapshotGate = RenewOneShot<Result<[RenewRowSnapshot], Error>>()
        store.snapshotForRenew { [weak self] result in
            snapshotGate.consume(result) { result in
                guard let self, self.isActiveNow() else { return }
                switch result {
                case .failure(let error):
                    self.finish(
                        result: RenewRunResult(
                            accepted: true, requestedCount: 0, successfulCalculationCount: 0,
                            appliedCount: 0, changedCount: 0,
                            snapshotError: .failed(error), timeoutError: nil,
                            saveError: nil, historyError: nil
                        ), history: nil
                    )
                case .success(let rows):
                    self.setCounts(requested: rows.count)
                    self.calculate(rows: rows)
                }
            }
        }
    }

    private func calculate(rows: [RenewRowSnapshot]) {
        setStage(.conversion)
        let group = DispatchGroup()
        let resultLock = NSLock()
        var successfulRatios: [Int: Float32] = [:]

        for (index, row) in rows.enumerated() {
            group.enter()
            calculationQueue.async { [weak self] in
                let rowGate = RenewOneShot<Float32?>()
                let complete: (Float32?) -> Void = { [weak self] ratio in
                    rowGate.consume(ratio) { ratio in
                        if let self, self.isActiveNow() {
                            resultLock.lock()
                            if let ratio {
                                successfulRatios[index] = ratio
                            }
                            resultLock.unlock()
                        }
                        group.leave()
                    }
                }

                guard let self else {
                    complete(nil)
                    return
                }
                guard let from = row.fromSymbol, let to = row.toSymbol,
                      !from.isEmpty, !to.isEmpty else {
                    complete(nil)
                    return
                }
                // The ticket explicitly treats same-currency conversion as a ratio of 1,
                // including zero and non-finite source amounts, without touching the network.
                if from == to {
                    complete(1)
                    return
                }
                guard row.fromAmount.isFinite, row.fromAmount != 0 else {
                    complete(nil)
                    return
                }

                self.converter.convert(from: from, to: to, unit: row.fromAmount) { amount, error in
                    guard error == nil, amount.isFinite else {
                        complete(nil)
                        return
                    }
                    let ratio = amount / row.fromAmount
                    complete(ratio.isFinite && ratio > 0 ? ratio : nil)
                }
            }
        }

        group.notify(queue: calculationQueue) { [weak self] in
            guard let self, self.beginApply() else { return }
            resultLock.lock()
            let updates = rows.enumerated().compactMap { index, row -> RenewUpdate? in
                guard let ratio = successfulRatios[index] else { return nil }
                return RenewUpdate(row: row, ratio: ratio)
            }
            let successfulCount = successfulRatios.count
            resultLock.unlock()
            self.setCounts(successful: successfulCount)

            let applyGate = RenewOneShot<RenewApplyOutcome>()
            self.store.applyRenew(updates: updates) { [weak self] outcome in
                applyGate.consume(outcome) { outcome in
                    guard let self, self.isActiveNow() else { return }
                    self.readHistory(
                        requestedCount: rows.count,
                        successfulCount: successfulCount,
                        outcome: outcome
                    )
                }
            }
        }
    }

    private func readHistory(requestedCount: Int, successfulCount: Int, outcome: RenewApplyOutcome) {
        setStage(.history)
        setCounts(applied: outcome.appliedCount, changed: outcome.changedCount)
        let historyGate = RenewOneShot<Result<[RenewHistoryValue], Error>>()
        store.readHistory { [weak self] result in
            historyGate.consume(result) { result in
                guard let self, self.isActiveNow() else { return }
                switch result {
                case .success(let values):
                    self.finish(
                        result: RenewRunResult(
                            accepted: true, requestedCount: requestedCount,
                            successfulCalculationCount: successfulCount,
                            appliedCount: outcome.appliedCount, changedCount: outcome.changedCount,
                            snapshotError: nil, timeoutError: nil,
                            saveError: outcome.saveError.map(RenewSaveError.failed),
                            historyError: nil
                        ), history: values
                    )
                case .failure(let error):
                    self.finish(
                        result: RenewRunResult(
                            accepted: true, requestedCount: requestedCount,
                            successfulCalculationCount: successfulCount,
                            appliedCount: outcome.appliedCount, changedCount: outcome.changedCount,
                            snapshotError: nil, timeoutError: nil,
                            saveError: outcome.saveError.map(RenewSaveError.failed),
                            historyError: .failed(error)
                        ), history: nil
                    )
                }
            }
        }
    }

    private func beginApply() -> Bool {
        stateLock.lock()
        guard isActive else {
            stateLock.unlock()
            return false
        }
        stage = .apply
        stateLock.unlock()
        return true
    }

    private func setStage(_ newStage: RenewTimeoutStage) {
        stateLock.lock()
        if isActive {
            stage = newStage
        }
        stateLock.unlock()
    }

    private func setCounts(
        requested: Int? = nil,
        successful: Int? = nil,
        applied: Int? = nil,
        changed: Int? = nil
    ) {
        stateLock.lock()
        if isActive {
            if let requested { requestedCount = requested }
            if let successful { successfulCalculationCount = successful }
            if let applied { appliedCount = applied }
            if let changed { changedCount = changed }
        }
        stateLock.unlock()
    }

    private func isActiveNow() -> Bool {
        stateLock.lock()
        let active = isActive
        stateLock.unlock()
        return active
    }

    private func timeoutFired() {
        stateLock.lock()
        let timedOutStage = stage
        let requestedCount = requestedCount
        let successfulCalculationCount = successfulCalculationCount
        let appliedCount = appliedCount
        let changedCount = changedCount
        stateLock.unlock()
        finish(
            result: RenewRunResult(
                accepted: true, requestedCount: requestedCount,
                successfulCalculationCount: successfulCalculationCount,
                appliedCount: appliedCount, changedCount: changedCount, snapshotError: nil,
                timeoutError: .expired(timedOutStage), saveError: nil, historyError: nil
            ), history: nil
        )
    }

    private func finish(result: RenewRunResult, history: [RenewHistoryValue]?) {
        stateLock.lock()
        guard isActive else {
            stateLock.unlock()
            return
        }
        isActive = false
        let task = timeoutTask
        timeoutTask = nil
        stateLock.unlock()
        task?.cancel()

        DispatchQueue.main.async { [self] in
            completion(result, history)
            let currentOwner = owner
            currentOwner?.operationDidFinish(self)
            owner = nil
            keepAlive = nil
        }
    }
}
