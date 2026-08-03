#!/usr/bin/env bash
set -euo pipefail

# Change-journal baseline backfill against production, one small batch at a time
# with a full business-invariant check between every one of them.
#
# Dry run is the default. `--max-batches` is mandatory on every invocation and
# `--entity-types` is mandatory for a first run: the first thing that touches
# production is a named slice, not the whole catalogue.
#
# This never calls `supabase db reset`, never calls `db push`, and has no
# destructive mode to unlock. Applying migrations is a separate, deliberate step
# in the runbook.
#
#   bash tool/run_supabase_production_backfill_canary.sh \
#     --max-batches=2 --entity-types=category
#   bash tool/run_supabase_production_backfill_canary.sh \
#     --max-batches=2 --entity-types=category --execute
#   bash tool/run_supabase_production_backfill_canary.sh \
#     --max-batches=4 --execute --resume <run-id>
#
# `--execute` additionally requires AISH_PRODUCTION_WRITE_SCOPE to include
# `journal_baseline`.

source "$(dirname "${BASH_SOURCE[0]}")/production_preflight.sh"

writes_flag=""
for argument in "$@"; do
  if [[ "$argument" == "--execute" ]]; then
    writes_flag="writes"
  fi
done

production_preflight "supabase_production_backfill_canary" require_service_role ${writes_flag:+$writes_flag}

exec deno run \
  --node-modules-dir=auto \
  --allow-env \
  --allow-net \
  --allow-read=artifacts \
  --allow-write=artifacts \
  tool/supabase_production_backfill_canary.ts "$@"
