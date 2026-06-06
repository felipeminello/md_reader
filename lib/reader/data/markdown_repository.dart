import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'markdown_document.dart';

/// Raised when a selected Markdown file cannot be read from disk.
class MarkdownReadException implements Exception {
  const MarkdownReadException(this.message);

  final String message;

  @override
  String toString() => 'MarkdownReadException: $message';
}

/// Data source responsible for locating and reading Markdown files.
///
/// This is the only place that talks to the file system and the native file
/// picker. The [ReaderBloc] depends on it; widgets must never use it directly.
class MarkdownRepository {
  const MarkdownRepository();

  /// Opens the native file picker so the user can choose a Markdown file.
  ///
  /// Returns the selected absolute path, or `null` if the user cancelled.
  Future<String?> pickMarkdownPath() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Selecionar arquivo Markdown',
      type: FileType.custom,
      allowedExtensions: const ['md', 'markdown', 'mdown', 'mkd', 'txt'],
    );
    return result?.files.single.path;
  }

  /// Reads the file at [path] from disk and wraps it in a [MarkdownDocument].
  ///
  /// Throws [MarkdownReadException] if the file cannot be read.
  Future<MarkdownDocument> readDocument(String path) async {
    try {
      final content = await File(path).readAsString();
      return MarkdownDocument(path: path, content: content);
    } on FileSystemException catch (e) {
      throw MarkdownReadException(e.message);
    }
  }
}
