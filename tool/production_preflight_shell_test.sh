#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

set +e
output="$(bash tool/production_preflight.sh 2>&1)"
rc=$?
set -e

[[ "$rc" -eq 64 ]] ||
  fail "direct execution expected exit 64, got $rc"

[[ "$output" == *"production_preflight_library_only"* ]] ||
  fail "direct execution did not emit library-only refusal"

bash -c '
  source tool/production_preflight.sh
  declare -F production_preflight >/dev/null
' || fail "preflight library cannot be sourced"

set +e
output="$(
  bash -c '
    source tool/production_preflight.sh
    AISH_PRODUCTION_PROJECT_REF=replace-with-production-project-ref
    production_require_var AISH_PRODUCTION_PROJECT_REF
  ' 2>&1
)"
rc=$?
set -e

[[ "$rc" -eq 1 ]] ||
  fail "placeholder expected exit 1, got $rc"

[[ "$output" == *"production_env_placeholder_refused"* ]] ||
  fail "placeholder was not explicitly refused"

echo "production preflight shell regression tests: PASS"
