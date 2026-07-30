import 'failures.dart';

/// Turns a thrown object into a sentence a clinic user can act on.
///
/// Business failures already carry an Indonesian message written for the person
/// on the other side of the screen. Anything else — a database error, a bug —
/// becomes one generic sentence, because a raw exception string or a stack
/// trace tells a nurse nothing and leaks internals.
String describeFailure(Object error) {
  if (error is AppFailure) return error.message;
  // A caller-supplied fallback sentence, e.g. `describeFailure(error ?? 'Gagal
  // mengirim')`. Without this branch the fallback would be swallowed and the
  // user would always get the generic sentence below.
  if (error is String) return error;
  if (error is StateError) {
    return 'Sesi pengguna tidak tersedia. Muat ulang aplikasi lalu coba lagi.';
  }
  return 'Terjadi kesalahan tak terduga. Silakan coba lagi.';
}

/// The single sentence every refused route shows, whichever module refused it.
///
/// One message for every reason on purpose. "This document belongs to another
/// branch" and "this document does not exist" are different facts, and telling them
/// apart would let anyone with the app enumerate which document ids are real across
/// the whole clinic group. It lives here rather than on one feature's access policy
/// because Stok Opname and Purchase Request refuse identically, and a second copy of
/// the wording is a second thing to keep in step.
const String accessDeniedMessage =
    'Anda tidak memiliki akses ke halaman ini. Dokumen ini mungkin tidak ada '
    'atau berada di cabang lain.';
