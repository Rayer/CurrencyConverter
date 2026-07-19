import Foundation
import CryptoKit

enum RenewPresentationIdentity {
    static func id(businessID: UUID?, objectIDURI: String) -> UUID {
        if let businessID {
            return businessID
        }

        var bytes = Array(SHA256.hash(data: Data(objectIDURI.utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
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
    let ratio: Float32
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

struct RenewRunResult {
    let accepted: Bool
    let requestedCount: Int
    let successfulCalculationCount: Int
    let appliedCount: Int
    let changedCount: Int
    let saveError: Error?

    static let rejected = RenewRunResult(
        accepted: false, requestedCount: 0, successfulCalculationCount: 0,
        appliedCount: 0, changedCount: 0, saveError: nil
    )
}

protocol AtomicRenewStore: AnyObject {
    func snapshotForRenew(completion: @escaping (Result<[RenewRowSnapshot], Error>) -> Void)
    func applyRenew(updates: [RenewUpdate], completion: @escaping (RenewApplyOutcome) -> Void)
    func readHistory(completion: @escaping ([RenewHistoryValue]) -> Void)
    func wipeAll()
    func wipeById(_ id: UUID)
}

protocol RenewConverter: AnyObject {
    func convert(from: String, to: String, unit: Float32, completionHandler: @escaping (Float32, Error?) -> Void)
}

extension CurrencyConverter: RenewConverter {}

final class AtomicRenewCoordinator {
    private let store: AtomicRenewStore
    private let converter: RenewConverter
    private let stateLock = NSLock()
    private let calculationQueue = DispatchQueue(label: "CurrencyConverter.atomic-renew.calculations", attributes: .concurrent)
    private var isInFlight = false

    init(store: AtomicRenewStore, converter: RenewConverter) {
        self.store = store
        self.converter = converter
    }

    @discardableResult
    func renew(completion: @escaping (RenewRunResult) -> Void) -> Bool {
        stateLock.lock()
        if isInFlight {
            stateLock.unlock()
            DispatchQueue.main.async { completion(.rejected) }
            return false
        }
        isInFlight = true
        stateLock.unlock()

        store.snapshotForRenew { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finish(RenewRunResult(
                    accepted: true, requestedCount: 0, successfulCalculationCount: 0,
                    appliedCount: 0, changedCount: 0, saveError: error
                ), completion: completion)
            case .success(let rows):
                self.calculate(rows: rows, completion: completion)
            }
        }
        return true
    }

    private func calculate(rows: [RenewRowSnapshot], completion: @escaping (RenewRunResult) -> Void) {
        let group = DispatchGroup()
        let resultLock = NSLock()
        var completedIndexes = Set<Int>()
        var successfulRatios: [Int: Float32] = [:]

        for (index, row) in rows.enumerated() {
            group.enter()
            calculationQueue.async { [weak self] in
                guard let self else {
                    group.leave()
                    return
                }

                let complete: (Float32?) -> Void = { ratio in
                    resultLock.lock()
                    guard completedIndexes.insert(index).inserted else {
                        resultLock.unlock()
                        return
                    }
                    if let ratio { successfulRatios[index] = ratio }
                    resultLock.unlock()
                    group.leave()
                }

                guard let from = row.fromSymbol, let to = row.toSymbol,
                      !from.isEmpty, !to.isEmpty else {
                    complete(nil)
                    return
                }
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
                    complete(ratio.isFinite ? ratio : nil)
                }
            }
        }

        group.notify(queue: calculationQueue) { [weak self] in
            guard let self else { return }
            resultLock.lock()
            let updates = rows.enumerated().compactMap { index, row -> RenewUpdate? in
                guard let ratio = successfulRatios[index] else { return nil }
                return RenewUpdate(objectID: row.objectID, businessID: row.businessID, ratio: ratio)
            }
            let successfulCount = successfulRatios.count
            resultLock.unlock()

            self.store.applyRenew(updates: updates) { outcome in
                self.finish(RenewRunResult(
                    accepted: true, requestedCount: rows.count,
                    successfulCalculationCount: successfulCount,
                    appliedCount: outcome.appliedCount,
                    changedCount: outcome.changedCount,
                    saveError: outcome.saveError
                ), completion: completion)
            }
        }
    }

    private func finish(_ result: RenewRunResult, completion: @escaping (RenewRunResult) -> Void) {
        stateLock.lock()
        isInFlight = false
        stateLock.unlock()
        DispatchQueue.main.async { completion(result) }
    }
}
