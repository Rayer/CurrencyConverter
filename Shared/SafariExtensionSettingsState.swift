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
    static let actionTitle = NSLocalizedString("Open Safari Extension Settings", comment: "Install/action title")
    static let accessibilityHint = NSLocalizedString("Opens Safari settings for this extension. Enable or disable it there.", comment: "Extension settings accessibility hint")

    static func copy(for status: SafariExtensionSettingsStatus) -> SafariExtensionSettingsCopy {
        let statusText: String
        let accessibilityValue: String

        switch status {
        case .loading:
            statusText = NSLocalizedString("Checking extension status…", comment: "Extension status text")
            accessibilityValue = NSLocalizedString("Checking.", comment: "Extension status accessibility value")
        case .unknown:
            statusText = NSLocalizedString("Extension status is unavailable. Check Safari Extension Settings.", comment: "Extension status text")
            accessibilityValue = NSLocalizedString("Unknown.", comment: "Extension status accessibility value")
        case .enabled:
            statusText = NSLocalizedString("Extension is enabled.", comment: "Extension status text")
            accessibilityValue = NSLocalizedString("Enabled.", comment: "Extension status accessibility value")
        case .disabled:
            statusText = NSLocalizedString("Extension is disabled. Enable it in Safari Extension Settings.", comment: "Extension status text")
            accessibilityValue = NSLocalizedString("Disabled.", comment: "Extension status accessibility value")
        case .error(let message):
            let detail = message.isEmpty ? "Safari did not provide more details." : message
            statusText = String(
                format: NSLocalizedString(
                    "Extension settings error: %@",
                    comment: "Extension status text"
                ),
                detail
            )
            accessibilityValue = String(
                format: NSLocalizedString(
                    "Error. %@",
                    comment: "Extension status accessibility value"
                ),
                detail
            )
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
