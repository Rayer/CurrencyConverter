import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

@main
struct CCS22StandaloneTests {
    static func main() {
        let disabledCopy = SafariExtensionSettingsCopyMapping.copy(for: .disabled)
        require(disabledCopy.actionTitle == "Open Safari Extension Settings", "action copy must describe settings")
        require(!disabledCopy.actionTitle.contains("Enable/Disable"), "action copy must not promise a toggle")
        require(disabledCopy.accessibilityHint.contains("Enable or disable it there"), "manual Safari step must be accessible")

        var machine = SafariExtensionSettingsStateMachine()
        let firstGeneration = machine.beginRefresh()
        let currentGeneration = machine.beginRefresh()
        require(!machine.apply(.status(.enabled), for: firstGeneration), "stale callback must be ignored")
        require(machine.status == .loading, "stale callback must not change loading state")
        require(machine.apply(.status(.disabled), for: currentGeneration), "current callback must apply")
        require(machine.status == .disabled, "disabled state must be observable")

        let errorGeneration = machine.beginHandoff()
        require(machine.apply(.failure("settings handoff failed"), for: errorGeneration), "failure must apply")
        require(machine.status == .error("settings handoff failed"), "error state must be observable")
        require(SafariExtensionSettingsCopyMapping.copy(for: machine.status).statusText.contains("settings handoff failed"), "error must reach user copy")

        print("CCS-22 standalone state/copy/generation checks passed")
    }
}
