// Regression fence around the production canary's cleanup path.
//
// The behavioural proof lives in `production_canary_namespace_test.ts`; these
// are the few properties a behaviour test cannot see, because they are about
// what the source is *allowed to contain* rather than what it does on a given
// run. Each one corresponds to a defect the canary audit found or to a fix that
// would be silently undone by an ordinary-looking edit.
//
// Read from disk on purpose: a regression here is a regression in the file an
// operator reviews, not in a value some other module re-exports.
//
// Run with:
//   deno test --allow-read=tool tool/production_canary_safety_test.ts
//
// The permission is not optional and the scope is not decoration. Without
// `--allow-read` Deno refuses the suite access to the sources it inspects and
// it reports 0 tests — which is what happened before the 2026-08-03 production
// canary, where this suite was invoked bare, reported 0/11, and the write went
// ahead behind a gate that had never run. Prefer the approved runner, which
// cannot be retyped wrong:
//
//   bash tool/run_production_canary_local_gates.sh

import { assert, assertEquals } from "jsr:@std/assert@1";

const NAMESPACE = "tool/production_canary_namespace.ts";
const HARNESSES = [
  "tool/supabase_production_canary_e2e.ts",
  "tool/supabase_production_realtime_canary.ts",
];

async function source(path: string): Promise<string> {
  return await Deno.readTextFile(new URL(`../${path}`, import.meta.url));
}

/// Strips line and block comments, so a prohibition is not tripped by the
/// comment that explains it.
function code(text: string): string {
  return text
    .replaceAll(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("//") && !line.trimStart().startsWith("///"))
    .join("\n");
}

Deno.test("the canary never issues a delete", async () => {
  for (const path of [NAMESPACE, ...HARNESSES]) {
    const body = code(await source(path));
    for (const forbidden of [".delete(", "deleteUser", "removeUser", ".truncate("]) {
      assert(
        !body.includes(forbidden),
        `${path} contains ${forbidden}; the canary retires, it does not delete`,
      );
    }
  }
});

Deno.test("the canary never reaches for the destructive-cleanup escape hatch", async () => {
  for (const path of [NAMESPACE, ...HARNESSES]) {
    const body = await source(path);
    assert(
      !body.includes("AISH_ALLOW_DESTRUCTIVE_CLEANUP"),
      `${path} references the destructive cleanup override`,
    );
  }
});

Deno.test("every update in the namespace is bound to an explicit id list", async () => {
  const body = code(await source(NAMESPACE));
  const updates = [...body.matchAll(/\.update\(/g)];
  // The single update lives in `supabaseBackend.softRetire`, whose id list is a
  // required argument. More than one means a second write path appeared that
  // this test has not seen.
  assertEquals(
    updates.length,
    1,
    "a new update appeared in the namespace; it must be reviewed for an id filter",
  );
  const index = body.indexOf(".update(");
  const statement = body.slice(index, index + 220);
  assert(statement.includes('.in("id"'), "the retirement update is not filtered by id");
  assert(
    statement.includes('.select("id")'),
    "the retirement update does not return the ids it matched",
  );
});

Deno.test("cleanup never filters by name, prefix or namespace token", async () => {
  const body = code(await source(NAMESPACE));
  // Scoped to `supabaseBackend`, the one function that builds PostgREST
  // queries. Checking the whole file would collide with `Array.prototype`
  // methods of the same name and force the check to be weakened.
  const start = body.indexOf("function supabaseBackend(");
  assert(start > 0, "supabaseBackend is no longer the single Supabase call site");
  const end = body.indexOf("export class ProductionCanaryNamespace", start);
  const backend = body.slice(start, end);
  for (const forbidden of [
    ".like(", ".ilike(", ".match(", ".filter(", ".neq(", ".gt(", ".or(", ".not(",
  ]) {
    assert(
      !backend.includes(forbidden),
      `${NAMESPACE} uses ${forbidden}; cleanup matches recorded ids, never a pattern`,
    );
  }
  // And the class body itself must not build queries at all.
  const classBody = body.slice(end);
  assert(
    !classBody.includes("this.service.from("),
    "the class bypasses the backend seam and queries Supabase directly",
  );
});

Deno.test("the Auth identity is recorded before the rows that depend on it", async () => {
  const body = code(await source(NAMESPACE));
  const created = body.indexOf("this.backend.createAuthUser(");
  const tracked = body.indexOf("this.trackAuthUser(");
  const domainInsert = body.indexOf('this.backend.insert("users"');
  const linkInsert = body.indexOf('this.backend.insert("user_auth_links"');
  assert(created > 0 && tracked > 0 && domainInsert > 0 && linkInsert > 0);
  assert(
    tracked > created && tracked < domainInsert && tracked < linkInsert,
    "the Auth identity must be tracked between createUser and the inserts that follow it",
  );
});

Deno.test("cleanup is driven by created identities, not by configured actors", async () => {
  const body = code(await source(NAMESPACE));
  const retirement = body.slice(body.indexOf("private async runRetirement"));
  assert(
    retirement.includes("this.authIdentities"),
    "retirement does not iterate the created Auth identities",
  );
  assert(
    !retirement.includes("this.set.actors"),
    "retirement reads set.actors, which is only populated for fully configured actors",
  );
});

Deno.test("every setup remote write sits inside the cleanup-protected try", async () => {
  const body = code(await source(NAMESPACE));
  // `setup()` is called from exactly one place, and that place is a try whose
  // catch retires the partial namespace.
  const call = body.indexOf("await instance.setup(");
  const tryStart = body.lastIndexOf("try {", call);
  const catchStart = body.indexOf("} catch (setupError)", call);
  assert(tryStart > 0 && catchStart > call, "setup() is not wrapped in a try/catch");
  assert(
    body.slice(catchStart, catchStart + 400).includes("instance.retire("),
    "the setup catch does not retire the partial namespace",
  );
  // No remote write happens before the instance exists.
  const construction = body.indexOf("new ProductionCanaryNamespace(");
  for (const write of ["this.backend.insert(", "this.backend.createAuthUser("]) {
    const first = body.indexOf(write);
    assert(first > construction, `${write} appears before the instance is constructed`);
  }
});

Deno.test("the retirement count is never inferred from the requested count", async () => {
  const body = code(await source(NAMESPACE));
  const retirement = body.slice(body.indexOf("private async runRetirement"));
  assert(
    !/retired\s*\+=\s*entry\.ids\.length/.test(retirement),
    "retired is being counted from the requested ids rather than the matched ones",
  );
  assert(
    retirement.includes("retired += confirmed.length"),
    "retired is not counted from the ids the server confirmed",
  );
});

Deno.test("an empty id list can never reach an update", async () => {
  const body = code(await source(NAMESPACE));
  const retirement = body.slice(body.indexOf("private async runRetirement"));
  assert(
    retirement.includes("if (entry.ids.length === 0) continue;"),
    "an empty id list is not skipped before the update",
  );
});

Deno.test("both harnesses still retire in a finally block", async () => {
  for (const path of HARNESSES) {
    const body = code(await source(path));
    const finallyIndex = body.indexOf("} finally {");
    assert(finallyIndex > 0, `${path} has no finally block`);
    assert(
      body.slice(finallyIndex, finallyIndex + 400).includes("canary.retire()"),
      `${path} does not retire in its finally block`,
    );
  }
});

Deno.test("the e2e harness tracks every purchase request child row it names", async () => {
  const body = code(await source(HARNESSES[0]));
  for (const table of [
    "stock_opnames", "purchase_requests",
    "purchase_request_lines", "purchase_request_opnames",
  ]) {
    assert(
      body.includes(`canary.trackDocument("${table}"`),
      `the e2e harness does not track ${table}`,
    );
  }
  // The opname link id must be a named variable that is also tracked, not an
  // inline uuid the harness immediately forgets.
  assert(
    !/opname_links:\s*\[\{\s*id:\s*crypto\.randomUUID\(\)/.test(body),
    "the opname link id is generated inline and cannot be tracked",
  );
});

// ---------------------------------------------------------------------------
// Realtime diagnostics, added after the 2026-08-03 production canary failed
// `realtime/a_scope_change_produces_an_invalidation` and recorded nothing an
// operator could act on. The hardening that followed makes the failure
// *legible*; these fences make sure a later edit cannot quietly make it
// *tolerated* instead.
// ---------------------------------------------------------------------------

const REPRO = "tool/realtime_journal_local_repro.ts";

Deno.test("the Realtime verdict is still a positive assertion", async () => {
  const body = code(await source(HARNESSES[0]));
  const check = "a_scope_change_produces_an_invalidation";
  const index = body.indexOf(`record("realtime", "${check}"`);
  assert(index > 0, "the Realtime invalidation check is gone");
  const call = body.slice(index, index + 260);
  // The verdict must still be gated on a frame that actually arrived in time.
  assert(
    call.includes("sawFrame") && call.includes("outcomeIsPass"),
    "the Realtime verdict no longer requires a frame inside the deadline",
  );
  // Nothing may downgrade it to a warning, a skip or an optional expectation.
  for (const softener of ["warn", "optional", "skip", "|| true", "?? true"]) {
    assert(
      !call.toLowerCase().includes(softener),
      `the Realtime verdict has been softened with ${softener}`,
    );
  }
});

Deno.test("the grace window is bounded and cannot rescue a failure", async () => {
  const body = code(await source(HARNESSES[0]));
  assert(/FRAME_GRACE_MS\s*=\s*[0-9_]+;/.test(body), "the grace window is not a constant");
  const grace = Number(
    body.match(/FRAME_GRACE_MS\s*=\s*([0-9_]+)/)![1].replaceAll("_", ""),
  );
  assert(grace > 0 && grace <= 30_000, `grace window ${grace}ms is not bounded`);
  const timeout = Number(
    body.match(/FRAME_TIMEOUT_MS\s*=\s*([0-9_]+)/)![1].replaceAll("_", ""),
  );
  // The deadline the verdict uses must not have been quietly inflated.
  assertEquals(timeout, 20_000, "the frame deadline changed without evidence");
});

Deno.test("no harness retries the Realtime observation without a bound", async () => {
  for (const path of [...HARNESSES, REPRO]) {
    const body = code(await source(path));
    assert(!/while\s*\(\s*true\s*\)/.test(body), `${path} has an unbounded while(true)`);
    assert(!/for\s*\(\s*;\s*;\s*\)/.test(body), `${path} has an unbounded for(;;)`);
    // Every wait loop must close against a deadline rather than a condition
    // the server controls.
    for (const match of body.matchAll(/while\s*\(([^)]*)\)/g)) {
      assert(
        /deadline|< *[a-zA-Z]*[Dd]eadline|performance\.now|Date\.now/.test(match[1]),
        `${path} has a wait loop with no deadline: while (${match[1].trim()})`,
      );
    }
  }
});

Deno.test("the diagnostic probes are reads, and the actor session precedes the subscription", async () => {
  const body = code(await source(HARNESSES[0]));
  // Anchored on code, not on section comments: `code()` strips those, and a
  // fence that depends on a comment is a fence an edit can walk through.
  const start = body.indexOf("const frames:");
  const end = body.indexOf('record("catchup", "subscription_closed"');
  assert(start > 0 && end > start, "the Realtime section could not be located");
  const section = body.slice(start, end);
  // The post-timeout diagnosis may only select.
  for (const forbidden of [".insert(", ".upsert(", ".delete(", ".rpc(\"admin_"]) {
    assert(
      !section.includes(forbidden),
      `the Realtime diagnostics perform ${forbidden}; they must only read`,
    );
  }
  assert(
    section.indexOf("auth.getSession()") < section.indexOf("headA.channel("),
    "the channel is opened before the actor session is confirmed",
  );
  // The subscriber must stay the authenticated actor; a service-role
  // subscription would bypass the very RLS check under test.
  assert(
    !/service\.channel\(/.test(section),
    "the Realtime subscription uses the service role",
  );
});

Deno.test("both harnesses confirm a session before opening a channel", async () => {
  for (const path of HARNESSES) {
    const body = code(await source(path));
    if (!body.includes(".channel(")) continue;
    assert(
      body.includes("auth.getSession()"),
      `${path} opens a channel without confirming the actor session first`,
    );
  }
});

Deno.test("the local reproduction can never point at a managed project", async () => {
  const body = code(await source(REPRO));
  assert(body.includes("assertLocalTarget"), "the local repro has no target guard");
  assert(
    body.includes("127.0.0.1") && body.includes("supabase\\.(co|in|net)"),
    "the local repro guard does not pin loopback and reject managed hosts",
  );
  assert(
    body.includes('AISH_TARGET_ENV") ?? "").toLowerCase() === "production"'),
    "the local repro does not refuse a loaded production contract",
  );
  // It must not carry any production credential name or runner.
  for (const forbidden of [
    "AISH_PRODUCTION_CONFIRM",
    "resolveProductionTarget",
    "AISH_ALLOW_DESTRUCTIVE_CLEANUP",
    ".delete(",
    "deleteUser",
  ]) {
    assert(!body.includes(forbidden), `the local repro references ${forbidden}`);
  }
  // Bounded by construction, so a diagnostic can never become a load generator.
  assert(/Math\.min\(\s*Number\(Deno\.env\.get\("AISH_REPRO_ITERATIONS"\)/.test(body),
    "the local repro's iteration count is not clamped");
});

Deno.test("isolation assertions were not relaxed alongside the Realtime work", async () => {
  const body = code(await source(HARNESSES[0]));
  for (const check of [
    "branch_b_never_sees_branch_as_room",
    "branch_b_never_sees_branch_as_store",
    "branch_b_never_sees_branch_as_document",
    "branch_a_never_sees_branch_bs_room",
    "scope_fingerprints_differ_between_actors",
    "another_actors_device_is_refused",
    "a_client_cannot_write_the_journal",
  ]) {
    assert(body.includes(`"${check}"`), `the isolation check ${check} is gone`);
  }
});

Deno.test("the local gate runner grants the narrowest permissions and no network", async () => {
  const runner = await source("tool/run_production_canary_local_gates.sh");
  const body = runner.split("\n").filter((line) => !line.trimStart().startsWith("#")).join("\n");
  assert(body.includes("set -euo pipefail"), "the runner does not fail closed");
  // The defect this whole runner exists to prevent: the safety suite invoked
  // without the read permission it needs, reporting 0 tests and exiting 0.
  assert(
    body.includes("--allow-read=tool tool/production_canary_safety_test.ts"),
    "the runner does not invoke the safety suite with --allow-read=tool",
  );
  for (const overbroad of ["-A ", "--allow-all", "--allow-net", "--allow-run", "--allow-write", "--allow-sys", "--allow-ffi"]) {
    assert(!body.includes(overbroad), `the runner grants ${overbroad}`);
  }
  // A local gate that sources the production contract is not a local gate.
  for (const forbidden of [".env.production.local", "run_supabase_production", "supabase db push", "supabase migration up"]) {
    assert(!body.includes(forbidden), `the runner references ${forbidden}`);
  }
  // Every suite the gates are supposed to cover has to actually be listed.
  for (const suite of [
    "production_guard_test.ts",
    "production_canary_namespace_test.ts",
    "production_canary_safety_test.ts",
    "realtime_diagnostics_test.ts",
    "readonly_sql_check_test.ts",
    "production_preflight_shell_test.sh",
  ]) {
    assert(body.includes(suite), `the runner does not run ${suite}`);
  }
});

Deno.test("the documented safety-test invocation carries the read permission", async () => {
  // The header comment is what an operator copies. It was the source of the
  // 2026-08-03 miss, so it is fenced like code.
  const header = await source("tool/production_canary_safety_test.ts");
  const documented = header.match(/deno test[^\n]*production_canary_safety_test\.ts/g) ?? [];
  assert(documented.length > 0, "the suite documents no invocation at all");
  for (const line of documented) {
    assert(
      line.includes("--allow-read"),
      `documented invocation lacks --allow-read: ${line}`,
    );
  }
});
