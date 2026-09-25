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

  /// Resolves an image reference found in [content] to a loadable [Uri].
  ///
  /// Remote (`http`/`https`), inline (`data:`) and explicit `file:` URIs are
  /// returned untouched. Windows absolute paths (`C:\img.png`, which [Uri]
  /// parses as a one-letter scheme) become `file:` URIs, and everything else
  /// is treated as a path relative to the folder containing this document,
  /// the same way GitHub and other Markdown viewers resolve them.
  Uri resolveImageUri(Uri source) {
    if (source.scheme.length == 1) {
      final drive = source.scheme.toUpperCase();
      return Uri.file('$drive:${Uri.decodeComponent(source.path)}',
          windows: true);
    }
    if (source.hasScheme) return source;
    return Uri.file(path, windows: _isWindowsPath).resolveUri(source);
  }

  /// Whether [path] uses Windows conventions (drive letter or `\`), detected
  /// from the path itself so resolution does not depend on the host platform.
  bool get _isWindowsPath =>
      path.contains('\\') || RegExp(r'^[a-zA-Z]:').hasMatch(path);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownDocument &&
          other.path == path &&
          other.content == content;

  @override
  int get hashCode => Object.hash(path, content);
}
