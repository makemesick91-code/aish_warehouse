#!/usr/bin/env bash
set -euo pipefail

# Every local gate that must pass BEFORE any production canary is run.
#
# Why this exists. On 2026-08-03 the static safety suite was invoked by hand as
#
#     deno test tool/production_canary_safety_test.ts
#
# without `--allow-read`. Deno refused the suite access to the source files it
# reads, so it reported 0/11 and exited. That is not an assertion failure — it
# is the gate never running at all, and the production write went ahead behind
# it. A gate whose invocation is retyped from memory each time is a gate that
# will eventually be retyped wrong.
#
# So the invocation lives here, once, with the permissions each suite actually
# needs and no more:
#
#   * `--allow-read=tool`  the safety suite reads harness source from `tool/`.
#   * `--allow-env`        the guard suite exercises refusals driven by the
#                          environment contract.
#   * nothing at all       for the namespace and diagnostics suites.
#
# No suite here is granted `-A`, `--allow-all`, `--allow-net`, `--allow-run` or
# `--allow-write`. Nothing here reaches the network, so nothing here can touch a
# remote project, and `.env.production.local` is never sourced.
#
# Usage:
#   bash tool/run_production_canary_local_gates.sh
#
# Exit code: 0 when every gate passed, non-zero at the first one that did not.

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# A production contract inherited from the caller's shell has no business in a
# local gate run. Unsetting is not a refusal — these gates are meant to be
# runnable at any time, including outside a maintenance window — it just makes
# sure nothing here can be pointed at production by accident.
unset AISH_TARGET_ENV AISH_PRODUCTION_CONFIRM AISH_PRODUCTION_CONFIRM_REF \
      SUPABASE_URL SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY \
      SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD AISH_CANARY_PASSWORD 2>/dev/null || true

failures=0
gate() {
  local label="$1"; shift
  printf '\n=== %s\n' "$label"
  if "$@"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\n' "$label"
    failures=$((failures + 1))
    # Fail closed on the first gate that fails. A later gate passing tells an
    # operator nothing useful once an earlier one has already said no.
    printf '\nlocal gates: FAIL at "%s"\n' "$label"
    exit 1
  fi
}

gate "shell syntax (bash -n tool/*.sh)" bash -n tool/*.sh
gate "production preflight shell regression" bash tool/production_preflight_shell_test.sh
gate "production guard refusals" \
  deno test --allow-env tool/production_guard_test.ts
gate "canary namespace behaviour" \
  deno test tool/production_canary_namespace_test.ts
gate "canary source safety fences" \
  deno test --allow-read=tool tool/production_canary_safety_test.ts
gate "realtime diagnostics classification" \
  deno test tool/realtime_diagnostics_test.ts
gate "read-only SQL checker" \
  deno test --allow-read=artifacts tool/readonly_sql_check_test.ts
gate "type check (deno check tool/*.ts)" deno check tool/*.ts
gate "no whitespace or conflict damage in the diff" git diff --check

printf '\nlocal gates: PASS (%d failures)\n' "$failures"
