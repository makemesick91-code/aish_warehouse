#!/usr/bin/env bash
set -euo pipefail

# Production canary preflight. Read-only.
#
# Run this first, and run it again after every canary step. It verifies the
# authorisation chain (exact project ref, exact host, branch, commit, ticket,
# maintenance window, backup identifier, restore rehearsal, operator
# acknowledgement) and evaluates the runbook's stop conditions against the live
# project. It writes nothing.
#
# Credentials come from the operator environment only — see
# `.env.production.example`. Never load a staging environment in the same shell.
#
#   set -a; . /path/outside/the/repo/production.env; set +a
#   bash tool/run_supabase_production_preflight.sh

source "$(dirname "${BASH_SOURCE[0]}")/production_preflight.sh"

production_preflight "production_preflight" require_service_role

exec deno run \
  --node-modules-dir=auto \
  --allow-env \
  --allow-net \
  --allow-read=artifacts \
  --allow-write=artifacts \
  tool/production_preflight.ts "$@"
