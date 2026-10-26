import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/text_search.dart';
import 'find_event.dart';
import 'find_state.dart';

/// Business logic for *Localizar* (find in the open document).
///
/// The view reports the document's searchable text with
/// [FindContentChanged]; the Bloc searches it with [TextSearch] and tracks
/// which occurrence the user is on. Highlighting and scrolling are left to the
/// presentation layer, which renders [FindState].
class FindBloc extends Bloc<FindEvent, FindState> {
  FindBloc() : super(const FindState()) {
    on<FindOpened>(_onOpened);
    on<FindClosed>(_onClosed);
    on<FindQueryChanged>(_onQueryChanged);
    on<FindNextRequested>(_onNextRequested);
    on<FindPreviousRequested>(_onPreviousRequested);
    on<FindContentChanged>(_onContentChanged);
  }

  /// Searchable text of the rendered document, from the last
  /// [FindContentChanged].
  List<String> _segments = const [];

  void _onOpened(FindOpened event, Emitter<FindState> emit) {
    final focusRequests = state.focusRequests + 1;
    if (state.isOpen) {
      emit(state.copyWith(focusRequests: focusRequests));
      return;
    }
    // Reopening runs the previous search again and goes to its first result.
    final matches = TextSearch.findAll(_segments, state.query);
    emit(
      state.copyWith(
        isOpen: true,
        matches: matches,
        currentIndex: matches.isEmpty ? -1 : 0,
        focusRequests: focusRequests,
        revealRequests: state.revealRequests + 1,
      ),
    );
  }

  void _onClosed(FindClosed event, Emitter<FindState> emit) {
    emit(state.copyWith(isOpen: false, matches: const [], currentIndex: -1));
  }

  void _onQueryChanged(FindQueryChanged event, Emitter<FindState> emit) {
    final matches = TextSearch.findAll(_segments, event.query);
    emit(
      state.copyWith(
        query: event.query,
        matches: matches,
        // Every new search jumps to its first occurrence.
        currentIndex: matches.isEmpty ? -1 : 0,
        revealRequests: state.revealRequests + 1,
      ),
    );
  }

  void _onNextRequested(FindNextRequested event, Emitter<FindState> emit) {
    _step(1, emit);
  }

  void _onPreviousRequested(
    FindPreviousRequested event,
    Emitter<FindState> emit,
  ) {
    _step(-1, emit);
  }

  void _step(int delta, Emitter<FindState> emit) {
    final count = state.matchCount;
    if (count == 0) return;
    emit(
      state.copyWith(
        currentIndex: (state.currentIndex + delta) % count,
        revealRequests: state.revealRequests + 1,
      ),
    );
  }

  void _onContentChanged(FindContentChanged event, Emitter<FindState> emit) {
    if (listEquals(event.segments, _segments)) return;
    _segments = List.unmodifiable(event.segments);
    if (!state.isOpen) return;

    final matches = TextSearch.findAll(_segments, state.query);
    emit(
      state.copyWith(
        matches: matches,
        currentIndex: matches.isEmpty
            ? -1
            : state.currentIndex.clamp(0, matches.length - 1),
      ),
    );
  }
}
