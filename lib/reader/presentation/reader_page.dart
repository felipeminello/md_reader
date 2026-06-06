import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/reader_bloc.dart';
import '../bloc/reader_event.dart';
import '../bloc/reader_state.dart';
import 'widgets/markdown_view.dart';
import 'widgets/reader_empty_view.dart';

/// The single screen of the app. It is intentionally dumb: it only reads
/// [ReaderState] to decide what to show and dispatches [ReaderEvent]s in
/// response to user actions. All logic lives in [ReaderBloc].
class ReaderPage extends StatelessWidget {
  const ReaderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: BlocBuilder<ReaderBloc, ReaderState>(
          builder: (context, state) {
            final title = switch (state) {
              ReaderLoaded(:final document) => document.fileName,
              _ => 'Leitor de Markdown',
            };
            return Text(title);
          },
        ),
        actions: [
          // The close action only exists while a document is open.
          BlocBuilder<ReaderBloc, ReaderState>(
            builder: (context, state) {
              if (state is! ReaderLoaded) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Fechar arquivo',
                onPressed: () =>
                    context.read<ReaderBloc>().add(const ReaderFileClosed()),
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<ReaderBloc, ReaderState>(
        listener: (context, state) {
          if (state is ReaderFailure) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          return switch (state) {
            ReaderLoading() => const Center(child: CircularProgressIndicator()),
            ReaderLoaded(:final document) => MarkdownView(document: document),
            ReaderEmpty() || ReaderFailure() => const ReaderEmptyView(),
          };
        },
      ),
      // Once a document is open, this lets the user swap it for another one.
      floatingActionButton: BlocBuilder<ReaderBloc, ReaderState>(
        builder: (context, state) {
          if (state is! ReaderLoaded) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () =>
                context.read<ReaderBloc>().add(const ReaderFileOpened()),
            icon: const Icon(Icons.folder_open),
            label: const Text('Abrir outro'),
          );
        },
      ),
    );
  }
}
