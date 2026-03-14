#!/usr/bin/env bash
# signum-ci.sh — CI wrapper for Signum pipeline
# Runs Signum with a pre-approved contract and maps decision to exit code.
#
# Exit codes:
#   0  — AUTO_OK (safe to merge)
#   1  — AUTO_BLOCK (issues found, block merge)
#   78 — HUMAN_REVIEW (needs manual review)
#
# Environment variables:
#   SIGNUM_CONTRACT_PATH — path to pre-approved contract.json (required)
#   SIGNUM_MAX_TURNS     — max agent turns (default: 30)
#   SIGNUM_ALLOWED_TOOLS — comma-separated tool allowlist (optional)
#   SIGNUM_PROJECT_ROOT  — project root (default: current directory)

set -euo pipefail

# --- Validate inputs ---
CONTRACT="${SIGNUM_CONTRACT_PATH:-}"
if [ -z "$CONTRACT" ]; then
  echo "ERROR: SIGNUM_CONTRACT_PATH is required" >&2
  exit 1
fi
if [ ! -f "$CONTRACT" ]; then
  echo "ERROR: Contract not found: $CONTRACT" >&2
  exit 1
fi

# Validate contract has required fields
if ! jq -e '.schemaVersion and .goal and .inScope and .acceptanceCriteria and .riskLevel' \
  "$CONTRACT" > /dev/null 2>&1; then
  echo "ERROR: Invalid contract (missing required fields)" >&2
  exit 1
fi

PROJECT_ROOT="${SIGNUM_PROJECT_ROOT:-$(pwd)}"
MAX_TURNS="${SIGNUM_MAX_TURNS:-30}"

echo "=== Signum CI ==="
echo "Contract: $CONTRACT"
echo "Project:  $PROJECT_ROOT"
echo "Max turns: $MAX_TURNS"

# --- Setup .signum directory ---
mkdir -p "$PROJECT_ROOT/.signum/reviews"
cp "$CONTRACT" "$PROJECT_ROOT/.signum/contract.json"

# --- Build claude invocation ---
TASK=$(jq -r '.goal' "$CONTRACT")

CLAUDE_ARGS=(
  -p "/signum $TASK"
  --output-format json
  --max-turns "$MAX_TURNS"
  --verbose
)

if [ -n "${SIGNUM_ALLOWED_TOOLS:-}" ]; then
  CLAUDE_ARGS+=(--allowedTools "$SIGNUM_ALLOWED_TOOLS")
fi

echo "Starting Signum pipeline..."
cd "$PROJECT_ROOT"
claude "${CLAUDE_ARGS[@]}" || true

# --- Extract decision ---
if [ ! -f .signum/proofpack.json ]; then
  echo "ERROR: proofpack.json not produced" >&2
  exit 1
fi

DECISION=$(jq -r '.decision' .signum/proofpack.json)
CONFIDENCE=$(jq -r '.confidence.overall // 0' .signum/proofpack.json)
RUN_ID=$(jq -r '.runId' .signum/proofpack.json)

echo ""
echo "=== Result ==="
echo "Decision:   $DECISION"
echo "Confidence: ${CONFIDENCE}%"
echo "Run ID:     $RUN_ID"

# --- Compute proofpack hash for artifact integrity ---
if command -v sha256sum >/dev/null 2>&1; then
  PP_HASH=$(sha256sum .signum/proofpack.json | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  PP_HASH=$(shasum -a 256 .signum/proofpack.json | awk '{print $1}')
else
  PP_HASH="unavailable"
fi
echo "Proofpack SHA-256: $PP_HASH"

# --- Map decision to exit code ---
case "$DECISION" in
  AUTO_OK)
    echo "Status: PASS"
    exit 0
    ;;
  AUTO_BLOCK)
    echo "Status: BLOCKED"
    exit 1
    ;;
  HUMAN_REVIEW)
    echo "Status: NEEDS REVIEW"
    exit 78
    ;;
  *)
    echo "ERROR: Unknown decision: $DECISION" >&2
    exit 1
    ;;
esac
