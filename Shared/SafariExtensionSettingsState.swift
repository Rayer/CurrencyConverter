import Foundation

enum SafariExtensionSettingsStatus: Equatable {
    case loading
    case unknown
    case enabled
    case disabled
    case error(String)
}

struct SafariExtensionSettingsCopy: Equatable {
    let actionTitle: String
    let statusText: String
    let accessibilityValue: String
    let accessibilityHint: String
}

enum SafariExtensionSettingsCopyMapping {
    static let actionTitle = "Open Safari Extension Settings"
    static let accessibilityHint = "Opens Safari settings for this extension. Enable or disable it there."

    static func copy(for status: SafariExtensionSettingsStatus) -> SafariExtensionSettingsCopy {
        let statusText: String
        let accessibilityValue: String

        switch status {
        case .loading:
            statusText = "Checking extension status…"
            accessibilityValue = "Checking."
        case .unknown:
            statusText = "Extension status is unavailable. Check Safari Extension Settings."
            accessibilityValue = "Unknown."
        case .enabled:
            statusText = "Extension is enabled."
            accessibilityValue = "Enabled."
        case .disabled:
            statusText = "Extension is disabled. Enable it in Safari Extension Settings."
            accessibilityValue = "Disabled."
        case .error(let message):
            let detail = message.isEmpty ? "Safari did not provide more details." : message
            statusText = "Extension settings error: \(detail)"
            accessibilityValue = "Error. \(detail)"
        }

        return SafariExtensionSettingsCopy(
            actionTitle: actionTitle,
            statusText: statusText,
            accessibilityValue: accessibilityValue,
            accessibilityHint: accessibilityHint
        )
    }
}

enum SafariExtensionSettingsResult: Equatable {
    case status(SafariExtensionSettingsStatus)
    case failure(String)
}

struct SafariExtensionSettingsStateMachine {
    private(set) var status: SafariExtensionSettingsStatus = .loading
    private(set) var generation: UInt = 0

    mutating func beginRefresh() -> UInt {
        generation &+= 1
        status = .loading
        return generation
    }

    mutating func beginHandoff() -> UInt {
        generation &+= 1
        return generation
    }

    @discardableResult
    mutating func apply(_ result: SafariExtensionSettingsResult, for generation: UInt) -> Bool {
        guard generation == self.generation else { return false }

        switch result {
        case .status(let status):
            self.status = status
        case .failure(let message):
            self.status = .error(message)
        }
        return true
    }
}
