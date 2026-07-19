//
//  ConvertHistoryDM.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/28.
//  Copyright © 2020 Rayer. All rights reserved.
//

import Foundation

extension ConvertHistory: ConvertHistoryRecord {}

class ConvertHistoryDMCollection : ObservableObject {
    @Published var data : [ConvertHistoryUIBean] = []
    let dataManager: AtomicRenewStore
    let converter: RenewConverter
    private let renewCoordinator: AtomicRenewCoordinator

    init(dataManager: AtomicRenewStore = CHDataManager.shared, converter: RenewConverter = CurrencyConverter.shared) {
        self.dataManager = dataManager
        self.converter = converter
        self.renewCoordinator = AtomicRenewCoordinator(store: dataManager, converter: converter)
    }
    
    @objc func reload() {
        publishReload()
    }

    private func publishReload(completion: (() -> Void)? = nil) {
        dataManager.readHistory { [weak self] values in
            let beans = values.map { value in
                let normalized = LegacyConvertHistoryCalculations.normalizedHistoryValues(
                    fromSymbol: value.fromSymbol, toSymbol: value.toSymbol,
                    fxFeeRate: value.fxFee, ratio: value.ratio
                )
                return ConvertHistoryUIBean(
                    id: RenewPresentationIdentity.id(businessID: value.id, objectIDURI: value.objectID),
                    title: value.title ?? "", url: value.url ?? "",
                    fromSymbol: value.fromSymbol ?? "", toSymbol: value.toSymbol ?? "",
                    fromAmount: value.fromAmount, fxFeeRate: normalized.fxFeeRate,
                    ratio: normalized.ratio
                )
            }
            DispatchQueue.main.async {
                self?.data = beans
                completion?()
            }
        }
    }
    func wipe() {
        dataManager.wipeAll()
        self.data = []
    }
    
    func wipeChecked() {
        data.enumerated()
            .filter { $0.element.isChecked }
            .forEach {
                dataManager.wipeById($0.element.id)
            }
        data = data.enumerated()
            .filter { $0.element.isChecked == false }
            .map { $0.element }
        
    }
    
    @discardableResult
    func renewFx(completion: ((RenewRunResult) -> Void)? = nil) -> Bool {
        renewCoordinator.renew { [weak self] result in
            guard result.accepted else {
                completion?(result)
                return
            }
            guard let self else {
                completion?(result)
                return
            }
            self.publishReload {
                completion?(result)
            }
        }
    }

}
