#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"
project_file="CurrencyConverter.xcodeproj/project.pbxproj"

fail() {
    echo "CCS-15 verification failed: $1" >&2
    exit 1
}

command -v rg >/dev/null 2>&1 || fail "rg is required"

app_sources=$(awk '/62850394251B936F00E381AA \/\* Sources \*\/ =/ {capture=1} capture {print} capture && /runOnlyForDeploymentPostprocessing = 0;/ {exit}' "$project_file")
extension_sources=$(awk '/625712F22371982E00466679 \/\* Sources \*\/ =/ {capture=1} capture {print} capture && /runOnlyForDeploymentPostprocessing = 0;/ {exit}' "$project_file")
test_sources=$(awk '/625712DC2371982E00466679 \/\* Sources \*\/ =/ {capture=1} capture {print} capture && /runOnlyForDeploymentPostprocessing = 0;/ {exit}' "$project_file")

for sources in "$app_sources" "$extension_sources" "$test_sources"; do
    printf '%s\n' "$sources" | rg -q 'ConversionTemplateDomain.swift in Sources' || fail "Foundation domain seam is not in every target"
    printf '%s\n' "$sources" | rg -q 'FormatStringDataManager.swift in Sources' || fail "repository is not in every target"
done
printf '%s\n' "$app_sources" | rg -q 'ConversionTemplateManagementView.swift in Sources' || fail "management UI is not in the app target"
printf '%s\n' "$test_sources" | rg -q 'CCS15ConversionTemplateTests.swift in Sources' || fail "CCS-15 tests are not in the test target"

rg -q '^import Foundation$' Shared/ConversionTemplateDomain.swift || fail "domain seam is not Foundation-only"
rg -q 'private lazy var conversionTemplateViewModel = ConversionTemplateManagementViewModel\(\)' CurrencyConverter/AppDelegate.swift || fail "AppDelegate does not own the template ViewModel"
rg -q 'templates: conversionTemplateViewModel' CurrencyConverter/AppDelegate.swift || fail "AppDelegate does not inject its template ViewModel"
rg -q 'sharedPersistentContainer\.newBackgroundContext\(\)' Shared/FormatStringDataManager.swift || fail "default repository does not use a dedicated context"
rg -q 'context\.reset\(\)' Shared/FormatStringDataManager.swift || fail "repository does not refresh cross-process reads"
if rg -q 'initializationError|try performAndWait \{ try ensureBundledDefaults\(\) \}' Shared/FormatStringDataManager.swift; then
    fail "repository still performs sticky eager initialization"
fi
if rg -q 'FormatString\(context:' Shared/FormatStringDataManager.swift CurrencyConverterTests/CCS15ConversionTemplateTests.swift; then
    fail "ambiguous generated Core Data insertion remains"
fi
if rg -q 'SwiftUI|AppKit|SafariServices|CoreData' Shared/ConversionTemplateDomain.swift; then
    fail "UI, Safari, or Core Data leaked into the Foundation domain seam"
fi
if rg -q 'defaultFormattingString|\$\{to_amount\} \$\{to_symbol\}' 'CurrencyConverter Extension/ConvertPasteboardFormatter.swift'; then
    fail "extension contains a duplicate hard-coded template array"
fi
rg -q 'templateManager\.selectedTemplate\(\)' 'CurrencyConverter Extension/SafariExtensionHandler.swift' || fail "context menu does not read selected repository template"
rg -q 'removeObject\(forKey: "lastResult"\)' 'CurrencyConverter Extension/SafariExtensionHandler.swift' || fail "encode failure can leave a stale clipboard result"
if tail -n 35 'CurrencyConverter Extension/SafariExtensionViewController.swift' | awk '/addItems\(withTitles:/ {added=1} /selectItem\(at:/ {if (!added) exit 1; selected=1} END {exit !(added && selected)}'; then :; else
    fail "popover selection is published before asynchronous items"
fi
if rg -q 'TEST_HOST|BUNDLE_LOADER' "$project_file"; then
    fail "test host or bundle loader was introduced"
fi

temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT HUP INT TERM
swiftc_path=${SWIFTC:-}
if [ -z "$swiftc_path" ]; then
    swiftc_path=$(xcrun --sdk macosx --find swiftc)
fi
sdk_path=${SDKROOT:-}
if [ -z "$sdk_path" ]; then
    sdk_path=$(xcrun --sdk macosx --show-sdk-path)
fi
"$swiftc_path" -sdk "$sdk_path" Shared/ConversionTemplateDomain.swift Scripts/ccs15_standalone_tests.swift -o "$temporary_dir/ccs15_standalone_tests"
"$temporary_dir/ccs15_standalone_tests"
echo "CCS-15 static wiring checks passed"
