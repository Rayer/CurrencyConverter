import XCTest
@testable import CurrencyConverter

final class CCS22SafariExtensionSettingsTests: XCTestCase {
    func testCopyNeverPromisesDirectToggleAndDescribesManualSettings() {
        let copy = SafariExtensionSettingsCopyMapping.copy(for: .disabled)

        XCTAssertEqual(copy.actionTitle, "Open Safari Extension Settings")
        XCTAssertTrue(copy.statusText.contains("Enable it in Safari Extension Settings"))
        XCTAssertTrue(copy.accessibilityHint.contains("Enable or disable it there"))
        XCTAssertFalse(copy.actionTitle.contains("Enable/Disable"))
    }

    func testCopyMapsLoadingUnknownEnabledDisabledAndError() {
        XCTAssertEqual(SafariExtensionSettingsCopyMapping.copy(for: .loading).accessibilityValue, "Checking.")
        XCTAssertEqual(SafariExtensionSettingsCopyMapping.copy(for: .unknown).accessibilityValue, "Unknown.")
        XCTAssertEqual(SafariExtensionSettingsCopyMapping.copy(for: .enabled).accessibilityValue, "Enabled.")
        XCTAssertEqual(SafariExtensionSettingsCopyMapping.copy(for: .disabled).accessibilityValue, "Disabled.")
        XCTAssertTrue(SafariExtensionSettingsCopyMapping.copy(for: .error("open failed")).statusText.contains("open failed"))
    }

    func testFailureIsVisibleInStateAndCopy() {
        var machine = SafariExtensionSettingsStateMachine()
        let generation = machine.beginHandoff()

        XCTAssertTrue(machine.apply(.failure("Safari is unavailable"), for: generation))
        XCTAssertEqual(machine.status, .error("Safari is unavailable"))
        XCTAssertTrue(SafariExtensionSettingsCopyMapping.copy(for: machine.status).statusText.contains("Safari is unavailable"))
    }

    func testStaleGenerationCannotOverwriteCurrentState() {
        var machine = SafariExtensionSettingsStateMachine()
        let firstGeneration = machine.beginRefresh()
        let currentGeneration = machine.beginRefresh()

        XCTAssertFalse(machine.apply(.status(.enabled), for: firstGeneration))
        XCTAssertEqual(machine.status, .loading)
        XCTAssertTrue(machine.apply(.status(.disabled), for: currentGeneration))
        XCTAssertEqual(machine.status, .disabled)
    }
}
