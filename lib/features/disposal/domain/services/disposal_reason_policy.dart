/// One of the reasons the form offers, as a chip (§19).
///
/// A value object rather than a bare string, because two facts travel with each
/// choice and the second is what makes the audit trail readable: whether the choice
/// says anything on its own, or needs the user to finish the sentence.
class DisposalReasonPreset {
  const DisposalReasonPreset({
    required this.code,
    required this.label,
    this.requiresDetail = false,
  });

  /// A stable identifier for the chip. **Never stored** — see
  /// [DisposalReasonPolicy.compose]. It exists so a widget can remember which chip
  /// is selected without comparing display strings.
  final String code;

  /// The human-readable text that *is* stored, alone or as the first half of the
  /// composed reason.
  final String label;

  /// Whether the label says too little on its own to be an audit record.
  ///
  /// True for `Lainnya` only, and that is the whole point of the flag: a stored
  /// reason of the literal word *"Lainnya"* explains nothing to the person reading
  /// the ledger a year later, which is the reader G-E7 is written for.
  final bool requiresDetail;
}

/// G-E7's mandatory note, and what it is allowed to say (§19).
///
/// *"Barang kedaluwarsa dikeluarkan dari stok hanya lewat movement `disposal`
/// (pemusnahan) dengan catatan & pelaku."*
///
/// The rule the specification states is that a note exists. What this policy adds
/// is that the note has to be worth reading, and it does that in three ways:
///
/// * **Whitespace is not a reason.** `String.trim()` in Dart strips tabs and
///   newlines; SQLite's `trim()` strips spaces only. A reason of `"\n\n"` therefore
///   satisfies the database CHECK and is refused here. The CHECK is the floor —
///   defence against a hand-written UPDATE — and this is the authority.
/// * **A preset code is never stored.** What goes into `disposals.reason` and into
///   every movement note is the *label*, in Indonesian, spelled out. Storing
///   `"cleanup"` and rendering it through a lookup table would mean a ledger row
///   whose meaning lives in a version of the app that may not exist any more.
/// * **`Lainnya` must finish its sentence.** The one preset that says nothing on
///   its own requires a detail, and the two are composed into a single readable
///   line rather than kept in separate fields — because the movement note is one
///   TEXT column and splitting the meaning across two places is how half of it gets
///   lost.
///
/// Everything here is pure. The presets are data the form renders; the composition
/// and validation are what the use cases apply, and the ledger note is derived from
/// the same function so a document's reason and its movements can never say
/// different things.
abstract final class DisposalReasonPolicy {
  /// Separator between a preset label and its detail, and between a header reason
  /// and a line note. An em dash with spaces, matching the wording §19 gives as an
  /// example: `Pembersihan stok lama — Ditemukan saat audit bulanan`.
  static const String separator = ' — ';

  /// The chips the form offers.
  ///
  /// Ordered from the most common to the least, because the first is the answer
  /// most of the time: the goods expired, and that is all there is to say.
  static const List<DisposalReasonPreset> presets = [
    DisposalReasonPreset(code: 'expired', label: 'Kedaluwarsa'),
    DisposalReasonPreset(
      code: 'damaged_after_expiry',
      label: 'Kemasan rusak setelah kedaluwarsa',
    ),
    DisposalReasonPreset(code: 'opname', label: 'Hasil stok opname'),
    DisposalReasonPreset(code: 'cleanup', label: 'Pembersihan stok lama'),
    DisposalReasonPreset(code: 'other', label: 'Lainnya', requiresDetail: true),
  ];

  /// The preset with [code], or `null`.
  static DisposalReasonPreset? presetByCode(String? code) {
    if (code == null) return null;
    for (final preset in presets) {
      if (preset.code == code) return preset;
    }
    return null;
  }

  /// Trims [value] and turns blank into `null`.
  ///
  /// The single normalisation every writer applies, so a reason stored by the
  /// create path and one stored by the edit path are byte-identical for the same
  /// input.
  static String? normalize(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Whether [value] is a reason G-E7 would accept.
  static bool isValid(String? value) => normalize(value) != null;

  /// The audit text for a chip plus its optional detail.
  ///
  /// Returns `null` when the result would not be a valid reason — an unknown
  /// preset, or `Lainnya` with nothing typed after it — so the caller refuses
  /// rather than storing half a sentence.
  ///
  /// A preset that does not require a detail still accepts one, and appends it:
  /// *"Kedaluwarsa — batch B-OLD bocor"* is strictly more informative than either
  /// half, and there is no reason to throw the extra away.
  ///
  /// Both arguments are optional, because "no chip selected, free text only" is a
  /// legitimate state the form allows — the branch head types a sentence of their
  /// own and never touches the chips.
  static String? compose({String? presetCode, String? detail}) {
    final preset = presetByCode(presetCode);
    if (preset == null) {
      // No chip selected: whatever was typed is the whole reason, if anything was.
      return normalize(detail);
    }
    final trimmedDetail = normalize(detail);
    if (preset.requiresDetail && trimmedDetail == null) return null;
    if (trimmedDetail == null) return preset.label;
    return '${preset.label}$separator$trimmedDetail';
  }

  /// The note one ledger movement carries (§20).
  ///
  /// Deterministic by construction: the header reason, then the line's own detail
  /// when it has one, joined by [separator]. Two devices posting the same document
  /// write the same text, and a movement is never left with an empty note — which
  /// is what makes *"note non-empty"* an assertion the ledger tests can make about
  /// every `disposal` row rather than about most of them.
  ///
  /// [reason] is required and must already be valid; a caller that has not checked
  /// is a caller that would write an unexplained movement, so this throws rather
  /// than inventing a fallback sentence.
  static String movementNote({required String reason, String? lineNote}) {
    final normalizedReason = normalize(reason);
    if (normalizedReason == null) {
      throw ArgumentError.value(
        reason,
        'reason',
        'Catatan pemusnahan wajib diisi (G-E7).',
      );
    }
    final normalizedLineNote = normalize(lineNote);
    if (normalizedLineNote == null) return normalizedReason;
    return '$normalizedReason$separator$normalizedLineNote';
  }
}
