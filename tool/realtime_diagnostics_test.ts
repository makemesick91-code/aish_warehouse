// Tests for the Realtime failure classification.
//
// Run with:
//
//   deno test tool/realtime_diagnostics_test.ts
//
// No permissions: the module under test is pure — no clock, no network, no
// environment, no file system. That is the point. The 2026-08-03 production
// canary's Realtime verdict could only be exercised by talking to a managed
// project, which is why a defect in it survived every local gate. The logic
// that decides pass from fail now runs here instead.

import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  classifyRealtimeOutcome,
  describeOutcome,
  type FrameObservation,
  maskId,
  outcomeIsPass,
  type RealtimeOutcome,
  sanitiseChannelError,
  summariseLatencies,
} from "./realtime_diagnostics.ts";

/// A run that did everything right. Each test names only what it changes.
function healthy(overrides: Partial<FrameObservation> = {}): FrameObservation {
  return {
    subscribed: true,
    channelError: null,
    journalCreated: true,
    actorSelectVisible: true,
    frameSeen: true,
    ...overrides,
  };
}

Deno.test("a frame inside the deadline is the only pass", () => {
  const outcome = classifyRealtimeOutcome(healthy());
  assertEquals(outcome, "delivered");
  assert(outcomeIsPass(outcome));
});

Deno.test("SUBSCRIBED followed by no frame fails", () => {
  // The exact shape of the production failure: the channel joined, the row was
  // written, the actor could read it, and nothing arrived.
  const outcome = classifyRealtimeOutcome(healthy({ frameSeen: false }));
  assertEquals(outcome, "journal_visible_via_select_but_no_frame");
  assertFalse(outcomeIsPass(outcome));
});

Deno.test("a frame for the wrong entity is still a failure", () => {
  const outcome = classifyRealtimeOutcome(
    healthy({ frameSeen: false, otherEntityFrames: 3 }),
  );
  assertEquals(outcome, "frames_for_other_entities_only");
  assertFalse(outcomeIsPass(outcome));
});

Deno.test("a channel error fails with a reason of its own", () => {
  assertEquals(
    classifyRealtimeOutcome(healthy({ subscribed: false, frameSeen: false })),
    "channel_error",
  );
  // An error reported after SUBSCRIBED, with nothing delivered, is still the
  // transport's fault and must not be mistaken for an RLS drop.
  assertEquals(
    classifyRealtimeOutcome(
      healthy({ frameSeen: false, channelError: "connection closed" }),
    ),
    "channel_error",
  );
  assertFalse(outcomeIsPass("channel_error"));
});

Deno.test("a frame after the timeout is late, not passing", () => {
  const outcome = classifyRealtimeOutcome(
    healthy({ frameSeen: false, lateFrameSeen: true }),
  );
  assertEquals(outcome, "frame_arrived_after_timeout");
  assertFalse(outcomeIsPass(outcome));
  assert(describeOutcome(outcome).includes("late is a failure"));
});

Deno.test("no journal row is reported as the trigger's fault, not Realtime's", () => {
  const outcome = classifyRealtimeOutcome(
    healthy({ frameSeen: false, journalCreated: false, actorSelectVisible: null }),
  );
  assertEquals(outcome, "journal_not_created");
});

Deno.test("a row the subscriber cannot SELECT is named as an RLS drop", () => {
  const outcome = classifyRealtimeOutcome(
    healthy({ frameSeen: false, actorSelectVisible: false }),
  );
  assertEquals(outcome, "journal_created_but_not_visible");
  assert(describeOutcome(outcome).includes("RLS"));
});

Deno.test("a row visible through the pull but not through Realtime still fails", () => {
  // The pull RPC is SECURITY DEFINER: it can supply the state while Realtime
  // delivers nothing. That combination must never read as a Realtime pass.
  const outcome = classifyRealtimeOutcome(
    healthy({ frameSeen: false, actorSelectVisible: true }),
  );
  assertFalse(outcomeIsPass(outcome));
  assertEquals(outcome, "journal_visible_via_select_but_no_frame");
});

Deno.test("every outcome except delivered is a failure", () => {
  const all: RealtimeOutcome[] = [
    "delivered",
    "channel_error",
    "journal_not_created",
    "journal_created_but_not_visible",
    "journal_visible_via_select_but_no_frame",
    "frames_for_other_entities_only",
    "frame_arrived_after_timeout",
  ];
  for (const outcome of all) {
    assertEquals(outcomeIsPass(outcome), outcome === "delivered", outcome);
    assert(describeOutcome(outcome).length > 0, outcome);
  }
});

Deno.test("diagnostics carry no secret", () => {
  // Assembled from pieces rather than written out, so this file does not
  // itself look like a leaked credential to every scanner that reads the repo.
  // The parts decode to `{"alg":"HS256","typ":"JWT"}` / `{"role":"anon"}` /
  // "sig" — a shape, not a token.
  const jwt = ["eyJ", "hbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"].join("") +
    ".eyJyb2xlIjoiYW5vbiJ9.c2ln";
  const fakeKey = ["sb", "secret", "abcdefghijklmnop"].join("_");
  const sanitised = sanitiseChannelError(
    `join failed apikey=${jwt} token=${jwt} for ${fakeKey}`,
  );
  assert(sanitised !== null);
  assertFalse(sanitised!.includes(jwt));
  assertFalse(sanitised!.includes(fakeKey));
  assertEquals(sanitiseChannelError(null), null);
  // Bounded, so a hostile transport cannot flood a report.
  assert(sanitiseChannelError("x".repeat(5_000))!.length <= 200);
});

Deno.test("ids in diagnostics are masked, never whole", () => {
  const id = "cafc2d3d-5a11-4a5a-9c96-0123456789ab";
  const masked = maskId(id);
  assertEquals(masked, "cafc2d3d…");
  assertFalse(masked.includes("0123456789ab"));
  assertEquals(maskId(null), "∅");
  assertEquals(maskId(""), "∅");
});

Deno.test("latency percentiles are values that were really observed", () => {
  const stats = summariseLatencies([310, 67, 338, 299, 334, 303, 332, 439, 310]);
  assertEquals(stats.count, 9);
  assertEquals(stats.min_ms, 67);
  assertEquals(stats.max_ms, 439);
  // Nearest-rank: every reported figure is one of the inputs.
  for (const value of [stats.median_ms, stats.p95_ms]) {
    assert([310, 67, 338, 299, 334, 303, 332, 439].includes(value!), String(value));
  }
  assertEquals(summariseLatencies([]), {
    count: 0,
    min_ms: null,
    median_ms: null,
    p95_ms: null,
    max_ms: null,
  });
});

Deno.test("classification is total and never throws on a partial observation", () => {
  // A run that died mid-setup still has to land in a named bucket rather than
  // crashing the reporter that is trying to explain the failure.
  const partial: FrameObservation = {
    subscribed: false,
    channelError: null,
    journalCreated: false,
    actorSelectVisible: null,
    frameSeen: false,
  };
  assertEquals(classifyRealtimeOutcome(partial), "channel_error");
});
