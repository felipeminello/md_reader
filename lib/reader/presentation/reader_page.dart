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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<ReaderBloc, ReaderState>(
          builder: (context, state) {
            if (state is! ReaderLoaded) {
              return const Text('Leitor de Markdown');
            }
            final document = state.document;
            final folder = _parentFolder(document.path);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.fileName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (folder != null)
                  Text(
                    folder,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            );
          },
        ),
        actions: [
          BlocBuilder<ReaderBloc, ReaderState>(
            builder: (context, state) {
              if (state is! ReaderLoaded) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.folder_open_outlined),
                      tooltip: 'Abrir outro arquivo',
                      onPressed: () => context
                          .read<ReaderBloc>()
                          .add(const ReaderFileOpened()),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Fechar arquivo',
                      onPressed: () => context
                          .read<ReaderBloc>()
                          .add(const ReaderFileClosed()),
                    ),
                  ],
                ),
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
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  content: Text(state.message),
                ),
              );
          }
        },
        builder: (context, state) {
          return switch (state) {
            ReaderLoading() => const _LoadingView(),
            ReaderLoaded(:final document) => MarkdownView(document: document),
            ReaderEmpty() || ReaderFailure() => const ReaderEmptyView(),
          };
        },
      ),
    );
  }

  /// The directory containing [path], for the small caption under the file
  /// name. Handles both Windows (`\`) and POSIX (`/`) separators.
  String? _parentFolder(String path) {
    final segments = path.replaceAll('\\', '/').split('/');
    if (segments.length < 2) return null;
    return segments.sublist(0, segments.length - 1).join(' / ');
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 20),
          Text(
            'Carregando documento...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
