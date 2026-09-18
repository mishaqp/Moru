import 'dart:math' as math;

/// One passage of the cleaned document, with its BM25 score against the focus query.
class FocusChunk {
  const FocusChunk({
    required this.index,
    required this.text,
    required this.score,
  });

  /// 0-based position in the cleaned document, i.e. document order.
  final int index;

  /// The passage text, verbatim from the cleaned document.
  final String text;

  /// BM25 score against the focus query; 0.0 when no query term occurs in the passage.
  final double score;
}

/// Outcome of a focused extraction.
///
/// [text] holds the selected passages joined by a blank line, always in **document** order
/// (never score order) so the caller reads the page the way it was written.
class FocusResult {
  const FocusResult({
    required this.text,
    required this.chunksTotal,
    required this.chunksSelected,
    required this.originalChars,
    required this.returnedChars,
    required this.focused,
    required this.fallbackUsed,
  });

  final String text;
  final int chunksTotal;
  final int chunksSelected;
  final int originalChars;
  final int returnedChars;
  final bool focused;
  final bool fallbackUsed;
}

/// Query-focused passage selection: chunk, rank with a compact BM25, return the best passages.
///
/// Pure Dart: no Flutter, no platform channels, no network, no embeddings, no model, no
/// third-party dependency, so it runs in plain unit tests and costs almost nothing on a weak
/// phone. Indexing is a single pass over the chunks and scoring is one pass per query term, so
/// nothing here is quadratic in the document size.
///
/// This is a faithful port of RikkaHub's `QueryFocusedExtractor` (Kotlin), keeping the same
/// constants, chunking rules and scoring so a page ranked on either platform selects the same
/// passages. The one deliberate difference: Dart's core library has no Unicode normaliser, so
/// NFC normalisation is not applied before lowercasing (it changed nothing in practice for the
/// Latin/Cyrillic/CJK text these tools read, and dropping it avoids a dependency).
class QueryFocusedExtractor {
  const QueryFocusedExtractor._();

  /// Passages a focus query may select by default.
  static const int defaultTopK = 8;

  /// Ceiling for a focused result when the caller does not ask for less.
  static const int focusCharBudget = 12 * 1024;

  /// Passages are packed up to roughly this size; smaller neighbours are merged into one.
  static const int _preferredChunkChars = 900;

  /// No passage is allowed to grow past this without being split.
  static const int _maxChunkChars = 1600;

  /// A block below this is a fragment, not a paragraph, and gets merged with its neighbour.
  static const int _minChunkChars = 400;

  /// Smallest useful tail when the budget clips the last selected passage.
  static const int _minTailChars = 200;

  /// BM25 term-frequency saturation.
  static const double _bm25K1 = 1.2;

  /// BM25 length normalisation.
  static const double _bm25B = 0.75;

  /// Passages scoring below this share of the best score are dropped as noise.
  static const double _minScoreRatio = 0.05;

  /// Leading passages returned when the query matches nothing at all.
  static const int _fallbackChunks = 4;

  /// Word-shingle Jaccard at or above which a passage counts as a near-duplicate.
  static const double _nearDuplicateJaccard = 0.8;

  /// Shingle containment at or above which a passage is a duplicate of a longer one.
  static const double _nearDuplicateContainment = 0.9;

  /// Containment is only trusted once the smaller passage has this many shingles.
  static const int _minShinglesForContainment = 6;

  /// Shingle width used by the near-duplicate check.
  static const int _shingleWords = 3;

  static final RegExp _blockBreak = RegExp(r'\n\s*\n');
  static final RegExp _sentenceBreak = RegExp(r'(?<=[.!?…])\s+');
  static final RegExp _token = RegExp(r'[\p{L}\p{N}]+', unicode: true);
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Rank [text] against [query] and return the most relevant passages inside [charBudget].
  ///
  /// [charBudget] is an upper bound on [FocusResult.text]; pass
  /// `math.min(maxChars, focusCharBudget)` when the caller asked for less than the default.
  static FocusResult focus(
    String text,
    String query, {
    int charBudget = focusCharBudget,
    int topK = defaultTopK,
  }) {
    final originalChars = text.length;
    final budget = charBudget < 1 ? 1 : charBudget;

    if (text.trim().isEmpty) {
      return FocusResult(
        text: '',
        chunksTotal: 0,
        chunksSelected: 0,
        originalChars: originalChars,
        returnedChars: 0,
        focused: true,
        fallbackUsed: false,
      );
    }

    final chunks = _chunk(text);
    if (chunks.isEmpty) {
      return FocusResult(
        text: '',
        chunksTotal: 0,
        chunksSelected: 0,
        originalChars: originalChars,
        returnedChars: 0,
        focused: true,
        fallbackUsed: false,
      );
    }

    final queryTokens = tokenize(query).toSet().toList();

    // A blank query is not a query: hand the text back untouched (inside the budget)
    // instead of pretending a ranking happened.
    if (queryTokens.isEmpty) {
      final plain = text.trim();
      final out = plain.length <= budget
          ? plain
          : _cutAtWordBoundary(plain, budget);
      return FocusResult(
        text: out,
        chunksTotal: chunks.length,
        chunksSelected: out.isEmpty ? 0 : 1,
        originalChars: originalChars,
        returnedChars: out.length,
        focused: false,
        fallbackUsed: false,
      );
    }

    final index = _Bm25Index(chunks.map(tokenize).toList());
    final scored = <FocusChunk>[
      for (var i = 0; i < chunks.length; i++)
        FocusChunk(
          index: i,
          text: chunks[i],
          score: _bm25(index, queryTokens, i),
        ),
    ];
    final matched = scored.where((c) => c.score > 0.0).toList();

    final List<FocusChunk> candidates;
    final bool fallbackUsed;
    if (matched.isEmpty) {
      // Never answer "no match" with nothing: the caller asked for the page, so hand back
      // the leading passages and say that is what happened.
      fallbackUsed = true;
      candidates = [
        for (var i = 0; i < math.min(_fallbackChunks, chunks.length); i++)
          FocusChunk(index: i, text: chunks[i], score: 0.0),
      ];
    } else {
      fallbackUsed = false;
      final best = matched.map((c) => c.score).reduce(math.max);
      final floor = best * _minScoreRatio;
      final kept = matched.where((c) => c.score >= floor).toList()
        ..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : a.index.compareTo(b.index);
        });
      candidates = kept.take(topK < 1 ? 1 : topK).toList();
    }

    final ordered = _dropNearDuplicates(candidates)
      ..sort((a, b) => a.index.compareTo(b.index));
    final packed = _pack(ordered, budget);

    return FocusResult(
      text: packed.text,
      chunksTotal: chunks.length,
      chunksSelected: packed.count,
      originalChars: originalChars,
      returnedChars: packed.text.length,
      focused: true,
      fallbackUsed: fallbackUsed,
    );
  }

  /// Lowercase word/number tokens of [raw]: Cyrillic, Latin, CJK alike.
  static List<String> tokenize(String raw) {
    if (raw.isEmpty) return const <String>[];
    final normalized = raw.toLowerCase();
    final out = <String>[];
    for (final match in _token.allMatches(normalized)) {
      final value = match.group(0);
      if (value != null && value.isNotEmpty) out.add(value);
    }
    return out;
  }

  /// Split [text] into logical passages: blank lines are paragraph boundaries, small
  /// neighbours are merged, oversize blocks are split on sentence boundaries, exact duplicates
  /// are dropped. One pass over the blocks, no quadratic work.
  static List<String> _chunk(String text) {
    final blocks = text
        .split(_blockBreak)
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();
    if (blocks.isEmpty) return const <String>[];

    final merged = <String>[];
    final buffer = StringBuffer();
    for (final block in blocks) {
      if (buffer.isEmpty) {
        if (block.length >= _minChunkChars) {
          merged.add(block);
        } else {
          buffer.write(block);
        }
        continue;
      }
      final fitsTarget =
          buffer.length + 2 + block.length <= _preferredChunkChars;
      if (buffer.length < _minChunkChars && fitsTarget) {
        buffer.write('\n\n');
        buffer.write(block);
      } else {
        merged.add(buffer.toString());
        buffer.clear();
        if (block.length >= _minChunkChars) {
          merged.add(block);
        } else {
          buffer.write(block);
        }
      }
    }
    if (buffer.isNotEmpty) merged.add(buffer.toString());

    final seen = <String>{};
    final out = <String>[];
    for (final block in merged) {
      for (final piece in _splitOversize(block)) {
        if (piece.trim().isEmpty) continue;
        if (seen.add(_normalizeForKey(piece))) out.add(piece);
      }
    }
    return out;
  }

  /// Split a block that is longer than [_maxChunkChars] on sentence boundaries.
  static List<String> _splitOversize(String block) {
    if (block.length <= _maxChunkChars) return <String>[block];

    final sentences = block
        .split(_sentenceBreak)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (sentences.length <= 1) return _hardSplit(block);

    final out = <String>[];
    final buffer = StringBuffer();
    for (final sentence in sentences) {
      if (sentence.length > _maxChunkChars) {
        if (buffer.isNotEmpty) {
          out.add(buffer.toString());
          buffer.clear();
        }
        out.addAll(_hardSplit(sentence));
        continue;
      }
      if (buffer.isEmpty) {
        buffer.write(sentence);
        continue;
      }
      if (buffer.length + 1 + sentence.length <= _maxChunkChars) {
        buffer.write(' ');
        buffer.write(sentence);
      } else {
        out.add(buffer.toString());
        buffer.clear();
        buffer.write(sentence);
      }
    }
    if (buffer.isNotEmpty) out.add(buffer.toString());
    return out;
  }

  /// Last resort for a single sentence longer than [_maxChunkChars].
  static List<String> _hardSplit(String sentence) {
    if (sentence.length <= _maxChunkChars) return <String>[sentence];
    final out = <String>[];
    var start = 0;
    while (start < sentence.length) {
      final end = math.min(start + _maxChunkChars, sentence.length);
      final piece = sentence.substring(start, end).trim();
      if (piece.isNotEmpty) out.add(piece);
      start = end;
    }
    return out;
  }

  /// Drop passages that repeat text already kept.
  static List<FocusChunk> _dropNearDuplicates(List<FocusChunk> chunks) {
    if (chunks.length < 2) return List<FocusChunk>.of(chunks);
    final kept = <FocusChunk>[];
    final keptShingles = <Set<int>>[];
    for (final chunk in chunks) {
      final shingles = _shinglesOf(chunk.text);
      var duplicate = false;
      for (final existing in keptShingles) {
        if (_isDuplicate(shingles, existing)) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) {
        kept.add(chunk);
        keptShingles.add(shingles);
      }
    }
    return kept;
  }

  /// Hashed word n-grams of [text]; the shingle width is [_shingleWords].
  static Set<int> _shinglesOf(String text) {
    final tokens = tokenize(text);
    if (tokens.length < _shingleWords) {
      return tokens.map((t) => t.hashCode).toSet();
    }
    final out = <int>{};
    for (var start = 0; start <= tokens.length - _shingleWords; start++) {
      var hash = 17;
      for (var i = start; i < start + _shingleWords; i++) {
        hash = (hash * 31 + tokens[i].hashCode) & 0x3fffffff;
      }
      out.add(hash);
    }
    return out;
  }

  /// Two passages are duplicates when the same words dominate both (Jaccard) or when one
  /// repeats the other (containment).
  static bool _isDuplicate(Set<int> a, Set<int> b) {
    if (a.isEmpty && b.isEmpty) return true;
    if (a.isEmpty || b.isEmpty) return false;
    final small = a.length <= b.length ? a : b;
    final large = a.length <= b.length ? b : a;
    var intersection = 0;
    for (final value in small) {
      if (large.contains(value)) intersection++;
    }
    final union = a.length + b.length - intersection;
    if (union > 0 && intersection / union >= _nearDuplicateJaccard) return true;
    return small.length >= _minShinglesForContainment &&
        intersection / small.length >= _nearDuplicateContainment;
  }

  /// Case- and whitespace-insensitive key, used only for cheap exact-duplicate detection.
  static String _normalizeForKey(String text) =>
      text.toLowerCase().replaceAll(_whitespace, ' ').trim();

  /// Join the selected passages in document order until [budget] is reached.
  static _Packed _pack(List<FocusChunk> chunks, int budget) {
    final sb = StringBuffer();
    var used = 0;
    var count = 0;
    for (final chunk in chunks) {
      final separator = sb.isEmpty ? 0 : 2;
      final need = separator + chunk.text.length;
      if (used + need <= budget) {
        if (separator == 2) sb.write('\n\n');
        sb.write(chunk.text);
        used += need;
        count++;
        continue;
      }
      if (sb.isEmpty) {
        sb.write(_cutAtWordBoundary(chunk.text, budget));
        count++;
        break;
      }
      final remaining = budget - used - separator;
      if (remaining >= _minTailChars) {
        sb.write('\n\n');
        sb.write(_cutAtWordBoundary(chunk.text, remaining));
        count++;
      }
      break;
    }
    final text = sb.toString();
    return _Packed(text: text, count: text.trim().isEmpty ? 0 : count);
  }

  /// Clip [text] to [limit] characters, preferring the last word boundary in the final third.
  static String _cutAtWordBoundary(String text, int limit) {
    if (text.length <= limit) return text;
    final cut = text.substring(0, limit);
    final lastSpace = cut.lastIndexOf(' ');
    return lastSpace >= limit * 2 ~/ 3
        ? cut.substring(0, lastSpace).trimRight()
        : cut.trimRight();
  }

  /// BM25 of one passage against the query terms, with the Robertson IDF (always positive).
  static double _bm25(_Bm25Index index, List<String> queryTokens, int doc) {
    if (index.freq.isEmpty || index.averageLength <= 0.0) return 0.0;
    final counts = index.freq[doc];
    final length = index.lengths[doc].toDouble();
    final docs = index.freq.length.toDouble();
    var score = 0.0;
    for (final term in queryTokens) {
      final tf = counts[term];
      if (tf == null) continue;
      final df = index.docFreq[term];
      if (df == null) continue;
      final idf = math.log(1.0 + (docs - df + 0.5) / (df + 0.5));
      final norm =
          tf +
          _bm25K1 * (1.0 - _bm25B + _bm25B * (length / index.averageLength));
      score += idf * (tf * (_bm25K1 + 1.0)) / norm;
    }
    return score;
  }
}

class _Packed {
  const _Packed({required this.text, required this.count});

  final String text;
  final int count;
}

/// Inverted-token bookkeeping for BM25: per-document frequencies, document frequencies, lengths.
class _Bm25Index {
  _Bm25Index(List<List<String>> docs) : this._(_build(docs));

  _Bm25Index._(_IndexData data)
    : freq = data.freq,
      docFreq = data.docFreq,
      lengths = data.lengths,
      averageLength = data.averageLength;

  final List<Map<String, int>> freq;
  final Map<String, int> docFreq;
  final List<int> lengths;
  final double averageLength;

  static _IndexData _build(List<List<String>> docs) {
    final perDoc = <Map<String, int>>[];
    final lengths = List<int>.filled(docs.length, 0);
    final docFreq = <String, int>{};
    for (var i = 0; i < docs.length; i++) {
      final tokens = docs[i];
      lengths[i] = tokens.length;
      final counts = <String, int>{};
      for (final token in tokens) {
        final seen = counts[token];
        if (seen == null) {
          counts[token] = 1;
          docFreq[token] = (docFreq[token] ?? 0) + 1;
        } else {
          counts[token] = seen + 1;
        }
      }
      perDoc.add(counts);
    }
    final average = docs.isEmpty
        ? 0.0
        : lengths.fold<int>(0, (a, b) => a + b) / docs.length.toDouble();
    return _IndexData(perDoc, docFreq, lengths, average);
  }
}

class _IndexData {
  const _IndexData(this.freq, this.docFreq, this.lengths, this.averageLength);

  final List<Map<String, int>> freq;
  final Map<String, int> docFreq;
  final List<int> lengths;
  final double averageLength;
}
