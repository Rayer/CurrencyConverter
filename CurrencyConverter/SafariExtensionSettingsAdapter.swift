import Foundation
import SafariServices

final class SafariExtensionSettingsAdapter: SafariExtensionSettingsProviding {
    private static let extensionProductName = "CurrencyConverter Extension"

    private let extensionBundleIdentifier: String?

    init(bundle: Bundle = .main) {
        extensionBundleIdentifier = Self.configuredExtensionBundleIdentifier(in: bundle)
    }

    static func configuredExtensionBundleIdentifier(in bundle: Bundle) -> String? {
        guard let plugInsURL = bundle.builtInPlugInsURL else { return nil }
        let extensionURL = plugInsURL.appendingPathComponent("\(extensionProductName).appex", isDirectory: true)
        return Bundle(url: extensionURL)?.bundleIdentifier
    }

    func fetchState(completion: @escaping (SafariExtensionSettingsResult) -> Void) {
        guard let identifier = extensionBundleIdentifier else {
            publish(.failure("The bundled Safari extension identifier is unavailable."), completion: completion)
            return
        }

        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: identifier) { state, error in
            let result: SafariExtensionSettingsResult
            if let error = error {
                result = .failure("Unable to read Safari extension status: \(error.localizedDescription)")
            } else if let state = state {
                result = .status(state.isEnabled ? .enabled : .disabled)
            } else {
                result = .status(.unknown)
            }
            self.publish(result, completion: completion)
        }
    }

    func openSettings(completion: @escaping (String?) -> Void) {
        guard let identifier = extensionBundleIdentifier else {
            publish("The bundled Safari extension identifier is unavailable.", completion: completion)
            return
        }

        SFSafariApplication.showPreferencesForExtension(withIdentifier: identifier) { error in
            self.publish(error.map { "Unable to open Safari Extension Settings: \($0.localizedDescription)" }, completion: completion)
        }
    }

    private func publish<T>(_ value: T, completion: @escaping (T) -> Void) {
        if Thread.isMainThread {
            completion(value)
        } else {
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }
}
