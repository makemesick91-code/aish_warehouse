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
//   deno test --allow-read tool/production_canary_safety_test.ts

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
