import 'package:flutter/foundation.dart';

import '../data/text_search.dart';

/// State of the *Localizar* (find in document) bar.
class FindState {
  const FindState({
    this.isOpen = false,
    this.query = '',
    this.matches = const [],
    this.currentIndex = -1,
    this.focusRequests = 0,
    this.revealRequests = 0,
  });

  /// Whether the find bar is visible.
  final bool isOpen;

  /// The text being searched for. Kept while the bar is closed, so reopening
  /// it starts from the last search.
  final String query;

  /// Every occurrence of [query] in the document, in reading order. Empty
  /// while the bar is closed, so nothing stays highlighted.
  final List<TextMatch> matches;

  /// Index into [matches] of the occurrence the user is on, or `-1` when
  /// there is none.
  final int currentIndex;

  /// Bumped every time the bar is asked to take keyboard focus, even when it
  /// is already open, so the view can react to repeated Cmd+F / Ctrl+F.
  final int focusRequests;

  /// Bumped every time the [currentMatch] should be scrolled into view, even
  /// when it did not change (e.g. "next" with a single occurrence).
  final int revealRequests;

  TextMatch? get currentMatch =>
      currentIndex >= 0 && currentIndex < matches.length
          ? matches[currentIndex]
          : null;

  int get matchCount => matches.length;

  FindState copyWith({
    bool? isOpen,
    String? query,
    List<TextMatch>? matches,
    int? currentIndex,
    int? focusRequests,
    int? revealRequests,
  }) {
    return FindState(
      isOpen: isOpen ?? this.isOpen,
      query: query ?? this.query,
      matches: matches ?? this.matches,
      currentIndex: currentIndex ?? this.currentIndex,
      focusRequests: focusRequests ?? this.focusRequests,
      revealRequests: revealRequests ?? this.revealRequests,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FindState &&
          other.isOpen == isOpen &&
          other.query == query &&
          listEquals(other.matches, matches) &&
          other.currentIndex == currentIndex &&
          other.focusRequests == focusRequests &&
          other.revealRequests == revealRequests;

  @override
  int get hashCode => Object.hash(
        isOpen,
        query,
        Object.hashAll(matches),
        currentIndex,
        focusRequests,
        revealRequests,
      );
}
