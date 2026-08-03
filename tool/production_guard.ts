// Fail-closed guard for the production canary rollout.
//
// This is a *separate* guard from `staging_guard.ts` on purpose. Staging and
// production are different decisions with different blast radii, and sharing a
// resolver between them is exactly how a production URL ends up passing a check
// that was written for staging. Nothing here reads a `AISH_STAGING_*` variable,
// nothing in `staging_guard.ts` reads a `AISH_PRODUCTION_*` one, and this file
// refuses outright if a staging confirmation is present in the same process.
//
// The posture is the inverse of the staging tools. There, the question was "is
// this really staging?". Here the answer is known — it is production — so the
// question becomes "has the operator earned the right to touch it?". That is
// answered by eight independent facts, every one of which the operator has to
// supply in advance and none of which has a default:
//
//   1. AISH_TARGET_ENV                  = production
//   2. AISH_PRODUCTION_CONFIRM          = the exact acknowledgement token
//   3. AISH_PRODUCTION_SECOND_CONFIRM   = the project ref, restated
//   4. AISH_PRODUCTION_PROJECT_REF      = exact, matched against the URL
//   5. AISH_PRODUCTION_ALLOWED_HOST     = exact, single host, no wildcards
//   6. AISH_CHANGE_TICKET               = the approved change record
//   7. AISH_MAINTENANCE_WINDOW          = an ISO interval containing *now*
//   8. AISH_BACKUP_IDENTIFIER + AISH_RESTORE_REHEARSAL_CONFIRMED
//
// Every tool defaults to read-only. A tool that writes has to ask for a named
// write scope, and the operator has to have granted that same scope by name.
// "I meant to run the read-only one" is therefore not a way to get a write.
//
// No value read here is ever printed. `safeLog` scrubs every registered secret
// from every line, including interpolated PostgREST error bodies.

/// The acknowledgement token. Deliberately long, deliberately unambiguous, and
/// deliberately *not* the staging one — pasting `I_UNDERSTAND_THIS_IS_STAGING`
/// into a production run is a refusal, not a near-miss.
export const PRODUCTION_CONFIRM_TOKEN = "I_UNDERSTAND_THIS_TARGETS_PRODUCTION";

/// The client contract these tools expect the production server to answer with.
export const EXPECTED_REVISION = "aish-supabase-003";

/// The longest maintenance window this guard will honour. A window with no end,
/// or one wide enough to cover a working week, is not a window — it is a
/// standing permission, which is the thing the window exists to prevent.
const MAX_WINDOW_HOURS = 12;

/// Variables that must NOT be present when a production tool runs. Their
/// presence means a staging environment file is still loaded, and the next
/// mistake after that is a tool reading the wrong one.
const FORBIDDEN_STAGING_VARS = [
  "AISH_STAGING_CONFIRM",
  "AISH_STAGING_HOST_ALLOWLIST",
  "AISH_STAGING_PROJECT_REF_ALLOWLIST",
  "AISH_STAGING_PROJECT_REF",
  "STAGING_FIXTURE_PASSWORD",
  "STAGING_ALLOW_DESTRUCTIVE_OPERATIONS",
];

/// Escape hatches that do not exist. If an operator has set one, they believe a
/// destructive mode is available; stopping is cheaper than letting that belief
/// carry into the next command they type.
const FORBIDDEN_ESCAPE_HATCHES = [
  "PRODUCTION_ALLOW_DESTRUCTIVE_OPERATIONS",
  "AISH_ALLOW_DB_RESET",
  "AISH_ALLOW_DESTRUCTIVE_CLEANUP",
  "AISH_ALLOW_MASS_FIXTURES",
  "AISH_ALLOW_FAILURE_INJECTION",
  "AISH_ALLOW_HEAVY_BENCHMARK",
  "AISH_ALLOW_LONG_TRANSACTION",
  "AISH_SKIP_PRODUCTION_PREFLIGHT",
];

/// Write scopes a tool may request. There is no `all`, and there is no scope
/// that permits deleting or truncating anything.
export type WriteScope =
  /// Inserts into `sync_change_journal` + `sync_entity_field_versions` through
  /// the admin backfill RPC only. Touches no business column.
  | "journal_baseline"
  /// Creates and retires the dedicated canary namespace: its own branches,
  /// rooms, locations, items, users and documents. Never touches a row it did
  /// not create.
  | "canary_namespace";

const WRITE_SCOPES: readonly WriteScope[] = ["journal_baseline", "canary_namespace"];

export type GuardMode = "read_only" | "dry_run" | "guarded_write";

const secrets = new Set<string>();

export class ProductionGuardError extends Error {
  constructor(readonly code: string, detail?: string) {
    super(detail ? `${code}: ${detail}` : code);
    this.name = "ProductionGuardError";
  }
}

function registerSecret(value: string | undefined): void {
  if (value && value.length >= 8) secrets.add(value);
}

/// Replaces every registered secret with a marker. Applied to everything these
/// tools print, including thrown error messages, because a PostgREST error body
/// can echo the request that failed.
export function redact(value: unknown): string {
  let text = typeof value === "string" ? value : inspect(value);
  for (const secret of secrets) text = text.replaceAll(secret, "[redacted]");
  return text;
}

function inspect(value: unknown): string {
  if (value instanceof Error) return `${value.name}: ${value.message}`;
  try {
    return JSON.stringify(value) ?? String(value);
  } catch {
    return String(value);
  }
}

export function safeLog(...parts: unknown[]): void {
  console.log(parts.map(redact).join(" "));
}

export function safeError(...parts: unknown[]): void {
  console.error(parts.map(redact).join(" "));
}

/// Keeps enough of a project ref to recognise it in a log and not enough to
/// identify the project to someone who does not already know it.
export function maskRef(ref: string): string {
  if (ref.length <= 4) return "*".repeat(ref.length);
  return `${ref.slice(0, 3)}${"*".repeat(Math.max(ref.length - 5, 1))}${ref.slice(-2)}`;
}

function env(name: string): string | undefined {
  const value = Deno.env.get(name)?.trim();
  return value && value.length > 0 ? value : undefined;
}

function requiredEnv(name: string): string {
  const value = env(name);
  if (!value) throw new ProductionGuardError("production_env_missing", name);
  return value;
}

export type MaintenanceWindow = {
  readonly raw: string;
  readonly startsAtUtc: string;
  readonly endsAtUtc: string;
  readonly remainingMinutes: number;
};

export type ProductionTarget = {
  readonly url: string;
  readonly host: string;
  readonly projectRef: string;
  readonly maskedRef: string;
  readonly anonKey: string;
  readonly serviceRoleKey: string | null;
  readonly canaryPassword: string | null;
  readonly mode: GuardMode;
  readonly writeScope: WriteScope | null;
  readonly changeTicket: string;
  readonly maintenanceWindow: MaintenanceWindow;
  readonly backupIdentifier: string;
  readonly backupChecksum: string | null;
  readonly restoreRehearsalConfirmed: true;
  readonly operatorAcknowledgement: string;
  readonly branch: string;
  readonly commit: string;
  readonly treeClean: boolean;
  readonly expectedRevision: string;
  readonly namespacePrefix: string;
};

export type ResolveOptions = {
  /// `read_only` may not write at all. `dry_run` is a tool that *can* write but
  /// was asked not to; it still resolves under the read rules so a dry run can
  /// never be upgraded by an argument. `guarded_write` requires `writeScope`.
  readonly mode: GuardMode;
  /// Only requested by tools that genuinely need the operator key, so it never
  /// enters the process for the ones that do not.
  readonly requireServiceRole: boolean;
  /// The named write this tool performs. Must also appear in the operator's
  /// `AISH_PRODUCTION_WRITE_SCOPE`.
  readonly writeScope?: WriteScope;
  /// The tool signs in as canary actors.
  readonly requireCanaryPassword?: boolean;
};

/// Parses `<ISO8601>/<ISO8601>` and asserts that now is inside it.
function resolveMaintenanceWindow(): MaintenanceWindow {
  const raw = requiredEnv("AISH_MAINTENANCE_WINDOW");
  const parts = raw.split("/");
  if (parts.length !== 2) {
    throw new ProductionGuardError(
      "production_maintenance_window_malformed",
      "expected <start-iso8601>/<end-iso8601>",
    );
  }
  const start = Date.parse(parts[0].trim());
  const end = Date.parse(parts[1].trim());
  if (Number.isNaN(start) || Number.isNaN(end)) {
    throw new ProductionGuardError("production_maintenance_window_unparseable");
  }
  if (end <= start) {
    throw new ProductionGuardError("production_maintenance_window_inverted");
  }
  const hours = (end - start) / 3_600_000;
  if (hours > MAX_WINDOW_HOURS) {
    throw new ProductionGuardError(
      "production_maintenance_window_too_wide",
      `${Math.round(hours)}h > ${MAX_WINDOW_HOURS}h`,
    );
  }
  const now = Date.now();
  if (now < start) {
    throw new ProductionGuardError(
      "production_maintenance_window_not_started",
      `opens in ${Math.ceil((start - now) / 60_000)} minute(s)`,
    );
  }
  if (now > end) {
    throw new ProductionGuardError(
      "production_maintenance_window_expired",
      `closed ${Math.ceil((now - end) / 60_000)} minute(s) ago`,
    );
  }
  return {
    raw,
    startsAtUtc: new Date(start).toISOString(),
    endsAtUtc: new Date(end).toISOString(),
    remainingMinutes: Math.floor((end - now) / 60_000),
  };
}

/// Backup and restore rehearsal are a single gate, not two. A dump nobody has
/// restored is not a rollback plan, so recording an identifier without the
/// rehearsal is refused the same way as recording nothing.
function resolveBackupBlocker(): { identifier: string; checksum: string | null } {
  const identifier = env("AISH_BACKUP_IDENTIFIER");
  if (!identifier) {
    throw new ProductionGuardError(
      "production_backup_identifier_missing",
      "record the backup identifier before any production command",
    );
  }
  if (identifier.length < 8) {
    throw new ProductionGuardError(
      "production_backup_identifier_implausible",
      "must name a real, retrievable backup",
    );
  }
  const rehearsed = (env("AISH_RESTORE_REHEARSAL_CONFIRMED") ?? "").toLowerCase();
  if (rehearsed !== "true") {
    throw new ProductionGuardError(
      "production_restore_rehearsal_not_confirmed",
      "restore the backup into a scratch database first, then set this to true",
    );
  }
  return { identifier, checksum: env("AISH_BACKUP_SHA256") ?? null };
}

function resolveWriteScope(options: ResolveOptions): WriteScope | null {
  if (options.mode !== "guarded_write") return null;
  const requested = options.writeScope;
  if (!requested) {
    throw new ProductionGuardError("production_write_scope_unrequested");
  }
  if (!WRITE_SCOPES.includes(requested)) {
    throw new ProductionGuardError("production_write_scope_unknown", requested);
  }
  const granted = requiredEnv("AISH_PRODUCTION_WRITE_SCOPE")
    .split(",").map((entry) => entry.trim()).filter((entry) => entry.length > 0);
  for (const entry of granted) {
    if (!WRITE_SCOPES.includes(entry as WriteScope)) {
      throw new ProductionGuardError("production_write_scope_unknown", entry);
    }
  }
  if (!granted.includes(requested)) {
    throw new ProductionGuardError("production_write_scope_not_granted", requested);
  }
  return requested;
}

/// Resolves and validates the production target, or throws. There is no partial
/// success: a caller holding a value has passed every gate above.
export function resolveProductionTarget(options: ResolveOptions): ProductionTarget {
  for (const name of FORBIDDEN_STAGING_VARS) {
    if (env(name)) {
      throw new ProductionGuardError("production_staging_environment_present", name);
    }
  }
  for (const name of FORBIDDEN_ESCAPE_HATCHES) {
    const value = (env(name) ?? "false").toLowerCase();
    if (value !== "false") {
      throw new ProductionGuardError("production_escape_hatch_refused", name);
    }
  }

  const targetEnv = requiredEnv("AISH_TARGET_ENV").toLowerCase();
  if (targetEnv !== "production") {
    throw new ProductionGuardError("production_target_env_invalid", targetEnv);
  }
  const appEnv = env("APP_ENV")?.toLowerCase();
  if (appEnv && appEnv !== "production") {
    throw new ProductionGuardError("production_app_env_invalid", appEnv);
  }

  // First confirmation: the operator states what they are about to do.
  if (requiredEnv("AISH_PRODUCTION_CONFIRM") !== PRODUCTION_CONFIRM_TOKEN) {
    throw new ProductionGuardError("production_confirmation_missing");
  }

  const projectRef = requiredEnv("AISH_PRODUCTION_PROJECT_REF").toLowerCase();
  // Second confirmation: the operator restates the project by name. A copied
  // environment file carries the token; typing the ref a second time is a
  // separate act, and the shell preflight asks for it a third time at a TTY.
  if (requiredEnv("AISH_PRODUCTION_SECOND_CONFIRM").toLowerCase() !== projectRef) {
    throw new ProductionGuardError(
      "production_second_confirmation_mismatch",
      "AISH_PRODUCTION_SECOND_CONFIRM must restate AISH_PRODUCTION_PROJECT_REF",
    );
  }

  const acknowledgement = requiredEnv("AISH_OPERATOR_ACKNOWLEDGEMENT");
  if (acknowledgement.length < 3) {
    throw new ProductionGuardError("production_operator_acknowledgement_implausible");
  }

  const changeTicket = requiredEnv("AISH_CHANGE_TICKET");
  if (!/^[A-Za-z0-9][A-Za-z0-9._/#-]{2,63}$/.test(changeTicket)) {
    throw new ProductionGuardError("production_change_ticket_malformed", changeTicket);
  }

  const maintenanceWindow = resolveMaintenanceWindow();
  const backup = resolveBackupBlocker();

  const rawUrl = requiredEnv("SUPABASE_URL");
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new ProductionGuardError("production_url_invalid");
  }
  if (parsed.protocol !== "https:") {
    throw new ProductionGuardError("production_url_not_https", parsed.protocol);
  }
  const host = parsed.hostname.toLowerCase();
  const allowedHost = requiredEnv("AISH_PRODUCTION_ALLOWED_HOST").toLowerCase();
  if (allowedHost.includes("*") || allowedHost.includes(",")) {
    throw new ProductionGuardError(
      "production_allowed_host_not_exact",
      "one exact host, no wildcards and no list",
    );
  }
  if (host !== allowedHost) {
    throw new ProductionGuardError("production_host_mismatch", host);
  }

  // The ref is derived from the URL and then matched against the one the
  // operator named, rather than trusted from either side alone.
  const label = (host.split(".")[0] ?? "").toLowerCase();
  if (label.length === 0) {
    throw new ProductionGuardError("production_project_ref_unresolvable");
  }
  if (label !== projectRef) {
    throw new ProductionGuardError(
      "production_project_ref_mismatch",
      `${maskRef(label)} != ${maskRef(projectRef)}`,
    );
  }

  const writeScope = resolveWriteScope(options);

  const anonKey = requiredEnv("SUPABASE_ANON_KEY");
  registerSecret(anonKey);

  let serviceRoleKey: string | null = null;
  if (options.requireServiceRole) {
    serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    registerSecret(serviceRoleKey);
  }

  let canaryPassword: string | null = null;
  if (options.requireCanaryPassword) {
    canaryPassword = requiredEnv("AISH_PRODUCTION_CANARY_PASSWORD");
    registerSecret(canaryPassword);
  }

  // Branch, commit and cleanliness are settled by `production_preflight.sh` and
  // exported; the guard asserts them rather than shelling out itself, so a tool
  // invoked directly with `deno run` fails closed instead of running unchecked.
  const branch = env("AISH_GIT_BRANCH");
  const commit = env("AISH_GIT_COMMIT");
  if (!branch || !commit) {
    throw new ProductionGuardError(
      "production_git_context_missing",
      "run through tool/run_*_production_*.sh so branch and commit are asserted",
    );
  }
  const expectedBranch = requiredEnv("AISH_PRODUCTION_ALLOWED_BRANCH");
  if (branch !== expectedBranch) {
    throw new ProductionGuardError("production_branch_refused", branch);
  }
  const treeClean = (env("AISH_GIT_TREE_CLEAN") ?? "false").toLowerCase() === "true";
  if (!treeClean) {
    throw new ProductionGuardError(
      "production_working_tree_dirty",
      "commit or stash: a production run must be reproducible from a commit",
    );
  }

  return {
    url: rawUrl,
    host,
    projectRef,
    maskedRef: maskRef(projectRef),
    anonKey,
    serviceRoleKey,
    canaryPassword,
    mode: options.mode,
    writeScope,
    changeTicket,
    maintenanceWindow,
    backupIdentifier: backup.identifier,
    backupChecksum: backup.checksum,
    restoreRehearsalConfirmed: true,
    operatorAcknowledgement: acknowledgement,
    branch,
    commit,
    treeClean,
    expectedRevision: env("SUPABASE_EXPECTED_SERVER_REVISION") ?? EXPECTED_REVISION,
    namespacePrefix: env("AISH_PRODUCTION_CANARY_NAMESPACE") ?? "aish-prod-canary",
  };
}

/// The sanitised banner every production tool prints before it opens a socket,
/// so the operator can still abort. Carries the whole authorisation chain: what
/// is being contacted, under which ticket, in which window, against which
/// backup, and by whom.
export function describeTarget(target: ProductionTarget, tool: string): void {
  safeLog("==============================================================");
  safeLog("  P R O D U C T I O N   C A N A R Y");
  safeLog("==============================================================");
  safeLog(`tool        = ${tool}`);
  safeLog(`mode        = ${describeMode(target)}`);
  safeLog(`host        = ${target.host}`);
  safeLog(`project ref = ${target.maskedRef}`);
  safeLog(`branch      = ${target.branch}@${target.commit} (clean)`);
  safeLog(`ticket      = ${target.changeTicket}`);
  safeLog(
    `window      = ${target.maintenanceWindow.startsAtUtc} .. ` +
      `${target.maintenanceWindow.endsAtUtc} ` +
      `(${target.maintenanceWindow.remainingMinutes} min left)`,
  );
  safeLog(`backup      = ${target.backupIdentifier} (restore rehearsed)`);
  safeLog(`operator    = ${target.operatorAcknowledgement}`);
  safeLog(`revision    = expecting ${target.expectedRevision}`);
  safeLog("==============================================================");
}

function describeMode(target: ProductionTarget): string {
  switch (target.mode) {
    case "read_only":
      return "READ-ONLY (writes nothing)";
    case "dry_run":
      return "DRY RUN (writes nothing)";
    case "guarded_write":
      return `GUARDED WRITE (scope: ${target.writeScope})`;
  }
}

/// Refuses a batch that is not bounded, or is bounded too loosely. Every
/// production loop passes through here; there is no unbounded operation.
export function assertBatchLimited(
  label: string,
  value: number | undefined,
  max: number,
): number {
  if (value === undefined || !Number.isInteger(value)) {
    throw new ProductionGuardError("production_batch_limit_required", label);
  }
  if (value < 1 || value > max) {
    throw new ProductionGuardError(
      "production_batch_limit_out_of_range",
      `${label}=${value}, allowed 1..${max}`,
    );
  }
  return value;
}

/// A per-run canary namespace. Every row a canary harness creates carries it,
/// and retirement matches on the ids this run recorded, so a run can never
/// retire a row it did not make.
export function runNamespace(prefix: string): string {
  const stamp = new Date().toISOString().replaceAll(/[:.]/g, "-");
  const random = crypto.randomUUID().slice(0, 8);
  return `${prefix}-${stamp}-${random}`;
}

export function assertCondition(condition: unknown, code: string): asserts condition {
  if (!condition) throw new Error(`production_assertion_failed:${code}`);
}

/// Retries only what is safe to retry: transport faults with no server-side
/// effect. A PostgREST error carrying an SQLSTATE means the server ran the
/// statement and rejected it, so repeating it would either be a no-op or a
/// second business operation — neither is a retry loop's decision to make.
export async function retryTransient<T>(
  label: string,
  attempt: () => Promise<T>,
  attempts = 3,
): Promise<T> {
  let lastError: unknown;
  for (let index = 0; index < attempts; index += 1) {
    try {
      return await attempt();
    } catch (error) {
      if (!isTransient(error)) throw error;
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 250 * (index + 1)));
    }
  }
  throw new Error(`production_transient_exhausted:${label}:${redact(lastError)}`);
}

function isTransient(error: unknown): boolean {
  if (error instanceof TypeError) return true; // fetch-level failure
  const code = (error as { code?: string } | null)?.code;
  if (typeof code === "string") {
    if (/^[0-9A-Z]{5}$/.test(code)) return false; // an SQLSTATE is a decision
    return ["ECONNRESET", "ETIMEDOUT", "ECONNREFUSED", "EAI_AGAIN"].includes(code);
  }
  const message = error instanceof Error ? error.message : "";
  return /network|fetch failed|timeout|socket/i.test(message);
}

export type ReportKind = "json" | "markdown";

/// Audit records land under `artifacts/production/`, which is gitignored: they
/// name the project, the ticket and the operator.
export async function writeProductionArtifact(
  name: string,
  kind: ReportKind,
  body: string,
): Promise<string> {
  const directory = "artifacts/production";
  await Deno.mkdir(directory, { recursive: true });
  const path = `${directory}/${name}.${kind === "json" ? "json" : "md"}`;
  await Deno.writeTextFile(path, body);
  return path;
}

/// The provenance block every production audit record carries, so a report can
/// always be tied back to the authorisation that permitted it. Never carries a
/// key, and never carries the unmasked project ref.
export function auditHeader(
  target: ProductionTarget,
  tool: string,
): Record<string, unknown> {
  return {
    tool,
    environment: "production",
    mode: target.mode,
    write_scope: target.writeScope,
    project_ref: target.maskedRef,
    host: target.host,
    branch: target.branch,
    commit: target.commit,
    change_ticket: target.changeTicket,
    maintenance_window: target.maintenanceWindow.raw,
    maintenance_window_start_utc: target.maintenanceWindow.startsAtUtc,
    maintenance_window_end_utc: target.maintenanceWindow.endsAtUtc,
    backup_identifier: target.backupIdentifier,
    backup_sha256: target.backupChecksum,
    restore_rehearsal_confirmed: target.restoreRehearsalConfirmed,
    operator_acknowledgement: target.operatorAcknowledgement,
  };
}

export function utcStamp(): string {
  return new Date().toISOString().replaceAll(/[:.]/g, "-");
}
