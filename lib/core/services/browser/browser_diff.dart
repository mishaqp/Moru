/// Token-cost optimisation: line-level text diff for the browser's
/// "diff-after-action" path.
///
/// State-changing browser actions (click / type / submit / select / press) used to return a tiny
/// envelope, after which the model had to call a read action again and re-consume the whole page
/// - most actions only mutate a small part of the visible text. Sending only the delta cuts the
/// per-step payload by roughly an order of magnitude on multi-step sessions.
///
/// The algorithm is intentionally simple - set membership over newline-split lines:
///  * `added`   = lines present in `after` but absent from `before`
///  * `removed` = lines present in `before` but absent from `after`
///
/// Conservative choice over a Myers / patience diff: the output the model consumes is "what's
/// new on the page", not "what bytes shifted". Line-set is sufficient and runs in O(N).
///
/// Port of RikkaHub's `BrowserDiffHelper` (Kotlin), same caps and same envelope keys.
class BrowserDiffHelper {
  const BrowserDiffHelper._();

  /// Per-side cap. Total envelope payload is <= 2 * [maxCharsPerSide] + JSON keys.
  static const int maxCharsPerSide = 2000;

  /// Compute the diff envelope for an action that transitioned the page from [before] to
  /// [after].
  ///
  /// Identical inputs (no visible effect) return `{'unchanged': true}`. Distinct inputs return
  /// `{added, removed, added_chars, removed_chars, truncated}`.
  static Map<String, dynamic> computeDiff(String before, String after) {
    if (before == after) return <String, dynamic>{'unchanged': true};

    // Ordered set semantics: preserve insertion order so the model reads the delta in document
    // order rather than hash order, and a repeated line is emitted once.
    final beforeLines = before.split('\n').toSet();
    final afterLines = after.split('\n').toSet();

    final addedLines = <String>[];
    for (final line in after.split('\n')) {
      if (!beforeLines.contains(line) && !addedLines.contains(line)) {
        addedLines.add(line);
      }
    }
    final removedLines = <String>[];
    for (final line in before.split('\n')) {
      if (!afterLines.contains(line) && !removedLines.contains(line)) {
        removedLines.add(line);
      }
    }

    final rawAdded = addedLines.join('\n').trim();
    final rawRemoved = removedLines.join('\n').trim();

    // Both sides empty -> identical-after-trim (e.g. only whitespace lines moved around).
    if (rawAdded.isEmpty && rawRemoved.isEmpty) {
      return <String, dynamic>{'unchanged': true};
    }

    final added = _truncate(rawAdded);
    final removed = _truncate(rawRemoved);

    return <String, dynamic>{
      'added': added.text,
      'removed': removed.text,
      'added_chars': added.text.length,
      'removed_chars': removed.text.length,
      'truncated': added.truncated || removed.truncated,
    };
  }

  static _Truncated _truncate(String value) => value.length <= maxCharsPerSide
      ? _Truncated(value, false)
      : _Truncated(value.substring(0, maxCharsPerSide), true);
}

class _Truncated {
  const _Truncated(this.text, this.truncated);

  final String text;
  final bool truncated;
}
