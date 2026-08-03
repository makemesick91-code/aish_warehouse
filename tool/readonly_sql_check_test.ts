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
  // These SQL files are tracked release evidence. A missing file is a failed
  // gate, not a condition that may be skipped.
  const shippedFiles = [
    "tool/sql/verify_production_canary_retirement_readonly.sql",
    "tool/sql/audit_production_realtime_readonly.sql",
  ];

  for (const file of shippedFiles) {
    const url = new URL(`../${file}`, import.meta.url);
    const stat = await Deno.stat(url);

    assertEquals(
      stat.isFile,
      true,
      `${file} is missing or is not a regular file`,
    );

    const sql = await Deno.readTextFile(url);
    assertEquals(findViolations(sql), [], `${file} is not read-only`);
  }
});
