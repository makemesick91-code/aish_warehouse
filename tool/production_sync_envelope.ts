// Canonical push/pull envelope construction for the production canary.
//
// Behaviourally identical to `staging_sync_envelope.ts` — that is the point: the
// canary must exercise the same wire contract the staging suite and the Flutter
// client do, or it is not testing the thing that will ship. It is a separate
// file rather than a shared one because the staging module retries through
// `staging_guard.ts`, and a production tool must never reach into the staging
// guard's state (its secret registry, its refusals) even indirectly.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { retryTransient } from "./production_guard.ts";

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
  return Array.from(digest).map((part) => part.toString(16).padStart(2, "0")).join("");
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
/// retry — which on production would be a duplicate document, not a test
/// failure.
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
///
/// `maxPages` is mandatory here, unlike the staging version's fixed ceiling. A
/// production feed is as long as production is old, and the caller has to decide
/// how much of the maintenance window a drain is allowed to spend.
export async function drain(
  client: SupabaseClient,
  device: string,
  from: number,
  limit: number,
  maxPages: number,
  entityTypes?: string[],
): Promise<{
  changes: PullPage["changes"];
  cursor: number;
  pages: number;
  truncated: boolean;
}> {
  let cursor = from;
  let pages = 0;
  const changes: PullPage["changes"] = [];
  for (;;) {
    const page = await pull(client, device, cursor, limit, entityTypes);
    changes.push(...page.changes);
    cursor = page.next_cursor;
    pages += 1;
    if (!page.has_more) return { changes, cursor, pages, truncated: false };
    if (pages >= maxPages) return { changes, cursor, pages, truncated: true };
  }
}
