import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../data/markdown_document.dart';
import 'mermaid_element_builder.dart';

/// Renders the contents of a [MarkdownDocument] as formatted, scrollable,
/// selectable text, centered in a readable column. Fenced ```mermaid blocks
/// are rendered as diagrams by [MermaidElementBuilder].
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.document});

  final MarkdownDocument document;

  static const double _maxContentWidth = 860;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final codeSurface = colorScheme.surfaceContainerHigh;

    return Container(
      color: colorScheme.surfaceContainerLowest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Markdown(
            data: document.content,
            selectable: true,
            padding: const EdgeInsets.fromLTRB(40, 32, 40, 64),
            builders: {'code': MermaidElementBuilder()},
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
              h1: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
              h2: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
              h3: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              h1Padding: const EdgeInsets.only(top: 24, bottom: 12),
              h2Padding: const EdgeInsets.only(top: 20, bottom: 10),
              h3Padding: const EdgeInsets.only(top: 16, bottom: 8),
              listBullet: theme.textTheme.bodyLarge,
              a: TextStyle(
                color: colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: colorScheme.primary.withValues(alpha: 0.4),
              ),
              code: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                backgroundColor: codeSurface,
                color: colorScheme.onSurface,
              ),
              codeblockPadding: const EdgeInsets.all(16),
              codeblockDecoration: BoxDecoration(
                color: codeSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              blockquotePadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              blockquoteDecoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(8),
                ),
                border: Border(
                  left: BorderSide(color: colorScheme.primary, width: 4),
                ),
              ),
              horizontalRuleDecoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              tableBorder: TableBorder.all(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              tableHead: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              tableCellsPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
