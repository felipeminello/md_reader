import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/find_bloc.dart';
import '../../bloc/find_event.dart';
import '../../bloc/find_state.dart';

/// The floating *Localizar* bar: a search field, the result counter and
/// buttons to step through the occurrences or close the bar.
///
/// Enter goes to the next occurrence, Shift+Enter to the previous one and Esc
/// closes the bar. It only dispatches [FindEvent]s; the [FindBloc] searches.
class FindBar extends StatefulWidget {
  const FindBar({super.key});

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode(debugLabel: 'FindBar');

  @override
  void initState() {
    super.initState();
    // Start from the last search, selected so typing replaces it.
    final query = context.read<FindBloc>().state.query;
    _controller = TextEditingController(text: query)
      ..selection = TextSelection(baseOffset: 0, extentOffset: query.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _add(FindEvent event) => context.read<FindBloc>().add(event);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocConsumer<FindBloc, FindState>(
      // Cmd+F / Ctrl+F while the bar is already open: take the focus back
      // and select the term, like a browser does.
      listenWhen: (previous, current) =>
          current.focusRequests != previous.focusRequests,
      listener: (context, state) {
        _focusNode.requestFocus();
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      },
      builder: (context, state) {
        final hasMatches = state.matchCount > 0;
        return Material(
          elevation: 3,
          color: colorScheme.surfaceContainerHigh,
          shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 220,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): () =>
                          _add(const FindNextRequested()),
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        shift: true,
                      ): () => _add(const FindPreviousRequested()),
                      const SingleActivator(LogicalKeyboardKey.escape): () =>
                          _add(const FindClosed()),
                    },
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      style: theme.textTheme.bodyMedium,
                      decoration: const InputDecoration(
                        hintText: 'Localizar no documento',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (query) => _add(FindQueryChanged(query)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72),
                  child: Text(
                    _resultLabel(state),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: state.query.isNotEmpty && !hasMatches
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 20,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: colorScheme.outlineVariant,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: 'Resultado anterior (Shift+Enter)',
                  visualDensity: VisualDensity.compact,
                  onPressed: hasMatches
                      ? () => _add(const FindPreviousRequested())
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: 'Próximo resultado (Enter)',
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      hasMatches ? () => _add(const FindNextRequested()) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Fechar busca (Esc)',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _add(const FindClosed()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// "3 de 12" while there are results, "Nenhum resultado" when the term is
  /// not found, and nothing before the user types.
  String _resultLabel(FindState state) {
    if (state.query.isEmpty) return '';
    if (state.matchCount == 0) return 'Nenhum resultado';
    return '${state.currentIndex + 1} de ${state.matchCount}';
  }
}
