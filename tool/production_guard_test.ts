// Refusal matrix for the production guard.
//
// The guard's whole value is what it refuses, and a refusal that was never
// exercised is a refusal nobody has seen work. These tests drive it entirely
// from the environment, offline: no network, no credentials, no Supabase.
//
// Run with:
//   deno test --allow-env tool/production_guard_test.ts
//
// Two properties matter beyond the individual cases:
//
//   * a fully valid environment resolves — otherwise the tests would pass by
//     refusing everything, which proves nothing;
//   * the staging confirmation token is not a production confirmation, and the
//     production token is not a staging one. The two environments are separate
//     contracts, and this is where that is checked rather than assumed.

import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  assertBatchLimited,
  maskRef,
  PRODUCTION_CONFIRM_TOKEN,
  ProductionGuardError,
  redact,
  resolveProductionTarget,
} from "./production_guard.ts";
import { resolveStagingTarget } from "./staging_guard.ts";

const MANAGED_KEYS = [
  "APP_ENV",
  "AISH_TARGET_ENV",
  "AISH_PRODUCTION_CONFIRM",
  "AISH_PRODUCTION_SECOND_CONFIRM",
  "AISH_PRODUCTION_PROJECT_REF",
  "AISH_PRODUCTION_ALLOWED_HOST",
  "AISH_PRODUCTION_ALLOWED_BRANCH",
  "AISH_PRODUCTION_WRITE_SCOPE",
  "AISH_PRODUCTION_CANARY_PASSWORD",
  "AISH_PRODUCTION_CANARY_NAMESPACE",
  "AISH_CHANGE_TICKET",
  "AISH_MAINTENANCE_WINDOW",
  "AISH_OPERATOR_ACKNOWLEDGEMENT",
  "AISH_BACKUP_IDENTIFIER",
  "AISH_BACKUP_SHA256",
  "AISH_RESTORE_REHEARSAL_CONFIRMED",
  "AISH_GIT_BRANCH",
  "AISH_GIT_COMMIT",
  "AISH_GIT_TREE_CLEAN",
  "SUPABASE_URL",
  "SUPABASE_ANON_KEY",
  "SUPABASE_SERVICE_ROLE_KEY",
  "SUPABASE_EXPECTED_SERVER_REVISION",
  "AISH_STAGING_CONFIRM",
  "AISH_STAGING_HOST_ALLOWLIST",
  "AISH_STAGING_PROJECT_REF_ALLOWLIST",
  "AISH_STAGING_PROJECT_REF",
  "STAGING_FIXTURE_PASSWORD",
  "STAGING_ALLOW_DESTRUCTIVE_OPERATIONS",
  "PRODUCTION_ALLOW_DESTRUCTIVE_OPERATIONS",
  "AISH_ALLOW_DB_RESET",
  "AISH_ALLOW_DESTRUCTIVE_CLEANUP",
  "AISH_ALLOW_MASS_FIXTURES",
  "AISH_ALLOW_FAILURE_INJECTION",
  "AISH_ALLOW_HEAVY_BENCHMARK",
  "AISH_ALLOW_LONG_TRANSACTION",
  "AISH_SKIP_PRODUCTION_PREFLIGHT",
];

/// A window that contains now, so the time gate is satisfied by default and each
/// test can break exactly one thing.
function currentWindow(): string {
  const start = new Date(Date.now() - 30 * 60_000).toISOString();
  const end = new Date(Date.now() + 90 * 60_000).toISOString();
  return `${start}/${end}`;
}

const VALID: Record<string, string> = {
  APP_ENV: "production",
  AISH_TARGET_ENV: "production",
  AISH_PRODUCTION_CONFIRM: PRODUCTION_CONFIRM_TOKEN,
  AISH_PRODUCTION_SECOND_CONFIRM: "examplerefabc",
  AISH_PRODUCTION_PROJECT_REF: "examplerefabc",
  AISH_PRODUCTION_ALLOWED_HOST: "examplerefabc.supabase.co",
  AISH_PRODUCTION_ALLOWED_BRANCH: "chore/12c-staging-rollout",
  AISH_CHANGE_TICKET: "CHG-4711",
  AISH_OPERATOR_ACKNOWLEDGEMENT: "operator-under-test",
  AISH_BACKUP_IDENTIFIER: "prod-backup-20260810T2200Z",
  AISH_RESTORE_REHEARSAL_CONFIRMED: "true",
  AISH_GIT_BRANCH: "chore/12c-staging-rollout",
  AISH_GIT_COMMIT: "abc1234",
  AISH_GIT_TREE_CLEAN: "true",
  SUPABASE_URL: "https://examplerefabc.supabase.co",
  SUPABASE_ANON_KEY: "anon-key-placeholder-not-a-real-key",
};

function applyEnv(overrides: Record<string, string | null> = {}): void {
  for (const key of MANAGED_KEYS) Deno.env.delete(key);
  const merged: Record<string, string | null> = {
    ...VALID,
    AISH_MAINTENANCE_WINDOW: currentWindow(),
    ...overrides,
  };
  for (const [key, value] of Object.entries(merged)) {
    if (value === null) continue;
    Deno.env.set(key, value);
  }
}

function refusalCode(
  overrides: Record<string, string | null>,
  options: Parameters<typeof resolveProductionTarget>[0] = {
    mode: "read_only",
    requireServiceRole: false,
  },
): string {
  applyEnv(overrides);
  try {
    resolveProductionTarget(options);
  } catch (error) {
    if (error instanceof ProductionGuardError) return error.code;
    throw error;
  }
  throw new Error("expected a refusal, got a resolved target");
}

Deno.test("a fully authorised environment resolves", () => {
  applyEnv();
  const target = resolveProductionTarget({ mode: "read_only", requireServiceRole: false });
  assertEquals(target.host, "examplerefabc.supabase.co");
  assertEquals(target.projectRef, "examplerefabc");
  assertEquals(target.changeTicket, "CHG-4711");
  assertEquals(target.backupIdentifier, "prod-backup-20260810T2200Z");
  assertEquals(target.restoreRehearsalConfirmed, true);
  assertEquals(target.mode, "read_only");
  assertEquals(target.writeScope, null);
  assertEquals(target.serviceRoleKey, null);
  assert(target.maintenanceWindow.remainingMinutes > 0);
});

Deno.test("the target environment must say production", () => {
  assertEquals(
    refusalCode({ AISH_TARGET_ENV: "staging" }),
    "production_target_env_invalid",
  );
  assertEquals(refusalCode({ AISH_TARGET_ENV: null }), "production_env_missing");
});

Deno.test("the first confirmation must be the exact production token", () => {
  assertEquals(
    refusalCode({ AISH_PRODUCTION_CONFIRM: null }),
    "production_env_missing",
  );
  assertEquals(
    refusalCode({ AISH_PRODUCTION_CONFIRM: "yes" }),
    "production_confirmation_missing",
  );
  // The staging acknowledgement is not a production one.
  assertEquals(
    refusalCode({ AISH_PRODUCTION_CONFIRM: "I_UNDERSTAND_THIS_IS_STAGING" }),
    "production_confirmation_missing",
  );
});

Deno.test("the second confirmation must restate the project ref", () => {
  assertEquals(
    refusalCode({ AISH_PRODUCTION_SECOND_CONFIRM: "someotherref" }),
    "production_second_confirmation_mismatch",
  );
  assertEquals(
    refusalCode({ AISH_PRODUCTION_SECOND_CONFIRM: null }),
    "production_env_missing",
  );
});

Deno.test("a staging environment loaded in the same shell is refused", () => {
  for (
    const key of [
      "AISH_STAGING_CONFIRM",
      "AISH_STAGING_HOST_ALLOWLIST",
      "AISH_STAGING_PROJECT_REF_ALLOWLIST",
      "STAGING_FIXTURE_PASSWORD",
    ]
  ) {
    assertEquals(
      refusalCode({ [key]: "anything" }),
      "production_staging_environment_present",
      `${key} should have been refused`,
    );
  }
});

Deno.test("escape hatches that do not exist are refused, not ignored", () => {
  for (
    const key of [
      "PRODUCTION_ALLOW_DESTRUCTIVE_OPERATIONS",
      "AISH_ALLOW_DB_RESET",
      "AISH_ALLOW_DESTRUCTIVE_CLEANUP",
      "AISH_ALLOW_MASS_FIXTURES",
      "AISH_ALLOW_FAILURE_INJECTION",
      "AISH_ALLOW_HEAVY_BENCHMARK",
      "AISH_ALLOW_LONG_TRANSACTION",
      "AISH_SKIP_PRODUCTION_PREFLIGHT",
    ]
  ) {
    assertEquals(
      refusalCode({ [key]: "true" }),
      "production_escape_hatch_refused",
      `${key} should have been refused`,
    );
  }
  // Explicitly false is the documented value and must not trip the check.
  applyEnv({ PRODUCTION_ALLOW_DESTRUCTIVE_OPERATIONS: "false" });
  resolveProductionTarget({ mode: "read_only", requireServiceRole: false });
});

Deno.test("the host must match exactly, with no wildcard and no list", () => {
  assertEquals(
    refusalCode({ SUPABASE_URL: "https://otherproject.supabase.co" }),
    "production_host_mismatch",
  );
  assertEquals(
    refusalCode({ AISH_PRODUCTION_ALLOWED_HOST: "*.supabase.co" }),
    "production_allowed_host_not_exact",
  );
  assertEquals(
    refusalCode({
      AISH_PRODUCTION_ALLOWED_HOST: "examplerefabc.supabase.co,other.supabase.co",
    }),
    "production_allowed_host_not_exact",
  );
});

Deno.test("the project ref parsed from the url must match the declared one", () => {
  assertEquals(
    refusalCode({
      SUPABASE_URL: "https://mismatchedref.supabase.co",
      AISH_PRODUCTION_ALLOWED_HOST: "mismatchedref.supabase.co",
    }),
    "production_project_ref_mismatch",
  );
});

Deno.test("the connection must be https", () => {
  assertEquals(
    refusalCode({ SUPABASE_URL: "http://examplerefabc.supabase.co" }),
    "production_url_not_https",
  );
  assertEquals(refusalCode({ SUPABASE_URL: "not-a-url" }), "production_url_invalid");
});

Deno.test("the backup blocker cannot be satisfied by an identifier alone", () => {
  assertEquals(
    refusalCode({ AISH_BACKUP_IDENTIFIER: null }),
    "production_backup_identifier_missing",
  );
  assertEquals(
    refusalCode({ AISH_BACKUP_IDENTIFIER: "x" }),
    "production_backup_identifier_implausible",
  );
  assertEquals(
    refusalCode({ AISH_RESTORE_REHEARSAL_CONFIRMED: "false" }),
    "production_restore_rehearsal_not_confirmed",
  );
  assertEquals(
    refusalCode({ AISH_RESTORE_REHEARSAL_CONFIRMED: null }),
    "production_restore_rehearsal_not_confirmed",
  );
});

Deno.test("the maintenance window must exist, be sane, and contain now", () => {
  assertEquals(
    refusalCode({ AISH_MAINTENANCE_WINDOW: null }),
    "production_env_missing",
  );
  assertEquals(
    refusalCode({ AISH_MAINTENANCE_WINDOW: "2026-08-10T22:00:00Z" }),
    "production_maintenance_window_malformed",
  );
  assertEquals(
    refusalCode({ AISH_MAINTENANCE_WINDOW: "yesterday/tomorrow" }),
    "production_maintenance_window_unparseable",
  );
  assertEquals(
    refusalCode({
      AISH_MAINTENANCE_WINDOW: "2026-08-11T02:00:00Z/2026-08-10T22:00:00Z",
    }),
    "production_maintenance_window_inverted",
  );
  const now = Date.now();
  assertEquals(
    refusalCode({
      AISH_MAINTENANCE_WINDOW: `${new Date(now - 48 * 3_600_000).toISOString()}/${
        new Date(now + 48 * 3_600_000).toISOString()
      }`,
    }),
    "production_maintenance_window_too_wide",
  );
  assertEquals(
    refusalCode({
      AISH_MAINTENANCE_WINDOW: `${new Date(now + 3_600_000).toISOString()}/${
        new Date(now + 7_200_000).toISOString()
      }`,
    }),
    "production_maintenance_window_not_started",
  );
  assertEquals(
    refusalCode({
      AISH_MAINTENANCE_WINDOW: `${new Date(now - 7_200_000).toISOString()}/${
        new Date(now - 3_600_000).toISOString()
      }`,
    }),
    "production_maintenance_window_expired",
  );
});

Deno.test("the change ticket must look like a change record", () => {
  assertEquals(refusalCode({ AISH_CHANGE_TICKET: null }), "production_env_missing");
  assertEquals(
    refusalCode({ AISH_CHANGE_TICKET: "no spaces allowed" }),
    "production_change_ticket_malformed",
  );
});

Deno.test("the operator has to acknowledge by name", () => {
  assertEquals(
    refusalCode({ AISH_OPERATOR_ACKNOWLEDGEMENT: null }),
    "production_env_missing",
  );
  assertEquals(
    refusalCode({ AISH_OPERATOR_ACKNOWLEDGEMENT: "x" }),
    "production_operator_acknowledgement_implausible",
  );
});

Deno.test("git context is asserted, not assumed", () => {
  assertEquals(refusalCode({ AISH_GIT_BRANCH: null }), "production_git_context_missing");
  assertEquals(refusalCode({ AISH_GIT_COMMIT: null }), "production_git_context_missing");
  assertEquals(refusalCode({ AISH_GIT_BRANCH: "main" }), "production_branch_refused");
  assertEquals(
    refusalCode({ AISH_GIT_TREE_CLEAN: "false" }),
    "production_working_tree_dirty",
  );
  // Unlike staging, read-only runs are refused on a dirty tree too.
  assertEquals(
    refusalCode({ AISH_GIT_TREE_CLEAN: null }),
    "production_working_tree_dirty",
  );
});

Deno.test("a write needs a scope the operator granted by name", () => {
  const write = {
    mode: "guarded_write" as const,
    requireServiceRole: false,
    writeScope: "journal_baseline" as const,
  };
  assertEquals(
    refusalCode({ AISH_PRODUCTION_WRITE_SCOPE: null }, write),
    "production_env_missing",
  );
  assertEquals(
    refusalCode({ AISH_PRODUCTION_WRITE_SCOPE: "canary_namespace" }, write),
    "production_write_scope_not_granted",
  );
  assertEquals(
    refusalCode({ AISH_PRODUCTION_WRITE_SCOPE: "all" }, write),
    "production_write_scope_unknown",
  );

  applyEnv({ AISH_PRODUCTION_WRITE_SCOPE: "journal_baseline,canary_namespace" });
  const target = resolveProductionTarget(write);
  assertEquals(target.mode, "guarded_write");
  assertEquals(target.writeScope, "journal_baseline");
});

Deno.test("a dry run resolves under the read rules and holds no write scope", () => {
  applyEnv();
  const target = resolveProductionTarget({ mode: "dry_run", requireServiceRole: false });
  assertEquals(target.mode, "dry_run");
  assertEquals(target.writeScope, null);
});

Deno.test("the service-role key is only read when a tool asks for it", () => {
  applyEnv();
  assertEquals(
    refusalCode({}, { mode: "read_only", requireServiceRole: true }),
    "production_env_missing",
  );
  applyEnv({ SUPABASE_SERVICE_ROLE_KEY: "service-role-key-placeholder" });
  const target = resolveProductionTarget({ mode: "read_only", requireServiceRole: true });
  assertEquals(target.serviceRoleKey, "service-role-key-placeholder");
});

Deno.test("every registered secret is scrubbed from output", () => {
  applyEnv({ SUPABASE_SERVICE_ROLE_KEY: "super-secret-service-role-value" });
  resolveProductionTarget({ mode: "read_only", requireServiceRole: true });
  const line = redact(
    `PostgREST said: apikey=super-secret-service-role-value failed for ` +
      `anon-key-placeholder-not-a-real-key`,
  );
  assert(!line.includes("super-secret-service-role-value"));
  assert(!line.includes("anon-key-placeholder-not-a-real-key"));
  assert(line.includes("[redacted]"));
});

Deno.test("a project ref is masked in anything it appears in", () => {
  assertEquals(maskRef("examplerefabc"), "exa********bc");
  assertEquals(maskRef("ab"), "**");
});

Deno.test("no loop runs without a bound", () => {
  assertThrows(
    () => assertBatchLimited("max-batches", undefined, 50),
    ProductionGuardError,
    "production_batch_limit_required",
  );
  assertThrows(
    () => assertBatchLimited("batch-size", 0, 100),
    ProductionGuardError,
    "production_batch_limit_out_of_range",
  );
  assertThrows(
    () => assertBatchLimited("batch-size", 101, 100),
    ProductionGuardError,
    "production_batch_limit_out_of_range",
  );
  assertThrows(
    () => assertBatchLimited("batch-size", 2.5, 100),
    ProductionGuardError,
    "production_batch_limit_required",
  );
  assertEquals(assertBatchLimited("batch-size", 25, 100), 25);
});

Deno.test("the staging guard does not accept a production confirmation", () => {
  // The inverse of the separation checked above: pointing the staging tools at
  // production by pasting the production token into AISH_STAGING_CONFIRM must
  // fail, and it must fail on the confirmation rather than sneak through to the
  // allowlist check.
  for (const key of MANAGED_KEYS) Deno.env.delete(key);
  Deno.env.set("AISH_STAGING_CONFIRM", PRODUCTION_CONFIRM_TOKEN);
  Deno.env.set("AISH_TARGET_ENV", "staging");
  Deno.env.set("SUPABASE_URL", "https://examplerefabc.supabase.co");
  Deno.env.set("SUPABASE_ANON_KEY", "anon-key-placeholder-not-a-real-key");
  Deno.env.set("AISH_STAGING_HOST_ALLOWLIST", "examplerefabc.supabase.co");
  Deno.env.set("AISH_STAGING_PROJECT_REF_ALLOWLIST", "examplerefabc");
  assertThrows(
    () => resolveStagingTarget({ mutating: false, requireServiceRole: false }),
    Error,
    "staging_confirmation_missing",
  );
  for (const key of MANAGED_KEYS) Deno.env.delete(key);
});
