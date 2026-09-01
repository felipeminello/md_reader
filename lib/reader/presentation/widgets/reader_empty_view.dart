import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/reader_bloc.dart';
import '../../bloc/reader_event.dart';

/// Placeholder shown when no document is open. Its button is the primary
/// entry point for picking a file, and the whole screen also accepts a
/// Markdown file dropped from the OS file explorer.
class ReaderEmptyView extends StatefulWidget {
  const ReaderEmptyView({super.key});

  @override
  State<ReaderEmptyView> createState() => _ReaderEmptyViewState();
}

class _ReaderEmptyViewState extends State<ReaderEmptyView> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        if (details.files.isEmpty) return;
        context
            .read<ReaderBloc>()
            .add(ReaderFileDropped(details.files.first.path));
      },
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                vertical: 56,
                horizontal: 40,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: _isDragging
                    ? colorScheme.primaryContainer.withValues(alpha: 0.25)
                    : null,
                border: Border.all(
                  color: _isDragging
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  width: _isDragging ? 2 : 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primaryContainer,
                    ),
                    child: Icon(
                      _isDragging
                          ? Icons.file_download_outlined
                          : Icons.description_outlined,
                      size: 40,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isDragging
                        ? 'Solte o arquivo aqui'
                        : 'Nenhum arquivo aberto',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Selecione ou arraste um arquivo Markdown (.md) do seu '
                    'computador para visualizá-lo aqui.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: () => context
                        .read<ReaderBloc>()
                        .add(const ReaderFileOpened()),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Selecionar arquivo'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
