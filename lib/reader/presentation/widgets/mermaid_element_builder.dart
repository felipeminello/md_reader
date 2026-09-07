import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:markdown/markdown.dart' as md;

/// Replaces ```mermaid fenced code blocks with natively rendered diagrams.
///
/// Registered under the `code` tag of [Markdown.builders]. Returning `null`
/// keeps flutter_markdown's default rendering, so inline code spans and
/// regular code blocks stay untouched.
class MermaidElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.attributes['class'] != 'language-mermaid') return null;

    final code = element.textContent;
    if (!_canRender(code)) return null;

    // MermaidDiagram lays out diagrams like sequence charts at a width
    // driven purely by their content (participant count, label lengths),
    // ignoring the space it is actually given. FittedBox scales that
    // natural-size render down to fit the available width instead of
    // letting it overflow the reading column.
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: MermaidDiagram(code: code),
      ),
    );
  }

  /// The pure-Dart renderer covers only part of the Mermaid grammar
  /// (flowchart, sequence, pie, gantt, timeline, kanban, radar and XY chart).
  /// Probe the parser first so unsupported or malformed diagrams degrade to
  /// the regular code block instead of an error box.
  bool _canRender(String code) {
    try {
      return const MermaidParser().parse(code) != null;
    } catch (_) {
      return false;
    }
  }
}
