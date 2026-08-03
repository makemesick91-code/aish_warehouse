// Canonical push envelope construction, shared by the staging harnesses.
//
// Lifted verbatim in behaviour from `tool/supabase_12b_e2e.ts` so the staging
// runners exercise the same wire contract the local ones do. Keeping it in one
// place is what stops the staging suite from quietly drifting into a weaker
// version of the local one.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { retryTransient } from "./staging_guard.ts";

export function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0)
        .map(([key, entry]) => [key, canonical(entry)]),
    );
  }
  return value;
}

export async function sha256Text(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(canonical(value)));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest).map((part) => part.toString(16).padStart(2, "0"))
    .join("");
}

export async function envelope(
  input: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  return { ...input, payload_hash: await sha256Text(input) };
}

export type PushOutcome = {
  outcome: "accepted" | "replayed" | "conflict";
  final_document_number?: string;
  conflict_code?: string;
};

/// Pushes an envelope. Transport faults are retried; a server decision is not.
///
/// This is the whole reason `request_id` exists: a retry re-sends the *same*
/// envelope, so the server recognises it and answers `replayed` instead of
/// performing the operation twice. A harness that generated a fresh request id
/// on retry would be creating a second business operation and calling it a
/// retry, which is the failure mode this contract was built to make impossible.
export async function push(
  client: SupabaseClient,
  operationEnvelope: Record<string, unknown>,
  label: string,
): Promise<PushOutcome> {
  return await retryTransient(label, async () => {
    const result = await client.rpc("push_sync_operation", {
      operation_envelope: operationEnvelope,
    });
    if (result.error) throw result.error;
    return result.data as PushOutcome;
  });
}

export type PullPage = {
  changes: Array<{
    change_seq: number;
    entity_type: string;
    entity_id: string;
    operation: "upsert" | "tombstone";
    server_version: number;
    payload: Record<string, unknown> | null;
    field_versions: Record<string, number>;
  }>;
  next_cursor: number;
  has_more: boolean;
  scope_fingerprint: string;
  server_horizon: number;
};

export async function pull(
  client: SupabaseClient,
  device: string,
  cursor: number,
  limit = 200,
  entityTypes?: string[],
): Promise<PullPage> {
  return await retryTransient(`pull_${cursor}`, async () => {
    const result = await client.rpc("pull_sync_changes", {
      after_cursor: cursor,
      batch_limit: limit,
      device_id: device,
      ...(entityTypes ? { entity_types: entityTypes } : {}),
    });
    if (result.error) throw result.error;
    return result.data as PullPage;
  });
}

/// Drains the feed the way the Flutter worker does: page after page from the
/// durable cursor until the server says there is no more.
export async function drain(
  client: SupabaseClient,
  device: string,
  from: number,
  limit = 200,
  entityTypes?: string[],
): Promise<{ changes: PullPage["changes"]; cursor: number; pages: number }> {
  let cursor = from;
  let pages = 0;
  const changes: PullPage["changes"] = [];
  for (;;) {
    const page = await pull(client, device, cursor, limit, entityTypes);
    changes.push(...page.changes);
    cursor = page.next_cursor;
    pages += 1;
    if (!page.has_more) return { changes, cursor, pages };
    if (pages >= 500) throw new Error("drain_did_not_terminate");
  }
}
