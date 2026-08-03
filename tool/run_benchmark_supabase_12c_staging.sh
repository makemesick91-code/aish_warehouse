#!/usr/bin/env bash
set -euo pipefail

# Milestone 12C journal and pull-RPC measurement, against staging.
#
# Staging only. Never calls `supabase db reset`, never touches a local stack,
# and reads every credential from the operator environment. See
# `.env.staging.example` and `docs/supabase_12c_staging_rollout.md`.

source "$(dirname "${BASH_SOURCE[0]}")/staging_preflight.sh"

staging_preflight "benchmark_supabase_12c_staging" require_service_role

exec deno run \
  --node-modules-dir=auto \
  --allow-env \
  --allow-net \
  --allow-read=artifacts \
  --allow-write=artifacts \
  tool/benchmark_supabase_12c_staging.ts "$@"
