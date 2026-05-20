#!/usr/bin/env bash
# run-hook-tests.sh — Run all hook test suites.
#
# Usage: bash test/hooks/run-hook-tests.sh
#
# Exits 0 if all suites pass, 1 if any fail.

set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/../..")"

SUITES=(
    test/hooks/test-secret-guard.sh
    test/hooks/test-git-workflow-gate.sh
)

TOTAL_SUITES=0
FAILED_SUITES=0

for suite in "${SUITES[@]}"; do
    echo ""
    echo "════════════════════════════════════════"
    echo "Running: $suite"
    echo "════════════════════════════════════════"
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    if ! bash "$suite"; then
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
done

echo ""
echo "════════════════════════════════════════"
echo "Hook test summary: $TOTAL_SUITES suites, $FAILED_SUITES failed"
echo "════════════════════════════════════════"

if [[ $FAILED_SUITES -gt 0 ]]; then
    exit 1
fi
exit 0
