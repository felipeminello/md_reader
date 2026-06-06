/// Immutable representation of a Markdown file that the user has opened.
///
/// Lives in the data layer and is produced by [MarkdownRepository]. The Bloc
/// passes it up to the presentation layer for rendering.
class MarkdownDocument {
  const MarkdownDocument({required this.path, required this.content});

  /// Absolute path of the file on disk.
  final String path;

  /// Raw Markdown source read from the file.
  final String content;

  /// File name (with extension) derived from [path], for display in the UI.
  ///
  /// Handles both Windows (`\`) and POSIX (`/`) separators so it stays correct
  /// regardless of how the path was produced.
  String get fileName {
    final segments = path.replaceAll('\\', '/').split('/');
    return segments.isEmpty ? path : segments.last;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownDocument &&
          other.path == path &&
          other.content == content;

  @override
  int get hashCode => Object.hash(path, content);
}
