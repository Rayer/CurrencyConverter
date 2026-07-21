import Combine
import Foundation

protocol SafariExtensionSettingsProviding {
    func fetchState(completion: @escaping (SafariExtensionSettingsResult) -> Void)
    func openSettings(completion: @escaping (String?) -> Void)
}

final class SafariExtensionSettingsViewModel: ObservableObject {
    @Published private(set) var copy = SafariExtensionSettingsCopyMapping.copy(for: .loading)

    private let provider: SafariExtensionSettingsProviding
    private var stateMachine = SafariExtensionSettingsStateMachine()

    init(provider: SafariExtensionSettingsProviding) {
        self.provider = provider
    }

    func refresh() {
        onMain { [weak self] in
            guard let self = self else { return }

            let generation = self.stateMachine.beginRefresh()
            self.publishCopy()
            self.provider.fetchState { [weak self] result in
                self?.apply(result, for: generation)
            }
        }
    }

    func openSettings() {
        onMain { [weak self] in
            guard let self = self else { return }

            let generation = self.stateMachine.beginHandoff()
            self.provider.openSettings { [weak self] errorMessage in
                guard let self = self else { return }
                self.onMain {
                    if let errorMessage = errorMessage {
                        guard self.stateMachine.apply(.failure(errorMessage), for: generation) else { return }
                        self.publishCopy()
                    } else {
                        self.refresh()
                    }
                }
            }
        }
    }

    private func apply(_ result: SafariExtensionSettingsResult, for generation: UInt) {
        onMain { [weak self] in
            guard let self = self else { return }
            guard self.stateMachine.apply(result, for: generation) else { return }
            self.publishCopy()
        }
    }

    private func publishCopy() {
        copy = SafariExtensionSettingsCopyMapping.copy(for: stateMachine.status)
    }

    private func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}
