#!/usr/bin/env bash
set -euo pipefail

# Milestone 12C local end-to-end. Unlike the 12B runner this needs no Edge
# Function server: the pull contract is a database RPC, so every assertion goes
# through PostgREST with a real session token.
#
# Run `npx supabase db reset` first. The harness commits rows and advances the
# change journal, so a fresh database is what makes the cursor arithmetic
# reproducible from one run to the next.

set -a
eval "$(npx supabase status -o env 2>/dev/null)"
set +a
export SUPABASE_URL="${API_URL}"
export SUPABASE_ANON_KEY="${ANON_KEY}"
export SUPABASE_SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY}"

deno run --node-modules-dir=auto --allow-env --allow-net tool/supabase_12c_e2e.ts
