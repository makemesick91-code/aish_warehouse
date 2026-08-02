import { assertEquals } from "jsr:@std/assert@1";
import {
  constantTimeHexEqual,
  declaredUploadSizeAllowed,
  functionHardCeilingBytes,
  importAuditMaxBytes,
  objectSizeBeforeBuffer,
  reportArtifactMaxBytes,
  requireBearer,
} from "./_shared/upload_validation.ts";

Deno.test("constant-time comparator accepts only exact hashes", () => {
  assertEquals(constantTimeHexEqual("aa", "aa"), true);
  assertEquals(constantTimeHexEqual("aa", "ab"), false);
  assertEquals(constantTimeHexEqual("aa", "aaa"), false);
});

Deno.test("import audit accepts exactly 10 MiB and rejects one byte more", () => {
  assertEquals(
    declaredUploadSizeAllowed("import_audit", importAuditMaxBytes),
    true,
  );
  assertEquals(
    declaredUploadSizeAllowed("import_audit", importAuditMaxBytes + 1),
    false,
  );
});

Deno.test("report artifacts use their independent documented limit", () => {
  assertEquals(
    declaredUploadSizeAllowed("report_artifact", reportArtifactMaxBytes),
    true,
  );
  assertEquals(
    declaredUploadSizeAllowed("report_artifact", reportArtifactMaxBytes + 1),
    false,
  );
});

Deno.test("objects above 20 MiB are detectable before full-memory processing", () => {
  assertEquals(functionHardCeilingBytes, 20 * 1024 * 1024);
  assertEquals(objectSizeBeforeBuffer(functionHardCeilingBytes + 1), 20971521);
  assertEquals(objectSizeBeforeBuffer("20971521"), null);
});

Deno.test("bearer parser fails closed", () => {
  assertEquals(requireBearer(new Request("http://local")), null);
  assertEquals(
    requireBearer(
      new Request("http://local", { headers: { authorization: "x" } }),
    ),
    null,
  );
});
