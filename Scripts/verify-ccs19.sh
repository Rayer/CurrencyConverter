#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
project_file="$root_dir/CurrencyConverter.xcodeproj/project.pbxproj"
picker_file="$root_dir/CurrencyConverter/CreditCardManageView.swift"

fail() {
    echo "CCS-19 verification failed: $1" >&2
    exit 1
}

command -v rg >/dev/null 2>&1 || fail "rg is required"

rg -q 'Text\(item\.code\)' "$picker_file" || fail "picker rows must render the code first"
rg -q 'Text\(item\.flag\)' "$picker_file" || fail "picker rows must retain decorative flags"
rg -q '\.accessibility\(hidden: true\)' "$picker_file" || fail "flags must be hidden from accessibility"
rg -q '\.accessibility\(label: Text\(item\.accessibilityLabel\)\)' "$picker_file" || fail "picker rows need an explicit code-only accessibility label"
if rg -q 'Text\("\(CountryCurrency\.shared\.getFlag' "$picker_file"; then
    fail "flag-first Text remains in the currency picker"
fi

app_sources=$(awk '/62850394251B936F00E381AA \/\* Sources \*\/ =/ {capture=1} capture {print} capture && /runOnlyForDeploymentPostprocessing = 0;/ {exit}' "$project_file")
test_sources=$(awk '/625712DC2371982E00466679 \/\* Sources \*\/ =/ {capture=1} capture {print} capture && /runOnlyForDeploymentPostprocessing = 0;/ {exit}' "$project_file")
extension_sources=$(awk '/625712F22371982E00466679 \/\* Sources \*\/ =/ {capture=1} capture {print} capture && /runOnlyForDeploymentPostprocessing = 0;/ {exit}' "$project_file")

printf '%s\n' "$app_sources" | rg -q 'CurrencyPickerPresentation.swift in Sources' || fail "presentation seam is not in the app target"
printf '%s\n' "$test_sources" | rg -q 'CurrencyPickerPresentation.swift in Sources' || fail "presentation seam is not in the test target"
printf '%s\n' "$test_sources" | rg -q 'CCS19CurrencyPickerTests.swift in Sources' || fail "CCS-19 XCTest source is not in the test target"
if printf '%s\n' "$extension_sources" | rg -q 'CurrencyPickerPresentation.swift'; then
    fail "picker UI seam leaked into the extension target"
fi
if rg -q 'TEST_HOST|BUNDLE_LOADER' "$project_file"; then
    fail "standalone test architecture regressed to a hosted test target"
fi
if rg -q 'import SwiftUI|import AppKit|import SafariServices' "$root_dir/Shared/CurrencyPickerPresentation.swift" "$root_dir/Scripts/ccs19_standalone_tests.swift"; then
    fail "standalone picker seam/tests must remain Foundation-only"
fi

temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT HUP INT TERM
swiftc_path=${SWIFTC:-$(command -v swiftc)}
"$swiftc_path" "$root_dir/Shared/CurrencyPickerPresentation.swift" "$root_dir/Scripts/ccs19_standalone_tests.swift" -o "$temporary_dir/ccs19_standalone_tests"
"$temporary_dir/ccs19_standalone_tests"
echo "CCS-19 static wiring checks passed"
