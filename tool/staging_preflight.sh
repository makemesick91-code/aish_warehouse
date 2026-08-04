#!/usr/bin/env bash
# Shared shell preflight for every Milestone 12C staging runner.
#
# Sourced, never executed. It settles the two things the Deno guard cannot see
# for itself — which git branch this is and which commit — and refuses outright
# on the shapes of mistake that are cheapest to make at a shell prompt: a
# missing variable, a stray `db reset`, a working tree that is not the rollout
# branch.
#
# It never prints a variable's value, only whether one is set.

staging_require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "staging_env_missing: ${name}" >&2
    echo "load the operator environment first; see .env.staging.example" >&2
    return 1
  fi
}

staging_refuse_destructive() {
  # A remote reset is not a supported operation in this rollout, and neither is
  # anything else that would drop or truncate. Catching it here means the
  # refusal happens before a credential is ever read.
  local argument
  for argument in "$@"; do
    case "${argument,,}" in
      *"db reset"*|*--reset*|*"drop "*|*truncate*|*"delete from"*)
        echo "staging_destructive_command_refused: ${argument}" >&2
        return 1
        ;;
    esac
  done
}

staging_preflight() {
  local tool_name="$1"
  shift || true
  local require_service_role=0
  local mutating=1
  local argument
  for argument in "$@"; do
    case "$argument" in
      require_service_role) require_service_role=1 ;;
      read_only) mutating=0 ;;
    esac
  done

  staging_refuse_destructive "${BASH_ARGV[@]:-}" || return 1

  staging_require_var AISH_STAGING_CONFIRM || return 1
  staging_require_var AISH_TARGET_ENV || return 1
  staging_require_var AISH_STAGING_HOST_ALLOWLIST || return 1
  staging_require_var AISH_STAGING_PROJECT_REF_ALLOWLIST || return 1
  staging_require_var SUPABASE_URL || return 1
  staging_require_var SUPABASE_ANON_KEY || return 1
  if [[ "$require_service_role" == "1" ]]; then
    staging_require_var SUPABASE_SERVICE_ROLE_KEY || return 1
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "staging_not_a_git_worktree" >&2
    return 1
  fi

  AISH_GIT_BRANCH="$(git branch --show-current)"
  AISH_GIT_COMMIT="$(git rev-parse --short HEAD)"
  export AISH_GIT_BRANCH AISH_GIT_COMMIT

  if [[ "$mutating" == "1" && "$AISH_GIT_BRANCH" != "chore/12c-staging-rollout" ]]; then
    echo "staging_branch_refused: ${AISH_GIT_BRANCH}" >&2
    echo "staging writes are only driven from chore/12c-staging-rollout" >&2
    return 1
  fi

  # A dirty tree means the script on disk is not the script the rollout record
  # will point at. Advisory for read-only checks, refused for writes.
  if [[ -n "$(git status --porcelain)" ]]; then
    if [[ "$mutating" == "1" ]]; then
      echo "staging_working_tree_dirty: commit or stash before writing to staging" >&2
      return 1
    fi
    echo "warning: working tree is dirty; this run is not reproducible" >&2
  fi

  echo "preflight   = ${tool_name} on ${AISH_GIT_BRANCH}@${AISH_GIT_COMMIT}"
}
