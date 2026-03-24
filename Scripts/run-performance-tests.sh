#!/bin/bash
# Performance Regression Test Runner per FEAT-064 / [D-QA-2].
#
# Runs the PerformanceRegressionTests suite against representative device targets.
# Exits with non-zero status if any performance threshold is breached, blocking the build.
#
# Usage:
#   ./Scripts/run-performance-tests.sh                    # Run on default (iPhone 15)
#   ./Scripts/run-performance-tests.sh --device iPhone15  # Specific device
#   ./Scripts/run-performance-tests.sh --device iPadPro   # iPad Pro (ProMotion)
#   ./Scripts/run-performance-tests.sh --all              # Both device targets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEVICE="iPhone15"
RUN_ALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)
            DEVICE="$2"
            shift 2
            ;;
        --all)
            RUN_ALL=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--device iPhone15|iPadPro] [--all]"
            echo ""
            echo "Runs performance regression tests per [D-QA-2]."
            echo "Exits non-zero if any performance target is breached."
            echo ""
            echo "Options:"
            echo "  --device NAME   Run on a specific device target (iPhone15 or iPadPro)"
            echo "  --all           Run on all device targets (iPhone 15 + iPad Pro)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Map device names to simulator destinations (AC4)
destination_for_device() {
    case "$1" in
        iPhone15)
            echo "platform=iOS Simulator,name=iPhone 15,OS=latest"
            ;;
        iPadPro)
            echo "platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation),OS=latest"
            ;;
        *)
            echo "Unknown device: $1" >&2
            exit 1
            ;;
    esac
}

run_tests_for_device() {
    local device="$1"
    local destination
    destination="$(destination_for_device "$device")"

    echo "═══════════════════════════════════════════════════════"
    echo "Running performance regression tests: $device"
    echo "Destination: $destination"
    echo "═══════════════════════════════════════════════════════"

    cd "$PROJECT_DIR"

    # Run only the PerformanceRegressionTests target
    # --filter targets the integrated suite that reports + saves baselines
    swift test \
        --filter PerformanceRegressionTests \
        2>&1

    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "FAILED: Performance regression detected on $device (exit code $exit_code)"
        echo "One or more performance targets exceeded. See report above."
        return $exit_code
    fi

    echo ""
    echo "PASSED: All performance targets met on $device"
    return 0
}

OVERALL_EXIT=0

if [ "$RUN_ALL" = true ]; then
    for device in iPhone15 iPadPro; do
        if ! run_tests_for_device "$device"; then
            OVERALL_EXIT=1
        fi
    done
else
    if ! run_tests_for_device "$DEVICE"; then
        OVERALL_EXIT=1
    fi
fi

if [ $OVERALL_EXIT -ne 0 ]; then
    echo ""
    echo "═══ BUILD BLOCKED: Performance regression detected ═══"
    exit 1
fi

echo ""
echo "═══ All performance targets passed ═══"
exit 0
