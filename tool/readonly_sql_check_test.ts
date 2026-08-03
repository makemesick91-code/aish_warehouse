// Tests for the read-only SQL checker.
//
// The checker is a control, not a convenience: it is what stands between an
// operator pasting a file into the production SQL Editor while the rollout is
// on HOLD and that file turning out to contain a write. A control nobody tests
// is a control nobody has.
//
// Run with:
//   deno test tool/readonly_sql_check_test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  findViolations,
  splitStatements,
  stripSqlComments,
} from "./readonly_sql_check.ts";

Deno.test("plain selects pass", () => {
  assertEquals(findViolations("select 1; select * from public.branches;"), []);
});

Deno.test("a CTE that only reads passes", () => {
  const sql = "with x as (select id from public.rooms) select count(*) from x;";
  assertEquals(findViolations(sql), []);
});

Deno.test("every mutating verb is refused", () => {
  for (
    const sql of [
      "insert into public.rooms (id) values (gen_random_uuid());",
      "update public.rooms set name = 'x';",
      "delete from public.rooms;",
      "truncate public.rooms;",
      "alter table public.rooms add column x int;",
      "drop table public.rooms;",
      "grant select on public.rooms to anon;",
      "revoke select on public.rooms from anon;",
      "create index on public.rooms (name);",
      "do $$ begin perform 1; end $$;",
      "call some_procedure();",
    ]
  ) {
    const violations = findViolations(sql);
    assert(violations.length > 0, `not refused: ${sql}`);
  }
});

Deno.test("a write hidden inside a CTE is refused", () => {
  // The shape that looks like a SELECT and is not.
  const sql = "with gone as (delete from public.rooms returning id) select count(*) from gone;";
  const violations = findViolations(sql);
  assert(violations.length > 0, "a data-modifying CTE slipped through");
  assertEquals(violations[0].verb, "DELETE FROM");
});

Deno.test("an unrecognised verb fails closed", () => {
  const violations = findViolations("frobnicate the_database;");
  assertEquals(violations.length, 1);
  assert(violations[0].reason.includes("fails closed"));
});

Deno.test("the word DELETE in a comment does not fail the file", () => {
  const sql = `
    -- This query proves nothing was deleted; no DELETE runs here.
    /* Not even an UPDATE. */
    select count(*) from public.rooms;
  `;
  assertEquals(findViolations(sql), []);
});

Deno.test("a statement cannot hide behind a comment marker", () => {
  // Stripping happens before classification, so the delete is still seen.
  const sql = "select 1; /* harmless */ delete from public.rooms;";
  assert(findViolations(sql).length > 0);
});

Deno.test("semicolons inside string literals do not split statements", () => {
  const sql = "select 'a;b' as x, \"weird;column\" from t;";
  assertEquals(splitStatements(stripSqlComments(sql)).length, 1);
  assertEquals(findViolations(sql), []);
});

Deno.test("psql meta-commands are ignored", () => {
  assertEquals(findViolations("\\set ns 'abc'\nselect 1;"), []);
});

Deno.test("the shipped production audit files are read-only", async () => {
  // The whole point. If either file ever gains a write, this fails in the local
  // gates rather than in production.
  for (
    const file of [
      "artifacts/production/read-only-retirement-verification-8193560.sql",
      "artifacts/production/read-only-realtime-audit-8193560.sql",
    ]
  ) {
    let sql: string;
    try {
      sql = await Deno.readTextFile(new URL(`../${file}`, import.meta.url));
    } catch {
      // `artifacts/` is git-ignored, so a fresh clone will not have these.
      // Skipping is correct there; failing would make the gate lie about a
      // file that is genuinely absent.
      continue;
    }
    assertEquals(findViolations(sql), [], `${file} is not read-only`);
  }
});
