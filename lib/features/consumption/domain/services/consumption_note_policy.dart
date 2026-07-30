/// How a consumption's free-text notes are normalized, in one place (§8/§19).
///
/// Two rules, and the second is what makes this a policy rather than a `trim()` call:
///
/// 1. **Blank is absent.** `"  "`, `"\n"` and `"\t"` all become `null` rather than
///    sitting in the column pretending to be a remark. `String.trim()` in Dart strips
///    tabs and newlines where SQLite's `trim()` strips spaces only, so the database
///    CHECK is the floor and this is the authority.
/// 2. **The movement note is composed once.** A ledger row's text is the document's note
///    plus the line's own detail, joined the same way for every row of every document —
///    so two callers cannot produce differently-worded audit trails for the same facts,
///    and a test can assert the whole ledger's notes from the plan alone.
///
/// ### A note is optional here, unlike a disposal's reason
///
/// `DisposalReasonPolicy` has a `normalize` that the guards turn into a *refusal* when
/// it returns null, because G-E7 makes a note mandatory on a destruction. Nothing in the
/// specification asks a nurse to justify ordinary consumption, so there is deliberately
/// no `requireNote` anywhere in this feature: the header CHECK does not demand one, the
/// guarded `markPosted` statement does not test for one, and [movementNote] returns
/// `null` rather than a placeholder when neither note carries text. Inventing the
/// requirement would be inventing a rule — and it would put a compulsory free-text field
/// in front of somebody recording what they just used, which is precisely where invented
/// text ends up being `"-"`.
///
/// ### What may never go in one
///
/// Neither note is a place for patient information: no name, no medical-record number,
/// no diagnosis, no procedure detail (§9). Nothing here can enforce that on free text —
/// what the schema and this policy do enforce is that there is no *column* inviting it,
/// and that the ledger note is composed from these two fields only.
abstract final class ConsumptionNotePolicy {
  /// Trims [note] and turns a blank one into `null`.
  ///
  /// The single normalizer every writer uses, so a note stored by the create path and
  /// one stored by the edit path are byte-identical for the same input.
  static String? normalize(String? note) {
    final trimmed = note?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Whether [note] carries something a reader can act on.
  static bool hasText(String? note) => normalize(note) != null;

  /// The deterministic ledger note for one line.
  ///
  /// * both present → `"<header> · <line>"`;
  /// * one present → that one;
  /// * neither → `null`, which is a legitimate `stock_movements.note` (§19).
  ///
  /// The separator is a middle dot rather than a newline so the text stays on one line
  /// in a stock-card row, which is where it is read.
  static String? movementNote({String? headerNote, String? lineNote}) {
    final header = normalize(headerNote);
    final line = normalize(lineNote);
    if (header == null) return line;
    if (line == null) return header;
    return '$header · $line';
  }
}
