// Tests for the Markdown reader.
//
// The Bloc is exercised against a fake repository so the file picker and the
// real file system are never touched, and the widget layer is checked for the
// empty/loaded/close behaviour.

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_erdiagram/mermaid_erdiagram.dart' show MermaidErDiagram;
import 'package:mermaid_flowchart/mermaid_flowchart.dart' show MermaidFlowchart;

import 'package:md_reader/main.dart';
import 'package:md_reader/reader/bloc/find_bloc.dart';
import 'package:md_reader/reader/bloc/find_event.dart';
import 'package:md_reader/reader/bloc/find_state.dart';
import 'package:md_reader/reader/bloc/reader_bloc.dart';
import 'package:md_reader/reader/bloc/reader_event.dart';
import 'package:md_reader/reader/bloc/reader_state.dart';
import 'package:md_reader/reader/data/markdown_document.dart';
import 'package:md_reader/reader/data/markdown_repository.dart';
import 'package:md_reader/reader/data/system_file_opener.dart';
import 'package:md_reader/reader/data/text_search.dart';
import 'package:md_reader/reader/presentation/reader_page.dart';
import 'package:md_reader/reader/presentation/widgets/find_bar.dart';
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

  @override
  bool isMarkdownPath(String path) {
    final extension = path.split('.').last.toLowerCase();
    return MarkdownRepository.allowedExtensions.contains(extension);
  }
}

/// Stands in for the macOS `AppDelegate`: answers `getInitialFile` and can
/// push `openFile` calls as if Finder had handed the app a document.
class _FakeOpenChannel {
  _FakeOpenChannel({this.initialFile});

  final String? initialFile;

  final channel = const MethodChannel(SystemFileOpener.channelName);

  /// Installs the fake native side for the duration of the test.
  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return call.method == 'getInitialFile' ? initialFile : null;
    });
  }

  /// Simulates macOS opening a file while the app is already running.
  Future<void> sendOpenFile(String path) async {
    ServicesBinding.instance.channelBuffers.push(
      SystemFileOpener.channelName,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('openFile', path)),
      (_) {},
    );
    // Let the buffered message reach the handler.
    await Future<void>.delayed(Duration.zero);
  }
}

/// A [SystemFileOpener] backed by a fake native side that reports
/// [initialFile] as the launch document.
SystemFileOpener _fakeOpener({required String? initialFile}) {
  final fake = _FakeOpenChannel(initialFile: initialFile)..install();
  return SystemFileOpener(channel: fake.channel);
}

/// [view] inside an app with the [FindBloc] that [MarkdownView] searches with.
Widget _viewApp(Widget view, {FindBloc? findBloc}) {
  return MaterialApp(
    home: BlocProvider(
      create: (_) => findBloc ?? FindBloc(),
      child: Scaffold(body: view),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Keep a fake native side from leaking into the next test.
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(SystemFileOpener.channelName),
      null,
    );
  });

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

    test('emits [Loading, Loaded] when a supported file is dropped', () {
      final bloc = ReaderBloc(
        _FakeRepository(
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

      bloc.add(const ReaderFileDropped(r'C:\docs\notas.md'));
    });

    test('emits a failure without reading when a dropped file is unsupported',
        () async {
      final bloc = ReaderBloc(_FakeRepository());

      expectLater(bloc.stream, emits(isA<ReaderFailure>()));

      bloc.add(const ReaderFileDropped(r'C:\docs\imagem.png'));
    });

    test('opens the file the OS launched the app with', () {
      final bloc = ReaderBloc(
        _FakeRepository(
          document: const MarkdownDocument(
            path: '/Users/ana/notas.md',
            content: '# Notas',
          ),
        ),
        systemFileOpener: _fakeOpener(initialFile: '/Users/ana/notas.md'),
      );
      addTearDown(bloc.close);

      expectLater(
        bloc.stream,
        emitsInOrder([isA<ReaderLoading>(), isA<ReaderLoaded>()]),
      );
    });

    test('opens files the OS sends while the app is running', () async {
      // Installed with no launch file, so only the pushed one is read.
      final channel = _FakeOpenChannel()..install();
      final bloc = ReaderBloc(
        _FakeRepository(
          document: const MarkdownDocument(
            path: '/Users/ana/guia.md',
            content: '# Guia',
          ),
        ),
        systemFileOpener: SystemFileOpener(channel: channel.channel),
      );
      addTearDown(bloc.close);

      // Let `start()` resolve so the handler is registered before we push.
      await Future<void>.delayed(Duration.zero);

      expectLater(
        bloc.stream,
        emitsInOrder([isA<ReaderLoading>(), isA<ReaderLoaded>()]),
      );

      await channel.sendOpenFile('/Users/ana/guia.md');
    });

    test('emits a failure when the OS sends an unsupported file', () {
      final bloc = ReaderBloc(
        _FakeRepository(),
        systemFileOpener: _fakeOpener(initialFile: '/Users/ana/imagem.png'),
      );
      addTearDown(bloc.close);

      expectLater(bloc.stream, emits(isA<ReaderFailure>()));
    });

    test('stays empty when the OS launched the app without a file', () async {
      final bloc = ReaderBloc(
        _FakeRepository(),
        systemFileOpener: _fakeOpener(initialFile: null),
      );
      addTearDown(bloc.close);

      await Future<void>.delayed(Duration.zero);

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
      // The empty screen accepts files dropped from the OS file explorer.
      expect(find.byType(DropTarget), findsOneWidget);
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
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: bloc),
              BlocProvider(create: (_) => FindBloc()),
            ],
            child: const ReaderPage(),
          ),
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

  group('MarkdownView – Mermaid', () {
    Future<void> pumpView(WidgetTester tester, String content) {
      return tester.pumpWidget(
        _viewApp(
          MarkdownView(
            document:
                MarkdownDocument(path: r'C:\docs\doc.md', content: content),
          ),
        ),
      );
    }

    testWidgets('renders a flowchart with mermaid_flowchart', (tester) async {
      await pumpView(tester, '''
# Fluxo

```mermaid
graph TD
  A[Início] --> B{Decisão}
  B -->|Sim| C[OK]
  B -->|Não| D[Cancelar]
```
''');
      await tester.pump();

      expect(find.byType(MermaidFlowchart), findsOneWidget);
      expect(find.byType(MermaidDiagram), findsNothing);
      // The diagram replaces the raw source text.
      expect(find.textContaining('graph TD'), findsNothing);
    });

    testWidgets('renders flowcharts with subgraphs and subgraph edges',
        (tester) async {
      await pumpView(tester, '''
```mermaid
flowchart LR
  CF["Cloudflare"] --> NG["NGINX"]
  subgraph APP["Instância de aplicação"]
    NG --> API["API<br/>2 workers"]
  end
  subgraph OBS["Logs"]
    OS["OpenSearch"]
  end
  APP -.->|Fluent Bit| OS
  API --> DB[("Postgres")]
```
''');
      await tester.pump();

      expect(find.byType(MermaidFlowchart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders an ER diagram with mermaid_erdiagram', (tester) async {
      await pumpView(tester, '''
```mermaid
erDiagram
  CUSTOMER ||--o{ ORDER : places
  ORDER ||--|{ LINE-ITEM : contains
  CUSTOMER {
    string name
    string custNumber PK
  }
```
''');
      await tester.pump();

      expect(find.byType(MermaidErDiagram), findsOneWidget);
      expect(find.byType(MermaidDiagram), findsNothing);
      expect(find.byType(MermaidFlowchart), findsNothing);
      expect(find.textContaining('erDiagram'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders other diagram types with flutter_mermaid',
        (tester) async {
      await pumpView(tester, '''
```mermaid
pie
  title Pets
  "Dogs" : 386
  "Cats" : 85
```
''');
      await tester.pump();

      expect(find.byType(MermaidDiagram), findsOneWidget);
      expect(find.byType(MermaidFlowchart), findsNothing);
    });

    testWidgets('falls back to a code block for unsupported diagram types',
        (tester) async {
      await pumpView(tester, '''
```mermaid
classDiagram
  Animal <|-- Duck
```
''');
      await tester.pump();

      expect(find.byType(MermaidDiagram), findsNothing);
      expect(find.byType(MermaidFlowchart), findsNothing);
      expect(find.byType(MermaidErDiagram), findsNothing);
      expect(find.textContaining('classDiagram'), findsOneWidget);
    });

    testWidgets('leaves regular and inline code untouched', (tester) async {
      await pumpView(tester, '''
Use o comando `flutter run` para iniciar.

```dart
void main() {}
```
''');
      await tester.pump();

      expect(find.byType(MermaidDiagram), findsNothing);
      expect(find.textContaining('flutter run'), findsOneWidget);
      expect(find.textContaining('void main() {}'), findsOneWidget);
    });
  });

  group('MarkdownDocument.resolveImageUri', () {
    Uri resolve(String documentPath, String source) =>
        MarkdownDocument(path: documentPath, content: '')
            .resolveImageUri(Uri.parse(source));

    test('keeps remote and inline URIs untouched', () {
      const doc = r'C:\docs\doc.md';
      expect(resolve(doc, 'https://example.com/a.png'),
          Uri.parse('https://example.com/a.png'));
      expect(resolve(doc, 'data:image/png;base64,AAAA').scheme, 'data');
    });

    test('resolves relative paths against a Windows document folder', () {
      final uri = resolve(r'C:\My Docs\notes\doc.md', 'img/foto%201.png');
      expect(uri.toFilePath(windows: true), r'C:\My Docs\notes\img\foto 1.png');

      final parent = resolve(r'C:\My Docs\notes\doc.md', '../logo.png');
      expect(parent.toFilePath(windows: true), r'C:\My Docs\logo.png');
    });

    test('resolves relative paths against a POSIX document folder', () {
      final uri = resolve('/Users/ana/notes/doc.md', './img/a.png');
      expect(uri.toFilePath(windows: false), '/Users/ana/notes/img/a.png');
    });

    test('turns Windows absolute paths into file URIs', () {
      final uri = resolve(r'C:\docs\doc.md', r'D:\imagens\a.png');
      expect(uri.scheme, 'file');
      expect(uri.toFilePath(windows: true), r'D:\imagens\a.png');
    });
  });

  group('MarkdownView – images', () {
    testWidgets('loads relative images from the document folder',
        (tester) async {
      await tester.pumpWidget(
        _viewApp(
          const MarkdownView(
            document: MarkdownDocument(
              path: r'C:\docs\doc.md',
              content: '![Diagrama](img/diagrama.png)',
            ),
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<FileImage>());
      expect(
        (image.image as FileImage).file.path.replaceAll(r'\', '/'),
        endsWith('docs/img/diagrama.png'),
      );
      expect(image.semanticLabel, 'Diagrama');
    });

    testWidgets('shows the alt text when an image cannot be loaded',
        (tester) async {
      await tester.pumpWidget(
        _viewApp(
          const MarkdownView(
            document: MarkdownDocument(
              path: r'C:\docs\doc.md',
              content: '![Logo ausente](ftp://example.com/logo.png)',
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('Logo ausente'), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });
  });

  group('MarkdownView – selection', () {
    testWidgets('copying the whole document keeps line breaks', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        _viewApp(
          const MarkdownView(
            document: MarkdownDocument(
              path: r'C:\docs\doc.md',
              content: '# Título\n\n'
                  'Primeiro parágrafo.\n\n'
                  'Segundo parágrafo.\n\n'
                  '- item a\n'
                  '- item b\n\n'
                  '```\nlinha 1\nlinha 2\n```\n',
            ),
          ),
        ),
      );

      // Focus the selection area, then select all and copy via keyboard.
      await tester.tap(find.text('Primeiro parágrafo.'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(
        copied,
        'Título\n'
        'Primeiro parágrafo.\n'
        'Segundo parágrafo.\n'
        '•\titem a\n'
        '•\titem b\n'
        'linha 1\nlinha 2',
      );
    });
  });
  group('TextSearch', () {
    test('ignores case and accents', () {
      expect(
        TextSearch.findAll(['Ação e ACAO', 'sem nada'], 'acao'),
        const [
          TextMatch(segment: 0, start: 0, end: 4),
          TextMatch(segment: 0, start: 7, end: 11),
        ],
      );
    });

    test('finds non-overlapping matches across segments in order', () {
      expect(
        TextSearch.findAll(['aaaa', 'xa'], 'aa'),
        const [
          TextMatch(segment: 0, start: 0, end: 2),
          TextMatch(segment: 0, start: 2, end: 4),
        ],
      );
      expect(TextSearch.findAll(['abc', 'cab'], 'ab').map((m) => m.segment),
          [0, 1]);
    });

    test('an empty query matches nothing', () {
      expect(TextSearch.findAll(['abc'], ''), isEmpty);
    });
  });

  group('FindBloc', () {
    Future<FindBloc> openWith(List<String> segments) async {
      final bloc = FindBloc()
        ..add(FindContentChanged(segments))
        ..add(const FindOpened());
      await bloc.stream.firstWhere((state) => state.isOpen);
      return bloc;
    }

    test('starts closed', () {
      expect(FindBloc().state.isOpen, isFalse);
    });

    test('goes to the first match when the query changes', () async {
      final bloc = await openWith(['um dois um', 'um']);
      addTearDown(bloc.close);

      bloc.add(const FindQueryChanged('um'));
      final state = await bloc.stream.first;

      expect(state.matchCount, 3);
      expect(state.currentIndex, 0);
      expect(state.currentMatch, const TextMatch(segment: 0, start: 0, end: 2));
    });

    test('next and previous wrap around', () async {
      final bloc = await openWith(['x x x']);
      addTearDown(bloc.close);
      bloc.add(const FindQueryChanged('x'));
      await bloc.stream.first;

      bloc.add(const FindPreviousRequested());
      expect((await bloc.stream.first).currentIndex, 2);
      bloc.add(const FindNextRequested());
      expect((await bloc.stream.first).currentIndex, 0);
      bloc.add(const FindNextRequested());
      expect((await bloc.stream.first).currentIndex, 1);
    });

    test('"next" with a single match still asks to reveal it', () async {
      final bloc = await openWith(['único']);
      addTearDown(bloc.close);
      bloc.add(const FindQueryChanged('único'));
      final before = await bloc.stream.first;

      bloc.add(const FindNextRequested());
      final after = await bloc.stream.first;

      expect(after.currentIndex, 0);
      expect(after.revealRequests, before.revealRequests + 1);
    });

    test('closing clears the matches but keeps the query for next time',
        () async {
      final bloc = await openWith(['abc abc']);
      addTearDown(bloc.close);
      bloc.add(const FindQueryChanged('abc'));
      await bloc.stream.first;

      bloc.add(const FindClosed());
      final closed = await bloc.stream.first;
      expect(closed.isOpen, isFalse);
      expect(closed.matches, isEmpty);
      expect(closed.query, 'abc');

      bloc.add(const FindOpened());
      final reopened = await bloc.stream.first;
      expect(reopened.matchCount, 2);
      expect(reopened.currentIndex, 0);
    });

    test('searches again when the document content changes', () async {
      final bloc = await openWith(['abc']);
      addTearDown(bloc.close);
      bloc.add(const FindQueryChanged('abc'));
      await bloc.stream.first;

      bloc.add(const FindContentChanged(['abc', 'abc', 'abc']));
      expect((await bloc.stream.first).matchCount, 3);
    });
  });

  group('ReaderPage – find', () {
    Future<(ReaderBloc, FindBloc)> pumpLoaded(
      WidgetTester tester,
      String content,
    ) async {
      final readerBloc = ReaderBloc(
        _FakeRepository(
          pickResult: r'C:\docs\guia.md',
          document:
              MarkdownDocument(path: r'C:\docs\guia.md', content: content),
        ),
      );
      final findBloc = FindBloc();
      addTearDown(readerBloc.close);
      addTearDown(findBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: readerBloc),
              BlocProvider.value(value: findBloc),
            ],
            child: const ReaderPage(),
          ),
        ),
      );
      readerBloc.add(const ReaderFileOpened());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(); // Loaded
      await tester.pump(); // post-frame indexing reaches the FindBloc
      return (readerBloc, findBloc);
    }

    testWidgets('the magnifier opens the bar and counts the results',
        (tester) async {
      await pumpLoaded(
        tester,
        '# Guia\n\nUm exemplo. Outro Exemplo.\n\n- mais um exemplo',
      );

      expect(find.byType(FindBar), findsNothing);
      await tester.tap(find.byTooltip('Localizar (Ctrl+F)'));
      await tester.pump();
      expect(find.byType(FindBar), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'exemplo');
      await tester.pump();
      expect(find.text('1 de 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Próximo resultado (Enter)'));
      await tester.pump();
      expect(find.text('2 de 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Resultado anterior (Shift+Enter)'));
      await tester.tap(find.byTooltip('Resultado anterior (Shift+Enter)'));
      await tester.pump();
      expect(find.text('3 de 3'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'inexistente');
      await tester.pump();
      expect(find.text('Nenhum resultado'), findsOneWidget);
    });

    testWidgets('Ctrl+F opens the bar, Enter steps and Esc closes it',
        (tester) async {
      await pumpLoaded(tester, 'abc abc abc');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.byType(FindBar), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('2 de 3'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(find.text('1 de 3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(FindBar), findsNothing);
    });

    testWidgets('scrolls to the first match', (tester) async {
      final filler = List.generate(80, (i) => 'Parágrafo $i.').join('\n\n');
      await pumpLoaded(tester, '$filler\n\nO tesouro está aqui.');

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(MarkdownView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.pixels, 0);

      await tester.tap(find.byTooltip('Localizar (Ctrl+F)'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'tesouro');
      await tester.pumpAndSettle();

      expect(find.text('1 de 1'), findsOneWidget);
      expect(scrollable.position.pixels, greaterThan(0));
      final match = tester.getRect(find.textContaining('O tesouro'));
      final viewport = tester.getRect(find.byType(MarkdownView));
      expect(viewport.contains(match.center), isTrue);
    });

    testWidgets('closing the document closes the bar', (tester) async {
      final (_, findBloc) = await pumpLoaded(tester, 'texto');
      await tester.tap(find.byTooltip('Localizar (Ctrl+F)'));
      await tester.pump();
      expect(find.byType(FindBar), findsOneWidget);

      await tester.tap(find.byTooltip('Fechar arquivo'));
      await tester.pump();

      expect(find.byType(FindBar), findsNothing);
      expect(findBloc.state,
          isA<FindState>().having((s) => s.isOpen, 'isOpen', false));
    });
  });
}
