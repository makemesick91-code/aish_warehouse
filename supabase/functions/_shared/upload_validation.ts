export const allowedBuckets = new Set(["import-audit", "report-artifacts"]);

export const mebibyte = 1024 * 1024;
export const importAuditMaxBytes = 10 * mebibyte;
// A report has its own policy even though its current value equals the global
// Function ceiling. It must not inherit a future import-policy change.
export const reportArtifactMaxBytes = 20 * mebibyte;
export const functionHardCeilingBytes = 20 * mebibyte;

export function uploadLimitForEntity(entityType: unknown): number | null {
  if (entityType === "import_audit") return importAuditMaxBytes;
  if (entityType === "report_artifact") return reportArtifactMaxBytes;
  return null;
}

export function declaredUploadSizeAllowed(
  entityType: unknown,
  sizeBytes: unknown,
): boolean {
  const limit = uploadLimitForEntity(entityType);
  return limit !== null && Number.isSafeInteger(sizeBytes) &&
    (sizeBytes as number) > 0 &&
    (sizeBytes as number) <= limit &&
    (sizeBytes as number) <= functionHardCeilingBytes;
}

export function objectSizeBeforeBuffer(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    return null;
  }
  return value;
}

export function safeError(code: string, status = 400): Response {
  return Response.json({ code, message: "Upload tidak dapat diproses." }, {
    status,
  });
}

const stableCodes = new Set([
  "sync_auth_required",
  "sync_identity_unlinked",
  "sync_user_inactive",
  "sync_access_denied",
  "sync_invalid_payload",
  "sync_request_id_reused",
  "sync_dependency_missing",
  "sync_upload_not_authorized",
  "sync_upload_expired",
  "sync_upload_hash_mismatch",
  "sync_upload_size_mismatch",
  "sync_upload_object_missing",
  "sync_upload_too_large",
  "sync_retry_later",
]);

export function stableServerCode(value: unknown): string {
  if (typeof value === "string" && stableCodes.has(value)) return value;
  return "sync_invalid_payload";
}

export function requireBearer(request: Request): string | null {
  const value = request.headers.get("authorization") ?? "";
  return value.startsWith("Bearer ") && value.length > 20 ? value : null;
}

export function constantTimeHexEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}
