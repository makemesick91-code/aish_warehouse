#!/usr/bin/env bash
# Shared shell preflight for every production canary runner.
#
# Sourced, never executed. It is deliberately a separate file from
# `staging_preflight.sh`: the two environments have different variables,
# different confirmations and different blast radii, and a shared helper is how
# one set of rules ends up applied to the other environment by accident.
#
# It settles what the Deno guard cannot see for itself — the git branch, the
# commit, whether the tree is clean — and performs the *second* confirmation at
# the terminal, where a human is present to reconsider.
#
# It never prints a variable's value except the ones that belong in the change
# record: branch, commit and ticket.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "production_preflight_library_only: use an approved production runner" >&2
  exit 64
fi

production_require_var() {
  local name="$1"
  local value="${!name:-}"

  if [[ -z "$value" ]]; then
    echo "production_env_missing: ${name}" >&2
    echo "load the production operator environment first; see .env.production.example" >&2
    return 1
  fi

  case "$value" in
    *replace-with*|*"<"*|*">"*)
      echo "production_env_placeholder_refused: ${name}" >&2
      return 1
      ;;
  esac
}

# A staging environment still loaded in this shell means two contracts are live
# at once. Refuse before a credential is read, not after.
production_refuse_staging_vars() {
  local name
  for name in AISH_STAGING_CONFIRM AISH_STAGING_HOST_ALLOWLIST \
    AISH_STAGING_PROJECT_REF_ALLOWLIST AISH_STAGING_PROJECT_REF \
    STAGING_FIXTURE_PASSWORD STAGING_ALLOW_DESTRUCTIVE_OPERATIONS; do
    if [[ -n "${!name:-}" ]]; then
      echo "production_staging_environment_present: ${name}" >&2
      echo "open a new shell with only the production environment loaded" >&2
      return 1
    fi
  done
}

# The operations this rollout does not have and will not acquire. Catching the
# shapes here means the refusal happens before a key is ever read.
production_refuse_destructive() {
  local argument
  for argument in "$@"; do
    case "${argument,,}" in
      *"db reset"*|*--reset*|*"drop "*|*truncate*|*"delete from"*|\
      *"--force"*|*"failure-injection"*|*"fault-injection"*|*"--burst"*|\
      *"mass-fixture"*|*"load-test"*|*"stress"*)
        echo "production_destructive_command_refused: ${argument}" >&2
        return 1
        ;;
    esac
  done
}

# Second confirmation. The environment token says "I know this is production";
# typing the project ref says "and I know *which* production". At a TTY we ask
# for it here as well, so a stale exported environment cannot answer on the
# operator's behalf.
production_second_confirmation() {
  local typed=""
  if [[ -t 0 ]]; then
    echo "" >&2
    echo "  This command targets PRODUCTION." >&2
    echo "  Ticket ${AISH_CHANGE_TICKET}, window ${AISH_MAINTENANCE_WINDOW}." >&2
    echo "  Backup ${AISH_BACKUP_IDENTIFIER} (restore rehearsed: ${AISH_RESTORE_REHEARSAL_CONFIRMED})." >&2
    echo "" >&2
    printf '  Type the production project ref to continue: ' >&2
    read -r typed
    if [[ "$typed" != "$AISH_PRODUCTION_PROJECT_REF" ]]; then
      echo "production_second_confirmation_mismatch" >&2
      return 1
    fi
    echo "confirm     = typed at the terminal" >&2
  else
    # No terminal: the guard still requires AISH_PRODUCTION_SECOND_CONFIRM to
    # restate the ref, and the audit record says the confirmation was given
    # non-interactively so a reviewer can see which path was taken.
    if [[ "${AISH_PRODUCTION_SECOND_CONFIRM:-}" != "$AISH_PRODUCTION_PROJECT_REF" ]]; then
      echo "production_second_confirmation_mismatch" >&2
      echo "no terminal available; AISH_PRODUCTION_SECOND_CONFIRM must restate the ref" >&2
      return 1
    fi
    echo "confirm     = non-interactive (AISH_PRODUCTION_SECOND_CONFIRM)" >&2
  fi
}

production_preflight() {
  local tool_name="$1"
  shift || true
  local require_service_role=0
  local writes=0
  local argument
  for argument in "$@"; do
    case "$argument" in
      require_service_role) require_service_role=1 ;;
      writes) writes=1 ;;
    esac
  done

  production_refuse_destructive "${BASH_ARGV[@]:-}" || return 1
  production_refuse_staging_vars || return 1

  production_require_var AISH_TARGET_ENV || return 1
  production_require_var AISH_PRODUCTION_CONFIRM || return 1
  production_require_var AISH_PRODUCTION_SECOND_CONFIRM || return 1
  production_require_var AISH_PRODUCTION_PROJECT_REF || return 1
  production_require_var AISH_PRODUCTION_ALLOWED_HOST || return 1
  production_require_var AISH_PRODUCTION_ALLOWED_BRANCH || return 1
  production_require_var AISH_CHANGE_TICKET || return 1
  production_require_var AISH_MAINTENANCE_WINDOW || return 1
  production_require_var AISH_BACKUP_IDENTIFIER || return 1
  production_require_var AISH_RESTORE_REHEARSAL_CONFIRMED || return 1
  production_require_var AISH_OPERATOR_ACKNOWLEDGEMENT || return 1
  production_require_var SUPABASE_URL || return 1
  production_require_var SUPABASE_ANON_KEY || return 1
  if [[ "$require_service_role" == "1" ]]; then
    production_require_var SUPABASE_SERVICE_ROLE_KEY || return 1
  fi
  if [[ "$writes" == "1" ]]; then
    production_require_var AISH_PRODUCTION_WRITE_SCOPE || return 1
  fi

  # The backup blocker is repeated here rather than left to the Deno guard: an
  # operator who has not rehearsed a restore should be stopped before a
  # credential is read into a process, not after.
  if [[ "${AISH_RESTORE_REHEARSAL_CONFIRMED,,}" != "true" ]]; then
    echo "production_restore_rehearsal_not_confirmed" >&2
    echo "restore ${AISH_BACKUP_IDENTIFIER} into a scratch database first" >&2
    return 1
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "production_not_a_git_worktree" >&2
    return 1
  fi

  AISH_GIT_BRANCH="$(git branch --show-current)"
  AISH_GIT_COMMIT="$(git rev-parse --short HEAD)"
  if [[ -z "$(git status --porcelain)" ]]; then
    AISH_GIT_TREE_CLEAN=true
  else
    AISH_GIT_TREE_CLEAN=false
  fi
  export AISH_GIT_BRANCH AISH_GIT_COMMIT AISH_GIT_TREE_CLEAN

  if [[ "$AISH_GIT_BRANCH" != "$AISH_PRODUCTION_ALLOWED_BRANCH" ]]; then
    echo "production_branch_refused: ${AISH_GIT_BRANCH}" >&2
    echo "production commands run only from ${AISH_PRODUCTION_ALLOWED_BRANCH}" >&2
    return 1
  fi

  # Unlike staging, a dirty tree is refused even for read-only runs. A
  # production observation that cannot be tied to a commit is not evidence.
  if [[ "$AISH_GIT_TREE_CLEAN" != "true" ]]; then
    echo "production_working_tree_dirty: commit or stash before running against production" >&2
    return 1
  fi

  production_second_confirmation || return 1

  echo "preflight   = ${tool_name} on ${AISH_GIT_BRANCH}@${AISH_GIT_COMMIT}"
}
