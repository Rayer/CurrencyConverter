import Combine
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

final class FakeSafariExtensionSettingsProvider: SafariExtensionSettingsProviding {
    private(set) var fetchCompletions: [(SafariExtensionSettingsResult) -> Void] = []
    private(set) var openSettingsCompletions: [(String?) -> Void] = []

    func fetchState(completion: @escaping (SafariExtensionSettingsResult) -> Void) {
        fetchCompletions.append(completion)
    }

    func openSettings(completion: @escaping (String?) -> Void) {
        openSettingsCompletions.append(completion)
    }
}

func waitForMainQueue(until condition: @escaping () -> Bool, _ message: String) {
    let deadline = Date(timeIntervalSinceNow: 2)
    while !condition() && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    require(condition(), message)
}

func testBackgroundRefreshPublishesOnMain() {
    let provider = FakeSafariExtensionSettingsProvider()
    let viewModel = SafariExtensionSettingsViewModel(provider: provider)
    var enabledCopyPublishedOnMain = false
    let cancellable = viewModel.$copy.sink { copy in
        if copy.accessibilityValue == "Enabled." {
            enabledCopyPublishedOnMain = Thread.isMainThread
        }
    }

    viewModel.refresh()
    require(provider.fetchCompletions.count == 1, "refresh must ask the provider for state")
    let completion = provider.fetchCompletions[0]
    DispatchQueue.global().async {
        completion(.status(.enabled))
    }
    waitForMainQueue(until: { viewModel.copy.accessibilityValue == "Enabled." }, "background refresh callback must publish")
    require(enabledCopyPublishedOnMain, "background refresh callback must publish copy on main")
    _ = cancellable
}

func testOpenSettingsErrorIsVisible() {
    let provider = FakeSafariExtensionSettingsProvider()
    let viewModel = SafariExtensionSettingsViewModel(provider: provider)

    viewModel.openSettings()
    require(provider.openSettingsCompletions.count == 1, "open settings must ask the provider")
    provider.openSettingsCompletions[0]("Safari is unavailable")

    require(viewModel.copy.statusText.contains("Safari is unavailable"), "open settings error must be visible")
}

func testSuccessfulHandoffTriggersRefresh() {
    let provider = FakeSafariExtensionSettingsProvider()
    let viewModel = SafariExtensionSettingsViewModel(provider: provider)

    viewModel.openSettings()
    provider.openSettingsCompletions[0](nil)
    require(provider.fetchCompletions.count == 1, "successful settings handoff must refresh state")

    provider.fetchCompletions[0](.status(.enabled))
    require(viewModel.copy.accessibilityValue == "Enabled.", "handoff refresh result must be visible")
}

func testStaleSuccessfulHandoffCannotTriggerRefresh() {
    let provider = FakeSafariExtensionSettingsProvider()
    let viewModel = SafariExtensionSettingsViewModel(provider: provider)

    viewModel.openSettings()
    viewModel.openSettings()
    require(provider.openSettingsCompletions.count == 2, "overlapping handoffs must remain independently controllable")

    provider.openSettingsCompletions[0](nil)
    require(provider.fetchCompletions.isEmpty, "stale successful handoff must not start a refresh")
    provider.openSettingsCompletions[1](nil)
    require(provider.fetchCompletions.count == 1, "current successful handoff must start one refresh")
}

func testStaleOutOfOrderCallbacksCannotOverwriteLatestState() {
    let provider = FakeSafariExtensionSettingsProvider()
    let viewModel = SafariExtensionSettingsViewModel(provider: provider)

    viewModel.refresh()
    viewModel.refresh()
    require(provider.fetchCompletions.count == 2, "duplicate refreshes must remain independently controllable")

    provider.fetchCompletions[1](.status(.disabled))
    let staleCompletion = provider.fetchCompletions[0]
    DispatchQueue.global().sync {
        staleCompletion(.status(.enabled))
    }
    var mainQueueDrained = false
    DispatchQueue.main.async {
        mainQueueDrained = true
    }
    waitForMainQueue(until: { mainQueueDrained }, "stale callback must reach main queue")
    require(viewModel.copy.accessibilityValue == "Disabled.", "stale callback must not overwrite latest state")
}

func testDuplicateActivationRefreshIsGenerationSafe() {
    let provider = FakeSafariExtensionSettingsProvider()
    let viewModel = SafariExtensionSettingsViewModel(provider: provider)

    viewModel.refresh()
    viewModel.refresh()
    provider.fetchCompletions[0](.status(.enabled))
    require(viewModel.copy.accessibilityValue == "Checking.", "first activation callback must be stale")
    provider.fetchCompletions[1](.status(.disabled))
    require(viewModel.copy.accessibilityValue == "Disabled.", "latest activation callback must win")
}

func testPureStateAndCopyBehavior() {
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
}

@main
struct CCS22StandaloneTests {
    static func main() {
        testPureStateAndCopyBehavior()
        testBackgroundRefreshPublishesOnMain()
        testOpenSettingsErrorIsVisible()
        testSuccessfulHandoffTriggersRefresh()
        testStaleSuccessfulHandoffCannotTriggerRefresh()
        testStaleOutOfOrderCallbacksCannotOverwriteLatestState()
        testDuplicateActivationRefreshIsGenerationSafe()
        print("CCS-22 standalone state/copy/ViewModel/provider checks passed (7 integration/state cases)")
    }
}
