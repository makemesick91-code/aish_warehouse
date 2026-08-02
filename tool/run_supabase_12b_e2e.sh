#!/usr/bin/env bash
set -euo pipefail

mkdir -p .dart_tool
set -a
eval "$(npx supabase status -o env 2>/dev/null)"
set +a
export SUPABASE_URL="${API_URL}"
export SUPABASE_ANON_KEY="${ANON_KEY}"
export SUPABASE_SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY}"
functions_url="${FUNCTIONS_URL:-${API_URL}/functions/v1}"

npx supabase functions serve >.dart_tool/supabase-functions-12b.log 2>&1 &
function_pid=$!
cleanup() {
  kill "${function_pid}" 2>/dev/null || true
  wait "${function_pid}" 2>/dev/null || true
}
trap cleanup EXIT

for _ in {1..40}; do
  if curl --silent --output /dev/null "${functions_url}/trusted-upload-intent"; then
    break
  fi
  sleep 0.25
done

deno run --node-modules-dir=auto --allow-env --allow-net tool/supabase_12b_e2e.ts
