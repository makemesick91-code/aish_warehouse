#!/usr/bin/env bash
set -euo pipefail

# Low-load production measurement.
#
# Default is metrics only and is genuinely read-only: journal rows, table bytes,
# index bytes, max cursor, commit horizon. One RPC call, no session, no writes.
#
#   bash tool/run_benchmark_supabase_production_readonly.sh
#
# `--with-pull` adds empty/1/50/200 page latency as p50/p95. Measuring a pull
# needs an authenticated session with a registered device, which is a write, so
# that mode creates the dedicated canary namespace and retires it afterwards. It
# requires AISH_PRODUCTION_WRITE_SCOPE to include `canary_namespace`.
#
#   bash tool/run_benchmark_supabase_production_readonly.sh --with-pull
#
# Samples are sequential with a pause between them. This cannot become a load
# test; the heavy benchmark stays on staging.

source "$(dirname "${BASH_SOURCE[0]}")/production_preflight.sh"

writes_flag=""
for argument in "$@"; do
  if [[ "$argument" == "--with-pull" ]]; then
    writes_flag="writes"
  fi
done

production_preflight "benchmark_supabase_production_readonly" require_service_role ${writes_flag:+$writes_flag}

exec deno run \
  --node-modules-dir=auto \
  --allow-env \
  --allow-net \
  --allow-read=artifacts \
  --allow-write=artifacts \
  tool/benchmark_supabase_production_readonly.ts "$@"
