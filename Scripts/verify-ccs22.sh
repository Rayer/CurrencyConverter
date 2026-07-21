#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

fail() {
    echo "CCS-22 verification failed: $1" >&2
    exit 1
}

command -v rg >/dev/null 2>&1 || fail "rg is required"

rg -q 'Open Safari Extension Settings' CurrencyConverter/ContentView.swift README.md || fail "truthful settings copy is missing"
if rg -q 'Enable/Disable Extension|Enable/Disable extension' CurrencyConverter README.md; then
    fail "direct-toggle copy remains in app or README"
fi
rg -q 'SFSafariApplication\.showPreferencesForExtension\(withIdentifier: identifier' CurrencyConverter/SafariExtensionSettingsAdapter.swift || fail "settings API wiring is missing"
rg -q 'SFSafariExtensionManager\.getStateOfSafariExtension\(withIdentifier: identifier\)' CurrencyConverter/SafariExtensionSettingsAdapter.swift || fail "state API wiring is missing"
rg -q 'builtInPlugInsURL' CurrencyConverter/SafariExtensionSettingsAdapter.swift || fail "configured embedded extension lookup is missing"
if rg -q 'com\.rayer\.CurrencyConverter-Extension' CurrencyConverter Shared; then
    fail "extension bundle identifier is duplicated in Swift"
fi
test "$(rg -c '^[[:space:]]+63CC34622531982E00466679 .*SafariExtensionSettingsState.swift in Sources.*,$' CurrencyConverter.xcodeproj/project.pbxproj)" = 2 || fail "Foundation seam is not in app and test targets"
app_sources=$(awk '/62850394251B936F00E381AA \/\* Sources \*\/ =/ {in_sources=1} in_sources {print} in_sources && /runOnlyForDeploymentPostprocessing = 0;/ {exit}' CurrencyConverter.xcodeproj/project.pbxproj)
test_sources=$(awk '/625712DC2371982E00466679 \/\* Sources \*\/ =/ {in_sources=1} in_sources {print} in_sources && /runOnlyForDeploymentPostprocessing = 0;/ {exit}' CurrencyConverter.xcodeproj/project.pbxproj)
extension_sources=$(awk '/625712F22371982E00466679 \/\* Sources \*\/ =/ {in_sources=1} in_sources {print} in_sources && /runOnlyForDeploymentPostprocessing = 0;/ {exit}' CurrencyConverter.xcodeproj/project.pbxproj)
printf '%s\n' "$app_sources" | rg -q 'SafariExtensionSettingsAdapter.swift in Sources' || fail "SafariServices adapter is not in the app target"
printf '%s\n' "$app_sources" | rg -q 'SafariExtensionSettingsState.swift in Sources' || fail "Foundation seam is not in the app target"
printf '%s\n' "$test_sources" | rg -q 'SafariExtensionSettingsState.swift in Sources' || fail "Foundation seam is not in the test target"
printf '%s\n' "$test_sources" | rg -q 'CCS22SafariExtensionSettingsTests.swift in Sources' || fail "CCS-22 tests are not in the test target"
if printf '%s\n' "$extension_sources" | rg -q 'SafariExtensionSettings'; then
    fail "SafariServices app adapter or seam leaked into the extension target"
fi
if rg -q 'SafariServices' Shared; then
    fail "Foundation-only shared seam imports SafariServices"
fi
if rg -q 'TEST_HOST|BUNDLE_LOADER' CurrencyConverter.xcodeproj; then
    fail "test host regression detected"
fi

extension_id=$(sed -n 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = "\([^"]*\)";/\1/p' CurrencyConverter.xcodeproj/project.pbxproj | head -1)
test -n "$extension_id" || fail "extension bundle identifier is missing from project settings"
test "$extension_id" = "com.rayer.CurrencyConverter-Extension" || fail "unexpected configured extension bundle identifier"
rg -q 'CurrencyConverter Extension\.appex' CurrencyConverter.xcodeproj/project.pbxproj || fail "extension is not embedded in the app"

temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT HUP INT TERM
swiftc_path=${SWIFTC:-}
if [ -z "$swiftc_path" ]; then
    swiftc_path=$(DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcrun --sdk macosx --find swiftc)
fi
sdk_path=$(DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcrun --sdk macosx --show-sdk-path)
"$swiftc_path" -sdk "$sdk_path" Shared/SafariExtensionSettingsState.swift Scripts/ccs22_standalone_tests.swift -o "$temporary_dir/ccs22_standalone_tests"
"$temporary_dir/ccs22_standalone_tests"
echo "CCS-22 static wiring checks passed"
