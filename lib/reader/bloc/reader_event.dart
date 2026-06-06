/// Base class for every event handled by the [ReaderBloc].
///
/// The UI only ever dispatches these; it never mutates state directly.
sealed class ReaderEvent {
  const ReaderEvent();
}

/// The user asked to open a Markdown file. Triggers the native file picker
/// and, if a file is chosen, reads and displays it.
class ReaderFileOpened extends ReaderEvent {
  const ReaderFileOpened();
}

/// The user closed the currently open document, returning to the empty state.
class ReaderFileClosed extends ReaderEvent {
  const ReaderFileClosed();
}
