import '../data/markdown_document.dart';

/// Base class for every state the reader screen can be in.
sealed class ReaderState {
  const ReaderState();
}

/// No document is open — the screen shows the empty placeholder.
class ReaderEmpty extends ReaderState {
  const ReaderEmpty();
}

/// A file was picked and is currently being read from disk.
class ReaderLoading extends ReaderState {
  const ReaderLoading();
}

/// A document was loaded successfully and is ready to be rendered.
class ReaderLoaded extends ReaderState {
  const ReaderLoaded(this.document);

  final MarkdownDocument document;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderLoaded && other.document == document;

  @override
  int get hashCode => document.hashCode;
}

/// Reading the selected file failed; [message] explains why.
class ReaderFailure extends ReaderState {
  const ReaderFailure(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderFailure && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
