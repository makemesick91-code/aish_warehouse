import { createClient } from "npm:@supabase/supabase-js@2";
import {
  allowedBuckets,
  declaredUploadSizeAllowed,
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
    if (
      !declaredUploadSizeAllowed(
        input?.entity_type,
        input?.expected_size_bytes,
      )
    ) {
      return safeError("sync_upload_too_large", 413);
    }
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authorization } },
    });
    const { data, error } = await userClient.rpc(
      "create_file_upload_intent",
      input,
    );
    if (error || !Array.isArray(data) || data.length !== 1) {
      return safeError(stableServerCode(error?.message), 400);
    }
    const intent = data[0];
    if (!allowedBuckets.has(intent.bucket_id)) {
      return safeError("sync_upload_not_authorized", 403);
    }
    if (intent.intent_status === "finalized" && intent.remote_object_id) {
      return Response.json({
        intent_id: intent.intent_id,
        bucket_id: intent.bucket_id,
        object_key: intent.object_key,
        expires_at: intent.expires_at,
        already_finalized: true,
        object_id: intent.remote_object_id,
      });
    }
    const serviceClient = createClient(url, service, {
      auth: { persistSession: false },
    });
    const signed = await serviceClient.storage.from(intent.bucket_id)
      .createSignedUploadUrl(intent.object_key);
    if (signed.error) return safeError("sync_retry_later", 503);
    return Response.json({
      intent_id: intent.intent_id,
      bucket_id: intent.bucket_id,
      object_key: intent.object_key,
      expires_at: intent.expires_at,
      token: signed.data.token,
    });
  } catch (_) {
    return safeError("sync_invalid_payload", 400);
  }
});
