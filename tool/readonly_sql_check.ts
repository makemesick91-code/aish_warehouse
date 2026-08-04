// Proves that an operator SQL file can only read.
//
// The two production verification files under `artifacts/production/` are meant
// to be pasted into the Supabase SQL Editor against the live project while the
// rollout is on HOLD. "I read it and it looked like SELECTs" is not a control.
// This is: every statement is parsed to its leading keyword, and anything that
// is not a read is a refusal.
//
// Comments are stripped first, so the word DELETE in an explanation cannot fail
// the file — and, more importantly, a mutation cannot hide behind a comment
// marker either, because stripping is done before classification rather than
// by ignoring lines that merely contain `--`.
//
// Run with:
//   deno run --allow-read=artifacts,tool tool/readonly_sql_check.ts <file>...
//
// Exit code: 0 when every file is read-only, 1 otherwise.

/// Statement verbs that read and nothing else. Anything absent from this list
/// is rejected, so a verb nobody thought about fails closed rather than passing
/// unnoticed.
const READ_ONLY_VERBS = new Set(["SELECT", "WITH", "TABLE", "VALUES", "SHOW", "EXPLAIN"]);

/// Verbs that must never appear, listed explicitly so the failure message can
/// name what was found instead of saying "unrecognised".
const FORBIDDEN_VERBS = [
  "INSERT", "UPDATE", "DELETE", "TRUNCATE", "ALTER", "DROP", "CREATE",
  "GRANT", "REVOKE", "COMMENT", "REFRESH", "REINDEX", "VACUUM", "CLUSTER",
  "COPY", "MERGE", "CALL", "DO", "SET", "RESET", "LOCK", "SECURITY",
  "IMPORT", "REASSIGN", "BEGIN", "COMMIT",
];

export function stripSqlComments(sql: string): string {
  let out = "";
  let i = 0;
  let inLine = false;
  let inBlock = 0;
  let inSingle = false;
  let inDouble = false;
  while (i < sql.length) {
    const two = sql.slice(i, i + 2);
    if (inLine) {
      if (sql[i] === "\n") { inLine = false; out += "\n"; }
      i += 1;
      continue;
    }
    if (inBlock > 0) {
      if (two === "*/") { inBlock -= 1; i += 2; continue; }
      if (two === "/*") { inBlock += 1; i += 2; continue; }
      i += 1;
      continue;
    }
    if (!inSingle && !inDouble && two === "--") { inLine = true; i += 2; continue; }
    if (!inSingle && !inDouble && two === "/*") { inBlock = 1; i += 2; continue; }
    if (!inDouble && sql[i] === "'") inSingle = !inSingle;
    else if (!inSingle && sql[i] === '"') inDouble = !inDouble;
    out += sql[i];
    i += 1;
  }
  return out;
}

/// Splits on semicolons that are not inside a string literal or an identifier.
export function splitStatements(sql: string): string[] {
  const statements: string[] = [];
  let current = "";
  let inSingle = false;
  let inDouble = false;
  for (const char of sql) {
    if (!inDouble && char === "'") inSingle = !inSingle;
    else if (!inSingle && char === '"') inDouble = !inDouble;
    if (char === ";" && !inSingle && !inDouble) {
      if (current.trim()) statements.push(current.trim());
      current = "";
      continue;
    }
    current += char;
  }
  if (current.trim()) statements.push(current.trim());
  return statements;
}

export type Violation = { statement: string; verb: string; reason: string };

export function findViolations(sql: string): Violation[] {
  const violations: Violation[] = [];
  for (const statement of splitStatements(stripSqlComments(sql))) {
    // psql meta-commands (\set, \echo) are client-side and touch no data.
    if (statement.startsWith("\\")) continue;
    const verb = (statement.match(/^[A-Za-z]+/)?.[0] ?? "").toUpperCase();
    if (READ_ONLY_VERBS.has(verb)) {
      // A CTE may still hide a write: WITH x AS (DELETE ... RETURNING ...).
      const body = statement.toUpperCase();
      for (const forbidden of ["INSERT INTO", "UPDATE ", "DELETE FROM", "TRUNCATE ", "MERGE INTO"]) {
        if (new RegExp(`\\(\\s*${forbidden.trim()}`).test(body.replaceAll(/\s+/g, " "))) {
          violations.push({
            statement: statement.slice(0, 120),
            verb: forbidden.trim(),
            reason: "a data-modifying statement inside a CTE",
          });
        }
      }
      continue;
    }
    violations.push({
      statement: statement.slice(0, 120),
      verb: verb || "<empty>",
      reason: FORBIDDEN_VERBS.includes(verb)
        ? "a data- or schema-modifying statement"
        : "an unrecognised leading keyword; this checker fails closed",
    });
  }
  return violations;
}

if (import.meta.main) {
  const files = Deno.args;
  if (files.length === 0) {
    console.error("usage: readonly_sql_check.ts <file.sql>...");
    Deno.exit(2);
  }
  let bad = 0;
  for (const file of files) {
    const violations = findViolations(await Deno.readTextFile(file));
    if (violations.length === 0) {
      console.log(`READ-ONLY  ${file}`);
      continue;
    }
    bad += 1;
    console.error(`NOT READ-ONLY  ${file}`);
    for (const violation of violations) {
      console.error(`  ${violation.verb}: ${violation.reason}\n    ${violation.statement}`);
    }
  }
  Deno.exit(bad === 0 ? 0 : 1);
}
