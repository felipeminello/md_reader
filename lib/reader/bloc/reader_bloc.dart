import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/markdown_repository.dart';
import 'reader_event.dart';
import 'reader_state.dart';

/// Business logic for the Markdown reader.
///
/// Mediates between the UI and the [MarkdownRepository]: widgets dispatch
/// [ReaderEvent]s and render [ReaderState]s, and never touch the repository or
/// the file system themselves.
class ReaderBloc extends Bloc<ReaderEvent, ReaderState> {
  ReaderBloc(this._repository) : super(const ReaderEmpty()) {
    on<ReaderFileOpened>(_onFileOpened);
    on<ReaderFileClosed>(_onFileClosed);
  }

  final MarkdownRepository _repository;

  Future<void> _onFileOpened(
    ReaderFileOpened event,
    Emitter<ReaderState> emit,
  ) async {
    final path = await _repository.pickMarkdownPath();
    if (path == null) {
      // The user dismissed the picker without choosing a file: keep the
      // current state instead of flashing an error or an empty screen.
      return;
    }

    emit(const ReaderLoading());
    try {
      final document = await _repository.readDocument(path);
      emit(ReaderLoaded(document));
    } on MarkdownReadException catch (e) {
      emit(ReaderFailure(e.message));
    } catch (e) {
      emit(ReaderFailure('Não foi possível abrir o arquivo. $e'));
    }
  }

  void _onFileClosed(
    ReaderFileClosed event,
    Emitter<ReaderState> emit,
  ) {
    emit(const ReaderEmpty());
  }
}
