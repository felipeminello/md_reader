// Tests for the Markdown reader.
//
// The Bloc is exercised against a fake repository so the file picker and the
// real file system are never touched, and the widget layer is checked for the
// empty/loaded/close behaviour.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:md_reader/main.dart';
import 'package:md_reader/reader/bloc/reader_bloc.dart';
import 'package:md_reader/reader/bloc/reader_event.dart';
import 'package:md_reader/reader/bloc/reader_state.dart';
import 'package:md_reader/reader/data/markdown_document.dart';
import 'package:md_reader/reader/data/markdown_repository.dart';
import 'package:md_reader/reader/presentation/reader_page.dart';
import 'package:md_reader/reader/presentation/widgets/markdown_view.dart';

/// Stand-in for [MarkdownRepository] with scripted behaviour, so tests stay
/// off the native file picker and the disk.
class _FakeRepository implements MarkdownRepository {
  _FakeRepository({this.pickResult, this.document, this.failOnRead = false});

  /// Path returned by the picker (`null` simulates the user cancelling).
  final String? pickResult;
  final MarkdownDocument? document;
  final bool failOnRead;

  @override
  Future<String?> pickMarkdownPath() async => pickResult;

  @override
  Future<MarkdownDocument> readDocument(String path) async {
    if (failOnRead) throw const MarkdownReadException('arquivo inacessível');
    return document ?? MarkdownDocument(path: path, content: '# Olá');
  }
}

void main() {
  group('ReaderBloc', () {
    test('starts in the empty state', () {
      final bloc = ReaderBloc(_FakeRepository());
      expect(bloc.state, isA<ReaderEmpty>());
    });

    test('emits [Loading, Loaded] when a file is picked and read', () {
      final bloc = ReaderBloc(
        _FakeRepository(
          pickResult: r'C:\docs\notas.md',
          document: const MarkdownDocument(
            path: r'C:\docs\notas.md',
            content: '# Notas',
          ),
        ),
      );

      expectLater(
        bloc.stream,
        emitsInOrder([isA<ReaderLoading>(), isA<ReaderLoaded>()]),
      );

      bloc.add(const ReaderFileOpened());
    });

    test('stays empty when the user cancels the picker', () async {
      final bloc = ReaderBloc(_FakeRepository(pickResult: null));

      bloc.add(const ReaderFileOpened());
      // Let the (async) handler run to completion.
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state, isA<ReaderEmpty>());
    });

    test('emits [Loading, Failure] when reading fails', () {
      final bloc = ReaderBloc(
        _FakeRepository(pickResult: r'C:\docs\broken.md', failOnRead: true),
      );

      expectLater(
        bloc.stream,
        emitsInOrder([isA<ReaderLoading>(), isA<ReaderFailure>()]),
      );

      bloc.add(const ReaderFileOpened());
    });

    test('returns to empty when the document is closed', () async {
      final bloc = ReaderBloc(
        _FakeRepository(
          pickResult: r'C:\docs\notas.md',
          document: const MarkdownDocument(
            path: r'C:\docs\notas.md',
            content: '# Notas',
          ),
        ),
      );

      // Wait for the open flow to finish before closing: the bloc runs handlers
      // for different event types concurrently, so dispatching both at once
      // would race.
      bloc.add(const ReaderFileOpened());
      await bloc.stream.firstWhere((state) => state is ReaderLoaded);

      bloc.add(const ReaderFileClosed());
      await bloc.stream.firstWhere((state) => state is ReaderEmpty);

      expect(bloc.state, isA<ReaderEmpty>());
    });
  });

  group('ReaderPage', () {
    testWidgets('shows the empty placeholder on launch', (tester) async {
      await tester.pumpWidget(const MyApp());

      expect(find.text('Leitor de Markdown'), findsOneWidget);
      expect(find.text('Nenhum arquivo aberto'), findsOneWidget);
      // FilledButton.icon builds a private subtype, so match on the label text.
      expect(find.text('Selecionar arquivo'), findsOneWidget);
    });

    testWidgets('renders the document and closes it', (tester) async {
      final bloc = ReaderBloc(
        _FakeRepository(
          pickResult: r'C:\docs\guia.md',
          document: const MarkdownDocument(
            path: r'C:\docs\guia.md',
            content: '# Guia\n\nConteúdo de exemplo.',
          ),
        ),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(value: bloc, child: const ReaderPage()),
        ),
      );

      // Drive the open flow without pumpAndSettle, which would hang on the
      // indeterminate progress spinner.
      bloc.add(const ReaderFileOpened());
      await tester.pump(); // deliver the event -> Loading
      await tester.pump(const Duration(milliseconds: 50)); // futures resolve
      await tester.pump(); // rebuild with Loaded

      expect(find.byType(MarkdownView), findsOneWidget);
      expect(find.text('guia.md'), findsOneWidget); // file name in the app bar

      // Close the document via the app-bar action.
      await tester.tap(find.byTooltip('Fechar arquivo'));
      await tester.pump();

      expect(find.byType(MarkdownView), findsNothing);
      expect(find.text('Nenhum arquivo aberto'), findsOneWidget);
    });
  });
}
