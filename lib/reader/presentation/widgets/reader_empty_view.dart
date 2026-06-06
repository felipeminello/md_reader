import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/reader_bloc.dart';
import '../../bloc/reader_event.dart';

/// Placeholder shown when no document is open. Its button is the primary
/// entry point for picking a file from the empty state.
class ReaderEmptyView extends StatelessWidget {
  const ReaderEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 96,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('Nenhum arquivo aberto', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Selecione um arquivo Markdown (.md) para visualizá-lo aqui.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () =>
                context.read<ReaderBloc>().add(const ReaderFileOpened()),
            icon: const Icon(Icons.folder_open),
            label: const Text('Selecionar arquivo'),
          ),
        ],
      ),
    );
  }
}
