#!/usr/bin/env bash
set -euo pipefail

# Minimal production canary end-to-end: 12B push, deterministic 12C pull, branch
# isolation, Realtime invalidation, disconnect and catch-up, duplicate movements
# zero, negative stock zero.
#
# Runs inside a dedicated canary namespace and pushes exactly one document — a
# purchase request, which posts no stock movement. The canary therefore never
# writes to the ledger, so the duplicate-movement and negative-stock checks are
# about production's real health rather than the canary's own leftovers.
#
# Requires AISH_PRODUCTION_WRITE_SCOPE to include `canary_namespace`.
#
#   bash tool/run_supabase_production_canary_e2e.sh

source "$(dirname "${BASH_SOURCE[0]}")/production_preflight.sh"

production_preflight "supabase_production_canary_e2e" require_service_role writes

exec deno run \
  --node-modules-dir=auto \
  --allow-env \
  --allow-net \
  --allow-read=artifacts \
  --allow-write=artifacts \
  tool/supabase_production_canary_e2e.ts "$@"
