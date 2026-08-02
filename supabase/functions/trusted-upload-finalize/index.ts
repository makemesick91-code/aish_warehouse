import { createClient } from "npm:@supabase/supabase-js@2";
import {
  declaredUploadSizeAllowed,
  functionHardCeilingBytes,
  objectSizeBeforeBuffer,
  requireBearer,
  safeError,
  stableServerCode,
} from "../_shared/upload_validation.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") return safeError("method_not_allowed", 405);
  const authorization = requireBearer(request);
  if (!authorization) return safeError("sync_auth_required", 401);
  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return safeError("sync_retry_later", 503);
  try {
    const input = await request.json();
    const client = createClient(url, anon, {
      global: { headers: { Authorization: authorization } },
    });
    const intentResult = await client.from("file_upload_intents")
      .select(
        "id,bucket_id,object_key,entity_type,mime_type,expected_sha256,expected_size_bytes",
      )
      .eq("id", input.intent_id).single();
    if (intentResult.error || !intentResult.data) {
      return safeError("sync_upload_not_authorized", 403);
    }
    const serviceClient = createClient(url, service, {
      auth: { persistSession: false },
    });
    if (
      !declaredUploadSizeAllowed(
        intentResult.data.entity_type,
        intentResult.data.expected_size_bytes,
      )
    ) {
      return safeError("sync_upload_too_large", 413);
    }
    const keyParts = intentResult.data.object_key.split("/");
    const objectName = keyParts.pop() ?? "";
    const folder = keyParts.join("/");
    const listed = await serviceClient.storage.from(intentResult.data.bucket_id)
      .list(folder, { search: objectName, limit: 2 });
    const object = listed.data?.find((candidate) =>
      candidate.name === objectName
    );
    if (listed.error || !object) {
      return safeError("sync_upload_object_missing", 404);
    }
    const metadata = object.metadata as Record<string, unknown> | null;
    const listedSize = objectSizeBeforeBuffer(metadata?.size);
    if (listedSize === null) {
      return safeError("sync_upload_size_mismatch", 400);
    }
    if (
      listedSize > functionHardCeilingBytes ||
      listedSize !== intentResult.data.expected_size_bytes
    ) {
      await serviceClient.storage.from(intentResult.data.bucket_id)
        .remove([intentResult.data.object_key]);
      return safeError(
        listedSize > functionHardCeilingBytes
          ? "sync_upload_too_large"
          : "sync_upload_size_mismatch",
        listedSize > functionHardCeilingBytes ? 413 : 400,
      );
    }
    const downloaded = await serviceClient.storage.from(
      intentResult.data.bucket_id,
    )
      .download(intentResult.data.object_key);
    if (downloaded.error || !downloaded.data) {
      return safeError("sync_upload_object_missing", 404);
    }
    // Blob.size is available without copying the payload into an ArrayBuffer.
    // This is the second hard-ceiling guard in case Storage metadata changed
    // between list and download.
    if (downloaded.data.size > functionHardCeilingBytes) {
      await serviceClient.storage.from(intentResult.data.bucket_id)
        .remove([intentResult.data.object_key]);
      return safeError("sync_upload_too_large", 413);
    }
    const bytes = await downloaded.data.arrayBuffer();
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    const hash = Array.from(digest).map((value) =>
      value.toString(16).padStart(2, "0")
    ).join("");
    const actualMime = typeof metadata?.mimetype === "string"
      ? metadata.mimetype
      : "";
    if (
      bytes.byteLength !== intentResult.data.expected_size_bytes ||
      hash !== intentResult.data.expected_sha256
    ) {
      // A failed integrity check must not leave an untrusted object behind. Removal
      // is deliberately best-effort; the database intent remains unfinalized and
      // cannot be referenced as a trusted remote file.
      await serviceClient.storage.from(intentResult.data.bucket_id)
        .remove([intentResult.data.object_key]);
      return safeError(
        bytes.byteLength !== intentResult.data.expected_size_bytes
          ? "sync_upload_size_mismatch"
          : "sync_upload_hash_mismatch",
        400,
      );
    }
    const result = await client.rpc("finalize_file_upload", {
      intent_id: input.intent_id,
      actual_sha256: hash,
      actual_size_bytes: bytes.byteLength,
      actual_mime_type: actualMime,
    });
    if (result.error) {
      return safeError(stableServerCode(result.error.message), 400);
    }
    return Response.json({ object_id: result.data });
  } catch (_) {
    return safeError("sync_invalid_payload", 400);
  }
});
