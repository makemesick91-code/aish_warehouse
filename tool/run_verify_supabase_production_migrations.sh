#!/usr/bin/env bash
set -euo pipefail

# Production-safe migration verification. Read-only, no fixtures.
#
# Verifies which migrations are applied, that the pull RPC signature and
# security context are unchanged, the grant table, the journal's RLS/policy/
# column/trigger shape, and — over the wire with the anon key — that the
# refusals the grant table promises are the ones the running server gives.
#
# Unlike the staging equivalent it never creates an actor and never pages the
# feed as one. Feed behaviour is the canary E2E's job, inside its own namespace.
#
#   bash tool/run_verify_supabase_production_migrations.sh

source "$(dirname "${BASH_SOURCE[0]}")/production_preflight.sh"

production_preflight "verify_supabase_production_migrations" require_service_role

exec deno run \
  --node-modules-dir=auto \
  --allow-env \
  --allow-net \
  --allow-read=artifacts \
  --allow-write=artifacts \
  tool/verify_supabase_production_migrations.ts "$@"
