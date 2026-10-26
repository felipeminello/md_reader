/// One occurrence of the search term inside the searchable text of a document.
///
/// The document is searched as a list of text segments (one per rendered
/// paragraph, heading, list item, table cell or code block); [segment] is the
/// index of the one holding the match and [start]/[end] are UTF-16 offsets
/// into it, `end` exclusive.
class TextMatch {
  const TextMatch({
    required this.segment,
    required this.start,
    required this.end,
  });

  final int segment;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextMatch &&
          other.segment == segment &&
          other.start == start &&
          other.end == end;

  @override
  int get hashCode => Object.hash(segment, start, end);

  @override
  String toString() => 'TextMatch($segment, $start..$end)';
}

/// Finds every occurrence of a term in a list of text segments, the way a
/// browser's *Find* does: ignoring case and accents, so `acao` also finds
/// `Ação`.
abstract final class TextSearch {
  /// Every non-overlapping occurrence of [query] in [segments], in reading
  /// order. An empty [query] matches nothing.
  static List<TextMatch> findAll(List<String> segments, String query) {
    if (query.isEmpty) return const [];

    final needle = _fold(query);
    final matches = <TextMatch>[];
    for (var segment = 0; segment < segments.length; segment++) {
      final haystack = _fold(segments[segment]);
      var start = haystack.indexOf(needle);
      while (start != -1) {
        final end = start + needle.length;
        matches.add(TextMatch(segment: segment, start: start, end: end));
        start = haystack.indexOf(needle, end);
      }
    }
    return matches;
  }

  /// Lower-cases [text] and strips the accents of Latin letters, one UTF-16
  /// unit at a time so offsets in the result still line up with [text].
  static String _fold(String text) {
    final buffer = StringBuffer();
    for (final unit in text.codeUnits) {
      final char = String.fromCharCode(unit);
      final lower = char.toLowerCase();
      // A few characters (such as `İ`) lower-case to two units; keep those
      // as they are rather than shifting every later offset.
      final folded = lower.length == 1 ? lower : char;
      buffer.write(_accentless[folded] ?? folded);
    }
    return buffer.toString();
  }

  static final Map<String, String> _accentless = {
    for (final MapEntry(key: base, value: accented) in const {
      'a': 'áàâãäå',
      'c': 'ç',
      'e': 'éèêë',
      'i': 'íìîï',
      'n': 'ñ',
      'o': 'óòôõö',
      'u': 'úùûü',
      'y': 'ýÿ',
    }.entries)
      for (final char in accented.split('')) char: base,
  };
}
