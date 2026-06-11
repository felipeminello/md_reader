import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../data/markdown_document.dart';
import 'mermaid_element_builder.dart';

/// Renders the contents of a [MarkdownDocument] as formatted, scrollable,
/// selectable text. Fenced ```mermaid blocks are rendered as diagrams by
/// [MermaidElementBuilder].
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.document});

  final MarkdownDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surfaceContainerHighest;

    return Markdown(
      data: document.content,
      selectable: true,
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
      builders: {'code': MermaidElementBuilder()},
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        code: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          backgroundColor: surface,
        ),
        codeblockDecoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(4),
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 4),
          ),
        ),
      ),
    );
  }
}
