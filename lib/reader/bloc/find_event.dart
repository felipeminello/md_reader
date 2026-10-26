/// Base class for every event handled by the [FindBloc], which drives the
/// *Localizar* (find in document) bar.
sealed class FindEvent {
  const FindEvent();
}

/// The user asked to find in the document — the magnifier button or
/// Cmd+F / Ctrl+F. Opens the find bar, or focuses it again if already open.
class FindOpened extends FindEvent {
  const FindOpened();
}

/// The find bar was closed (Esc, its close button, or the document went away).
class FindClosed extends FindEvent {
  const FindClosed();
}

/// The user typed in the find bar; [query] is the whole text of the field.
class FindQueryChanged extends FindEvent {
  const FindQueryChanged(this.query);

  final String query;
}

/// Go to the next occurrence (wrapping around to the first).
class FindNextRequested extends FindEvent {
  const FindNextRequested();
}

/// Go to the previous occurrence (wrapping around to the last).
class FindPreviousRequested extends FindEvent {
  const FindPreviousRequested();
}

/// The rendered document changed; [segments] is its searchable text, one
/// entry per rendered block, in reading order.
class FindContentChanged extends FindEvent {
  const FindContentChanged(this.segments);

  final List<String> segments;
}
