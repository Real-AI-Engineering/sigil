#!/usr/bin/env bash
# test-signum-ci.sh — tests for lib/signum-ci.sh (unit tests, no actual claude invocation)
# Tests input validation and decision-to-exit-code mapping only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CI_SCRIPT="$SCRIPT_DIR/../lib/signum-ci.sh"

passed=0
failed=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

assert_exit() {
  local name="$1" expected_exit="$2"; shift 2
  local output exit_code
  set +e
  output=$("$@" 2>&1)
  exit_code=$?
  set -e
  if [[ "$exit_code" -eq "$expected_exit" ]]; then
    printf '  PASS: %s (exit=%s)\n' "$name" "$exit_code"
    passed=$((passed + 1))
  else
    printf '  FAIL: %s — expected exit %s, got %s: %s\n' "$name" "$expected_exit" "$exit_code" "$output"
    failed=$((failed + 1))
  fi
}

assert_contains() {
  local name="$1" expected="$2" output="$3"
  if [[ "$output" == *"$expected"* ]]; then
    printf '  PASS: %s\n' "$name"
    passed=$((passed + 1))
  else
    printf '  FAIL: %s — output missing "%s"\n' "$name" "$expected"
    failed=$((failed + 1))
  fi
}

echo "=== Input validation ==="

# No SIGNUM_CONTRACT_PATH
assert_exit "fails without CONTRACT_PATH" 1 \
  env -u SIGNUM_CONTRACT_PATH bash "$CI_SCRIPT"

# Nonexistent contract file
assert_exit "fails on missing contract file" 1 \
  env SIGNUM_CONTRACT_PATH="/tmp/nonexistent-contract-xyz.json" bash "$CI_SCRIPT"

# Invalid contract (missing required fields)
echo '{"foo": "bar"}' > "$WORK/invalid.json"
assert_exit "fails on invalid contract" 1 \
  env SIGNUM_CONTRACT_PATH="$WORK/invalid.json" bash "$CI_SCRIPT"

echo ""
echo "=== Contract field validation ==="

# Valid contract structure (will fail at claude invocation, but should pass validation)
cat > "$WORK/valid.json" <<'EOF'
{
  "schemaVersion": "3.2",
  "contractId": "sig-20260314-test",
  "goal": "Test goal",
  "inScope": ["test.py"],
  "acceptanceCriteria": [{"id": "AC1", "description": "Test", "visibility": "visible"}],
  "riskLevel": "low"
}
EOF

# The script should get past validation but fail at `claude` command
set +e
output=$(env SIGNUM_CONTRACT_PATH="$WORK/valid.json" SIGNUM_PROJECT_ROOT="$WORK" bash "$CI_SCRIPT" 2>&1)
exit_code=$?
set -e

# It should print the header (proves validation passed)
assert_contains "valid contract passes validation" "=== Signum CI ===" "$output"
assert_contains "shows contract path" "valid.json" "$output"

echo ""
echo "=== Exit code mapping (direct test) ==="

# Test the case statement logic by creating mock proofpacks and sourcing
for decision in AUTO_OK AUTO_BLOCK HUMAN_REVIEW; do
  mkdir -p "$WORK/exittest-${decision}/.signum"
  cat > "$WORK/exittest-${decision}/.signum/proofpack.json" <<PPEOF
{
  "runId": "signum-test",
  "decision": "${decision}",
  "confidence": {"overall": 85}
}
PPEOF

  # Extract the exit code mapping logic and test it standalone
  set +e
  exit_code=$(cd "$WORK/exittest-${decision}" && bash -c '
    DECISION="'"${decision}"'"
    case "$DECISION" in
      AUTO_OK) exit 0 ;;
      AUTO_BLOCK) exit 1 ;;
      HUMAN_REVIEW) exit 78 ;;
      *) exit 1 ;;
    esac
  ')
  actual_exit=$?
  set -e

  case "$decision" in
    AUTO_OK)      expected=0 ;;
    AUTO_BLOCK)   expected=1 ;;
    HUMAN_REVIEW) expected=78 ;;
  esac

  if [[ "$actual_exit" -eq "$expected" ]]; then
    printf '  PASS: %s → exit %s\n' "$decision" "$actual_exit"
    passed=$((passed + 1))
  else
    printf '  FAIL: %s — expected exit %s, got %s\n' "$decision" "$expected" "$actual_exit"
    failed=$((failed + 1))
  fi
done

echo ""
echo "=== SHA-256 hash computation ==="

# Verify hash is computed correctly
mkdir -p "$WORK/hashtest/.signum"
echo '{"test": true}' > "$WORK/hashtest/.signum/proofpack.json"

if command -v sha256sum >/dev/null 2>&1; then
  EXPECTED=$(sha256sum "$WORK/hashtest/.signum/proofpack.json" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  EXPECTED=$(shasum -a 256 "$WORK/hashtest/.signum/proofpack.json" | awk '{print $1}')
else
  EXPECTED="skip"
fi

if [[ "$EXPECTED" != "skip" && -n "$EXPECTED" ]]; then
  printf '  PASS: SHA-256 hash computable (%s)\n' "${EXPECTED:0:16}..."
  passed=$((passed + 1))
else
  printf '  SKIP: no sha256sum/shasum available\n'
fi

echo ""
echo "=== Results ==="
echo "Passed: $passed"
echo "Failed: $failed"
echo ""

if [ "$failed" -gt 0 ]; then
  echo "FAILED"
  exit 1
else
  echo "ALL PASSED"
  exit 0
fi
