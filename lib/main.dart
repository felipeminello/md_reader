import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'reader/bloc/reader_bloc.dart';
import 'reader/data/markdown_repository.dart';
import 'reader/presentation/reader_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Leitor de Markdown',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // Dependency injection: the repository is provided once and handed to the
      // Bloc, which is the only thing the UI talks to.
      home: RepositoryProvider(
        create: (_) => const MarkdownRepository(),
        child: BlocProvider(
          create: (context) => ReaderBloc(context.read<MarkdownRepository>()),
          child: const ReaderPage(),
        ),
      ),
    );
  }
}
