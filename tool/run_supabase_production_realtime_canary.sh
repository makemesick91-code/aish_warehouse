#!/usr/bin/env bash
set -euo pipefail

# Realtime canary against production, inside a dedicated canary namespace.
#
# Creates its own branches, rooms, catalogue and throwaway accounts, asserts
# invalidation and cross-branch isolation over real websocket frames, then
# retires everything it created. It never subscribes to, reads, or writes a real
# tenant's rows.
#
# No burst, no failure injection, no load. Those stay local and on staging.
#
# Requires AISH_PRODUCTION_WRITE_SCOPE to include `canary_namespace`.
#
#   bash tool/run_supabase_production_realtime_canary.sh

source "$(dirname "${BASH_SOURCE[0]}")/production_preflight.sh"

production_preflight "supabase_production_realtime_canary" require_service_role writes

exec deno run \
  --node-modules-dir=auto \
  --allow-env \
  --allow-net \
  --allow-read=artifacts \
  --allow-write=artifacts \
  tool/supabase_production_realtime_canary.ts "$@"
