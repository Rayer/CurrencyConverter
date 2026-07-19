#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
project_file="$root_dir/CurrencyConverter.xcodeproj/project.pbxproj"
tests_file="$root_dir/CurrencyConverterTests/CCS21AtomicRenewTests.swift"

debug_settings=$(awk '
    /625713152371982E00466679 \/\* Debug \*\// { capture = 1 }
    capture { print }
    capture && /name = Debug;/ { exit }
' "$project_file")
release_settings=$(awk '
    /625713162371982E00466679 \/\* Release \*\// { capture = 1 }
    capture { print }
    capture && /name = Release;/ { exit }
' "$project_file")

case "$debug_settings $release_settings" in
    *BUNDLE_LOADER*|*TEST_HOST*)
        echo "CurrencyConverterTests must not define TEST_HOST or BUNDLE_LOADER" >&2
        exit 1
        ;;
esac

test_sources=$(awk '
    /625712DC2371982E00466679 \/\* Sources \*\/ = \{/ { capture = 1 }
    capture { print }
    capture && /runOnlyForDeploymentPostprocessing = 0;/ { exit }
' "$project_file")

printf '%s\n' "$test_sources" | grep -Fq '62C49F25252AA14600ED2E72 /* CHDataManager.swift in Sources */'
printf '%s\n' "$test_sources" | grep -Fq '63CC34512531982E00466679 /* AtomicRenew.swift in Sources */'
grep -Fq '63CC34522531982E00466679 /* AtomicRenew.swift in Sources */' "$project_file"
grep -Fq '63CC34532531982E00466679 /* AtomicRenew.swift in Sources */' "$project_file"
grep -Fq '62C49F26252AA14600ED2E72 /* CHDataManager.swift in Sources */' "$project_file"
grep -Fq '62C49F27252AA14600ED2E72 /* CHDataManager.swift in Sources */' "$project_file"

if grep -Fq 'ConvertHistoryDMCollection' "$tests_file"; then
    echo "CCS21 tests must not reference the SwiftUI app collection" >&2
    exit 1
fi
grep -Fq 'AtomicRenewWorkflow' "$tests_file"
grep -Fq 'AtomicRenewWorkflow' "$root_dir/CurrencyConverter/ConvertHistoryUIBean.swift"
if grep -Fq 'ConvertHistoryUIBean' "$root_dir/Shared/AtomicRenew.swift"; then
    echo "AtomicRenew.swift must not depend on UI beans" >&2
    exit 1
fi
if grep -Fq 'AtomicRenewCoordinator' "$tests_file"; then
    echo "CCS21 tests must instantiate AtomicRenewWorkflow, not its coordinator" >&2
    exit 1
fi
if grep -Fq 'renewAndReload' "$tests_file"; then
    echo "CCS21 tests must not shadow the production renew workflow" >&2
    exit 1
fi
grep -Fq 'RenewPresentationOrchestration.beans(from:' "$tests_file"
grep -Fq 'RenewPresentationOrchestration.beans(from:' "$root_dir/CurrencyConverter/ConvertHistoryUIBean.swift"
grep -Fq 'RenewPresentationOrchestration.reload' "$root_dir/CurrencyConverter/ConvertHistoryUIBean.swift"

echo "CCS21 standalone architecture checks passed"
