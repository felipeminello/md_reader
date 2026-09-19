import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/markdown_repository.dart';
import '../data/system_file_opener.dart';
import 'reader_event.dart';
import 'reader_state.dart';

/// Business logic for the Markdown reader.
///
/// Mediates between the UI and the [MarkdownRepository]: widgets dispatch
/// [ReaderEvent]s and render [ReaderState]s, and never touch the repository or
/// the file system themselves.
class ReaderBloc extends Bloc<ReaderEvent, ReaderState> {
  ReaderBloc(this._repository, {SystemFileOpener? systemFileOpener})
      : _systemFileOpener = systemFileOpener,
        super(const ReaderEmpty()) {
    on<ReaderFileOpened>(_onFileOpened);
    on<ReaderFileClosed>(_onFileClosed);
    on<ReaderFileDropped>(_onPathEvent);
    on<ReaderSystemFileOpened>(_onPathEvent);

    _watchSystemFileOpener();
  }

  final MarkdownRepository _repository;

  /// Optional: absent on platforms (and in tests) where the OS never hands
  /// files to the app.
  final SystemFileOpener? _systemFileOpener;

  StreamSubscription<String>? _systemFileSubscription;

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

    await _loadDocument(path, emit);
  }

  /// Handles every event that arrives with a path already chosen outside the
  /// picker: drag-and-drop and files opened from the OS.
  Future<void> _onPathEvent(
    ReaderPathEvent event,
    Emitter<ReaderState> emit,
  ) async {
    if (!_repository.isMarkdownPath(event.path)) {
      emit(
        const ReaderFailure(
          'Tipo de arquivo não suportado. Abra um arquivo .md.',
        ),
      );
      return;
    }

    await _loadDocument(event.path, emit);
  }

  void _onFileClosed(
    ReaderFileClosed event,
    Emitter<ReaderState> emit,
  ) {
    emit(const ReaderEmpty());
  }

  Future<void> _loadDocument(String path, Emitter<ReaderState> emit) async {
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

  /// Turns files handed over by the OS into [ReaderSystemFileOpened] events:
  /// the one the app was launched with, plus any that arrive while it runs.
  void _watchSystemFileOpener() {
    final opener = _systemFileOpener;
    if (opener == null) return;

    _systemFileSubscription = opener.files.listen(
      (path) => add(ReaderSystemFileOpened(path)),
    );

    unawaited(
      opener.start().then((path) {
        if (path != null && !isClosed) add(ReaderSystemFileOpened(path));
      }),
    );
  }

  @override
  Future<void> close() async {
    await _systemFileSubscription?.cancel();
    return super.close();
  }
}
