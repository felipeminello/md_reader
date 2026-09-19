/// Base class for every event handled by the [ReaderBloc].
///
/// The UI only ever dispatches these; it never mutates state directly.
sealed class ReaderEvent {
  const ReaderEvent();
}

/// Events that already carry the [path] of a file to open, so no picker is
/// involved. The Bloc validates the extension before reading them.
sealed class ReaderPathEvent extends ReaderEvent {
  const ReaderPathEvent(this.path);

  final String path;
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

/// The user dropped a file onto the reader (drag-and-drop). Reads and
/// displays it, same as [ReaderFileOpened], if its extension is supported.
class ReaderFileDropped extends ReaderPathEvent {
  const ReaderFileDropped(super.path);
}

/// The operating system asked the app to open a file — on macOS, a `.md`
/// double-clicked in Finder or opened through *Abrir com*.
class ReaderSystemFileOpened extends ReaderPathEvent {
  const ReaderSystemFileOpened(super.path);
}
