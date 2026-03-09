#!/usr/bin/env bash
# dsl-runner.sh — typed DSL runner for signum verify blocks
# Subcommands: validate
set -euo pipefail

readonly MAX_STEPS=20
readonly MAX_TIMEOUT_MS=120000
readonly EXEC_WHITELIST="test ls wc cat jq"

# --- helpers ---

validate_error() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
validate_ok() { printf 'VALID\n'; exit 0; }

need_jq() {
  command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq not found\n' >&2; exit 1; }
}

# --- validate ---

cmd_validate() {
  local file="${1:-}"
  [[ -z "$file" ]] && validate_error "usage: dsl-runner.sh validate <file.json>"
  [[ -f "$file" ]] || validate_error "file not found: $file"

  need_jq

  # Parse JSON
  if ! jq empty "$file" 2>/dev/null; then
    validate_error "invalid JSON in $file"
  fi

  local step_count timeout_ms
  step_count=$(jq '.steps | length' "$file")
  timeout_ms=$(jq '.timeout_ms // 0' "$file")

  # Structural checks
  [[ "$step_count" -eq 0 ]] && validate_error "steps array is empty"
  [[ "$step_count" -gt "$MAX_STEPS" ]] && validate_error "too many steps: $step_count (max $MAX_STEPS)"
  [[ "$timeout_ms" -lt 1 ]] && validate_error "timeout_ms must be positive"
  [[ "$timeout_ms" -gt "$MAX_TIMEOUT_MS" ]] && validate_error "timeout_ms too large: $timeout_ms (max $MAX_TIMEOUT_MS)"

  # Collect capture names for forward-reference validation
  local -a capture_names=()
  local i step_type
  for (( i = 0; i < step_count; i++ )); do
    local has_http has_exec has_expect
    has_http=$(jq -r ".steps[$i] | has(\"http\")" "$file")
    has_exec=$(jq -r ".steps[$i] | has(\"exec\")" "$file")
    has_expect=$(jq -r ".steps[$i] | has(\"expect\")" "$file")

    # Determine step type
    local type_count=0
    if [[ "$has_http" == "true" ]]; then type_count=$((type_count + 1)); fi
    if [[ "$has_exec" == "true" ]]; then type_count=$((type_count + 1)); fi
    if [[ "$has_expect" == "true" ]]; then type_count=$((type_count + 1)); fi

    [[ "$type_count" -eq 0 ]] && validate_error "step $i: no recognized type (need http, exec, or expect)"

    if [[ "$has_http" == "true" && "$has_exec" == "true" ]]; then
      validate_error "step $i: cannot have both http and exec"
    fi

    # Validate http
    if [[ "$has_http" == "true" ]]; then
      _validate_http "$file" "$i"
    fi

    # Validate exec
    if [[ "$has_exec" == "true" ]]; then
      _validate_exec "$file" "$i"
    fi

    # Validate expect
    if [[ "$has_expect" == "true" ]]; then
      _validate_expect "$file" "$i" "${capture_names[*]:-}"
    fi

    # Track capture names
    local capture_name
    capture_name=$(jq -r ".steps[$i].capture // empty" "$file")
    if [[ -n "$capture_name" ]]; then
      capture_names+=("$capture_name")
    fi
  done

  validate_ok
}

_validate_http() {
  local file="$1" idx="$2"
  local url method
  url=$(jq -r ".steps[$idx].http.url // empty" "$file")
  method=$(jq -r ".steps[$idx].http.method // empty" "$file")

  [[ -z "$url" ]] && validate_error "step $idx: http.url is required"
  [[ -z "$method" ]] && validate_error "step $idx: http.method is required"

  # URL must target localhost or 127.0.0.1
  local host
  # Strip protocol if present
  host="${url#http://}"
  host="${host#https://}"
  # Extract host part (before first /)
  host="${host%%/*}"
  # Strip port
  host="${host%%:*}"

  if [[ "$host" != "localhost" && "$host" != "127.0.0.1" ]]; then
    validate_error "step $idx: http.url must target localhost or 127.0.0.1, got: $host"
  fi

  # Validate method
  case "$method" in
    GET|POST|PUT|DELETE|PATCH|HEAD) ;;
    *) validate_error "step $idx: invalid http method: $method" ;;
  esac
}

_validate_exec() {
  local file="$1" idx="$2"
  local argv0
  argv0=$(jq -r ".steps[$idx].exec.argv[0] // empty" "$file")

  [[ -z "$argv0" ]] && validate_error "step $idx: exec.argv is empty"

  # Whitelist check
  local allowed=false cmd
  for cmd in $EXEC_WHITELIST; do
    if [[ "$argv0" == "$cmd" ]]; then
      allowed=true
      break
    fi
  done

  if [[ "$allowed" == "false" ]]; then
    validate_error "step $idx: exec command '$argv0' not in whitelist ($EXEC_WHITELIST)"
  fi
}

_validate_expect() {
  local file="$1" idx="$2" known_captures="$3"
  local source
  source=$(jq -r ".steps[$idx].expect.source // empty" "$file")

  # If source is set, it must reference a known capture
  if [[ -n "$source" ]]; then
    local found=false name
    for name in $known_captures; do
      if [[ "$name" == "$source" ]]; then
        found=true
        break
      fi
    done
    if [[ "$found" == "false" ]]; then
      validate_error "step $idx: expect.source '$source' references unknown capture (known: $known_captures)"
    fi
  fi

  # Must have at least one assertion
  local has_json_path has_stdout_contains has_stdout_matches has_exit_code has_file_exists
  has_json_path=$(jq -r ".steps[$idx].expect | has(\"json_path\")" "$file")
  has_stdout_contains=$(jq -r ".steps[$idx].expect | has(\"stdout_contains\")" "$file")
  has_stdout_matches=$(jq -r ".steps[$idx].expect | has(\"stdout_matches\")" "$file")
  has_exit_code=$(jq -r ".steps[$idx].expect | has(\"exit_code\")" "$file")
  has_file_exists=$(jq -r ".steps[$idx].expect | has(\"file_exists\")" "$file")

  if [[ "$has_json_path" != "true" && "$has_stdout_contains" != "true" && \
        "$has_stdout_matches" != "true" && "$has_exit_code" != "true" && \
        "$has_file_exists" != "true" ]]; then
    validate_error "step $idx: expect must have at least one assertion (json_path, stdout_contains, stdout_matches, exit_code, file_exists)"
  fi

  # json_path requires equals
  if [[ "$has_json_path" == "true" ]]; then
    local equals
    equals=$(jq -r ".steps[$idx].expect | has(\"equals\")" "$file")
    if [[ "$equals" != "true" ]]; then
      validate_error "step $idx: expect.json_path requires expect.equals"
    fi
  fi
}

# --- dispatch ---

main() {
  local subcmd="${1:-}"
  shift || true

  case "$subcmd" in
    validate) cmd_validate "$@" ;;
    *)        printf 'usage: dsl-runner.sh validate <file.json>\n' >&2; exit 1 ;;
  esac
}

main "$@"
