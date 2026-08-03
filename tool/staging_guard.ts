// Shared fail-closed guard for every Milestone 12C staging tool.
//
// The rule this file exists to enforce: a script may only ever reach a project
// an operator has *named in advance*. A variable called `SUPABASE_URL` pointing
// at a host called "staging" proves nothing — an operator can paste a production
// URL into it in one keystroke. So the check is an allowlist of hosts and
// project refs the operator configured separately, plus an acknowledgement
// token, plus a branch assertion for anything that writes. Every one of those
// must line up; any missing piece is a refusal, never a default.
//
// Nothing here ever prints a key. `safeLog` scrubs every secret it was given
// before a line reaches stdout, so a diagnostic that interpolates a client
// object or an error body cannot leak one by accident.

export const ROLLOUT_BRANCH = "chore/12c-staging-rollout";
export const EXPECTED_REVISION = "aish-supabase-003";

/// Substrings that disqualify a host or project ref outright, before the
/// allowlist is even consulted. An operator who genuinely names a staging
/// project "prod-clone" has to rename it; that is the cheaper mistake.
const PRODUCTION_MARKERS = ["prod", "production", "live", "prd"];

const secrets = new Set<string>();

export class StagingGuardError extends Error {
  constructor(code: string, detail?: string) {
    super(detail ? `${code}: ${detail}` : code);
    this.name = "StagingGuardError";
  }
}

function registerSecret(value: string | undefined): void {
  if (value && value.length >= 8) secrets.add(value);
}

/// Replaces every registered secret with a marker. Applied to *everything* the
/// staging tools print, including thrown error messages, because a PostgREST
/// error body can echo the request it failed on.
export function redact(value: unknown): string {
  let text = typeof value === "string" ? value : inspect(value);
  for (const secret of secrets) {
    text = text.replaceAll(secret, "[redacted]");
  }
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
  return `${ref.slice(0, 3)}${"*".repeat(Math.max(ref.length - 5, 1))}${
    ref.slice(-2)
  }`;
}

function env(name: string): string | undefined {
  const value = Deno.env.get(name)?.trim();
  return value && value.length > 0 ? value : undefined;
}

function requiredEnv(name: string): string {
  const value = env(name);
  if (!value) throw new StagingGuardError("staging_env_missing", name);
  return value;
}

function allowlist(name: string): string[] {
  return requiredEnv(name)
    .split(",")
    .map((entry) => entry.trim().toLowerCase())
    .filter((entry) => entry.length > 0);
}

export type StagingTarget = {
  readonly url: string;
  readonly host: string;
  readonly projectRef: string;
  readonly maskedRef: string;
  readonly anonKey: string;
  readonly serviceRoleKey: string | null;
  readonly namespace: string;
  readonly expectedRevision: string;
  readonly fixturePassword: string | null;
  readonly branch: string | null;
  readonly commit: string | null;
};

export type ResolveOptions = {
  /// The tool writes to staging (fixtures, backfill). Adds the branch
  /// assertion and the destructive-operations check on top of the read checks.
  readonly mutating: boolean;
  /// The tool needs the operator key. Read-only checks that can run on an anon
  /// session leave it unset so the key never enters the process at all.
  readonly requireServiceRole: boolean;
  /// The tool signs in as fixture actors.
  readonly requireFixturePassword?: boolean;
};

function projectRefFromUrl(host: string): string {
  const explicit = env("AISH_STAGING_PROJECT_REF");
  if (explicit) return explicit.toLowerCase();
  const label = host.split(".")[0] ?? "";
  if (label.length === 0) {
    throw new StagingGuardError(
      "staging_project_ref_unresolvable",
      "set AISH_STAGING_PROJECT_REF for a custom domain",
    );
  }
  return label.toLowerCase();
}

function assertNotProduction(host: string, projectRef: string): void {
  for (const marker of PRODUCTION_MARKERS) {
    if (host.toLowerCase().includes(marker)) {
      throw new StagingGuardError("staging_refused_production_host", marker);
    }
    if (projectRef.includes(marker)) {
      throw new StagingGuardError("staging_refused_production_ref", marker);
    }
  }
}

/// Resolves and validates the staging target, or throws. There is no partial
/// success: a caller that gets a value back has passed every gate.
export function resolveStagingTarget(options: ResolveOptions): StagingTarget {
  const confirm = requiredEnv("AISH_STAGING_CONFIRM");
  if (confirm !== "I_UNDERSTAND_THIS_IS_STAGING") {
    throw new StagingGuardError("staging_confirmation_missing");
  }
  const targetEnv = requiredEnv("AISH_TARGET_ENV").toLowerCase();
  if (targetEnv !== "staging") {
    throw new StagingGuardError("staging_target_env_invalid", targetEnv);
  }
  const appEnv = env("APP_ENV")?.toLowerCase();
  if (appEnv && appEnv !== "staging") {
    throw new StagingGuardError("staging_app_env_invalid", appEnv);
  }

  const rawUrl = requiredEnv("SUPABASE_URL");
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new StagingGuardError("staging_url_invalid");
  }
  if (parsed.protocol !== "https:") {
    throw new StagingGuardError("staging_url_not_https", parsed.protocol);
  }
  const host = parsed.hostname.toLowerCase();
  const projectRef = projectRefFromUrl(host);

  assertNotProduction(host, projectRef);

  const hosts = allowlist("AISH_STAGING_HOST_ALLOWLIST");
  if (!hosts.includes(host)) {
    throw new StagingGuardError("staging_host_not_allowlisted", host);
  }
  const refs = allowlist("AISH_STAGING_PROJECT_REF_ALLOWLIST");
  if (!refs.includes(projectRef)) {
    throw new StagingGuardError(
      "staging_project_ref_not_allowlisted",
      maskRef(projectRef),
    );
  }

  const destructive = (env("STAGING_ALLOW_DESTRUCTIVE_OPERATIONS") ?? "false")
    .toLowerCase();
  if (destructive !== "false") {
    // No tool in this rollout has a destructive mode to unlock, so a truthy
    // value means the operator believes one exists. Stop rather than let that
    // belief carry into the next command they type.
    throw new StagingGuardError("staging_destructive_operations_refused");
  }

  const anonKey = requiredEnv("SUPABASE_ANON_KEY");
  registerSecret(anonKey);

  let serviceRoleKey: string | null = null;
  if (options.requireServiceRole) {
    serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    registerSecret(serviceRoleKey);
  }

  let fixturePassword: string | null = null;
  if (options.requireFixturePassword) {
    fixturePassword = requiredEnv("STAGING_FIXTURE_PASSWORD");
    registerSecret(fixturePassword);
  }

  const branch = env("AISH_GIT_BRANCH") ?? null;
  const commit = env("AISH_GIT_COMMIT") ?? null;
  if (options.mutating) {
    if (branch === null) {
      throw new StagingGuardError(
        "staging_branch_unknown",
        "run through tool/run_*.sh so the branch can be asserted",
      );
    }
    if (branch !== ROLLOUT_BRANCH) {
      throw new StagingGuardError("staging_branch_refused", branch);
    }
  }

  const expectedRevision = env("SUPABASE_EXPECTED_SERVER_REVISION") ??
    EXPECTED_REVISION;

  return {
    url: rawUrl,
    host,
    projectRef,
    maskedRef: maskRef(projectRef),
    anonKey,
    serviceRoleKey,
    namespace: env("STAGING_TEST_NAMESPACE") ?? "aish-12c-staging",
    expectedRevision,
    fixturePassword,
    branch,
    commit,
  };
}

/// The sanitised banner every tool prints before it touches the network, so the
/// operator sees what is about to be contacted and can abort. Deliberately not
/// derived from the key material.
export function describeTarget(target: StagingTarget, tool: string): void {
  safeLog("--------------------------------------------------------------");
  safeLog(`tool        = ${tool}`);
  safeLog("environment = staging");
  safeLog(`host        = ${target.host}`);
  safeLog(`project ref = ${target.maskedRef}`);
  safeLog(`branch      = ${target.branch ?? "(not asserted, read-only)"}`);
  safeLog(`commit      = ${target.commit ?? "(unknown)"}`);
  safeLog(`namespace   = ${target.namespace}`);
  safeLog(`revision    = expecting ${target.expectedRevision}`);
  safeLog("--------------------------------------------------------------");
}

/// A per-run fixture namespace. Every row a staging harness creates carries it,
/// and cleanup matches on it, so a run can never remove a row it did not make.
export function runNamespace(prefix: string): string {
  const stamp = new Date().toISOString().replaceAll(/[:.]/g, "-");
  const random = crypto.randomUUID().slice(0, 8);
  return `${prefix}-${stamp}-${random}`;
}

export function assertCondition(
  condition: unknown,
  code: string,
): asserts condition {
  if (!condition) throw new Error(`staging_assertion_failed:${code}`);
}

/// Retries only what is safe to retry: transport faults with no server-side
/// effect. A PostgREST error carrying an SQLSTATE means the server ran the
/// statement and rejected it, so repeating it would either be a no-op or a
/// second business operation — neither is something a retry loop should decide.
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
  throw new Error(`staging_transient_exhausted:${label}:${redact(lastError)}`);
}

function isTransient(error: unknown): boolean {
  if (error instanceof TypeError) return true; // fetch-level failure
  const code = (error as { code?: string } | null)?.code;
  if (typeof code === "string") {
    // A PostgREST/PostgreSQL SQLSTATE is a decision, not a fault.
    if (/^[0-9A-Z]{5}$/.test(code)) return false;
    return ["ECONNRESET", "ETIMEDOUT", "ECONNREFUSED", "EAI_AGAIN"].includes(
      code,
    );
  }
  const message = error instanceof Error ? error.message : "";
  return /network|fetch failed|timeout|socket/i.test(message);
}

export type ReportKind = "json" | "markdown";

/// Reports land under `artifacts/staging/`, which is gitignored: they name the
/// project and the actors that ran against it.
export async function writeArtifact(
  name: string,
  kind: ReportKind,
  body: string,
): Promise<string> {
  const directory = "artifacts/staging";
  await Deno.mkdir(directory, { recursive: true });
  const path = `${directory}/${name}.${kind === "json" ? "json" : "md"}`;
  await Deno.writeTextFile(path, body);
  return path;
}

export function utcStamp(): string {
  return new Date().toISOString().replaceAll(/[:.]/g, "-");
}
