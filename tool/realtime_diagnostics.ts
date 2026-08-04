// Realtime failure classification, shared by the production canary and the
// local reproduction harness.
//
// The 2026-08-03 production canary recorded `realtime/
// a_scope_change_produces_an_invalidation` as a bare `false` with an empty
// detail string. That single boolean collapses at least six distinct failures
// into one, and the operator holding the report could not tell which had
// happened without going back to the database:
//
//   * the channel never joined, or errored after joining;
//   * the mutation never produced a journal row at all;
//   * the row exists but the subscriber cannot SELECT it under RLS — which is
//     exactly the check Realtime's `walrus` performs per subscriber, and
//     exactly the check nothing else in the canary exercises, because the pull
//     RPC is SECURITY DEFINER and bypasses the journal policy;
//   * the row is readable by the subscriber but no frame was delivered;
//   * frames arrived, but for other entities;
//   * the frame arrived, only after the deadline.
//
// Everything here is pure: no clock, no network, no environment. That is what
// lets the classification be tested without a remote project, which is the
// property the incident showed was missing.
//
// Classifying a failure more precisely is not the same as excusing it. Every
// outcome other than `delivered` is a failure, `frame_arrived_after_timeout`
// included.

export type RealtimeOutcome =
  | "delivered"
  | "channel_error"
  | "journal_not_created"
  | "journal_created_but_not_visible"
  | "journal_visible_via_select_but_no_frame"
  | "frames_for_other_entities_only"
  | "frame_arrived_after_timeout";

export type FrameObservation = {
  /// The channel reached SUBSCRIBED.
  subscribed: boolean;
  /// A sanitised channel error, if the transport reported one at any point.
  channelError: string | null;
  /// A journal row for the mutated entity exists, observed with service role.
  journalCreated: boolean;
  /// The subscribing actor can SELECT that journal row under RLS. `null` when
  /// the probe was not run (there was no row to probe for).
  actorSelectVisible: boolean | null;
  /// A frame naming the mutated entity arrived within the deadline.
  frameSeen: boolean;
  /// A frame naming the mutated entity arrived only after the deadline.
  lateFrameSeen?: boolean;
  /// Frames that arrived naming some other entity.
  otherEntityFrames?: number;
};

/// The order is the diagnosis. A later branch may only be reached when every
/// earlier one has been ruled out, so the name a run receives is the most
/// specific true statement about it, not the first plausible one.
export function classifyRealtimeOutcome(
  observation: FrameObservation,
): RealtimeOutcome {
  if (!observation.subscribed) return "channel_error";
  if (observation.frameSeen) return "delivered";
  if (observation.lateFrameSeen) return "frame_arrived_after_timeout";
  if (!observation.journalCreated) return "journal_not_created";
  if (observation.channelError) return "channel_error";
  if (observation.actorSelectVisible === false) {
    return "journal_created_but_not_visible";
  }
  if ((observation.otherEntityFrames ?? 0) > 0) {
    return "frames_for_other_entities_only";
  }
  return "journal_visible_via_select_but_no_frame";
}

/// `delivered` is the only pass. Stated as a function so no caller can quietly
/// decide that a late frame, or a frame for the wrong entity, is close enough.
export function outcomeIsPass(outcome: RealtimeOutcome): boolean {
  return outcome === "delivered";
}

/// One line an operator can act on, without having to hold the taxonomy in
/// their head. Never interpolates a credential: the inputs are counts, booleans
/// and already-masked ids.
export function describeOutcome(outcome: RealtimeOutcome): string {
  switch (outcome) {
    case "delivered":
      return "a frame for the mutated entity arrived within the deadline";
    case "channel_error":
      return "the channel never joined, or reported an error";
    case "journal_not_created":
      return "no journal row was written for the mutation — the trigger, not Realtime, is the suspect";
    case "journal_created_but_not_visible":
      return "the journal row exists but the subscriber cannot SELECT it under RLS — Realtime evaluates the same policy per subscriber and would drop the frame for the same reason";
    case "journal_visible_via_select_but_no_frame":
      return "the journal row exists and the subscriber can read it, yet no frame arrived — publication, replication or the Realtime service, not RLS";
    case "frames_for_other_entities_only":
      return "frames arrived, but none named the mutated entity";
    case "frame_arrived_after_timeout":
      return "the frame arrived only after the deadline — late is a failure, not a pass";
  }
}

/// Identifiers in a report are for correlation, not for reconstruction. Eight
/// hex characters is enough to line a frame up against a fixture and not enough
/// to be a handle on a row.
export function maskId(value: string | null | undefined): string {
  if (!value) return "∅";
  return value.length <= 8 ? value : `${value.slice(0, 8)}…`;
}

/// Channel errors come from a transport the harness does not control, so they
/// are truncated and stripped of anything shaped like a bearer token before
/// they reach a report that gets pasted into an issue.
export function sanitiseChannelError(error: unknown): string | null {
  if (error === null || error === undefined) return null;
  const text = error instanceof Error ? error.message : String(error);
  const stripped = text
    .replace(/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "<jwt>")
    .replace(/sb_(secret|publishable)_[A-Za-z0-9_-]+/g, "<key>")
    .replace(/(apikey|access_token|token|password)=[^&\s]+/gi, "$1=<redacted>");
  return stripped.slice(0, 200);
}

export type LatencySummary = {
  count: number;
  min_ms: number | null;
  median_ms: number | null;
  p95_ms: number | null;
  max_ms: number | null;
};

/// Nearest-rank percentile. With ten samples an interpolating p95 invents a
/// number that no run actually produced; nearest-rank returns a latency that
/// was really observed, which is the only kind worth putting in an incident
/// record.
export function summariseLatencies(values: number[]): LatencySummary {
  if (values.length === 0) {
    return { count: 0, min_ms: null, median_ms: null, p95_ms: null, max_ms: null };
  }
  const sorted = [...values].sort((a, b) => a - b);
  const rank = (fraction: number) =>
    sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil(fraction * sorted.length) - 1))];
  return {
    count: sorted.length,
    min_ms: sorted[0],
    median_ms: rank(0.5),
    p95_ms: rank(0.95),
    max_ms: sorted[sorted.length - 1],
  };
}
