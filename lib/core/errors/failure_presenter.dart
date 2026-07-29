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
