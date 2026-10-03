import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart'
    show MermaidDiagram, MermaidParser;
import 'package:markdown/markdown.dart' as md;

import 'flowchart/flowchart_diagram.dart';
import 'flowchart/flowchart_parser.dart';

/// Replaces ```mermaid fenced code blocks with natively rendered diagrams.
///
/// Registered under the `code` tag of [Markdown.builders]. Returning `null`
/// keeps flutter_markdown's default rendering, so inline code spans and
/// regular code blocks stay untouched.
///
/// Flowcharts (`flowchart` / `graph`) go through the in-house renderer in
/// `flowchart/`, which handles subgraphs, multi-line labels and orthogonal
/// edges; the other diagram types are drawn by flutter_mermaid.
class MermaidElementBuilder extends MarkdownElementBuilder {
  static final RegExp _flowchartHeader = RegExp(
    r'^\s*(?:graph|flowchart(?:-elk)?)(?=\s|;|$)',
    caseSensitive: false,
    multiLine: true,
  );

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.attributes['class'] != 'language-mermaid') return null;

    final code = element.textContent;
    if (_isFlowchart(code)) {
      final chart = const FlowchartParser().parse(code);
      if (chart == null) return null;
      return _fitted(FlowchartDiagram(chart: chart));
    }

    if (!_canRender(code)) return null;
    return _fitted(MermaidDiagram(code: code));
  }

  /// Diagrams are laid out at a width driven by their content (rank count,
  /// label lengths), ignoring the space they are actually given. FittedBox
  /// scales that natural-size render down to fit the available width instead
  /// of letting it overflow the reading column.
  Widget _fitted(Widget diagram) => Padding(
        padding: const EdgeInsets.all(16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: diagram,
        ),
      );

  /// Whether the first statement (after front matter, directives and
  /// comments) declares a flowchart.
  bool _isFlowchart(String code) {
    final lines = code
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('%%'))
        .toList();
    if (lines.isNotEmpty && lines.first == '---') {
      final close = lines.indexOf('---', 1);
      if (close > 0) lines.removeRange(0, close + 1);
    }
    return lines.isNotEmpty && _flowchartHeader.hasMatch(lines.first);
  }

  /// flutter_mermaid covers only part of the Mermaid grammar (sequence, pie,
  /// gantt, timeline, kanban, radar and XY chart besides flowcharts). Probe
  /// its parser first so unsupported or malformed diagrams degrade to the
  /// regular code block instead of an error box.
  bool _canRender(String code) {
    try {
      return const MermaidParser().parse(code) != null;
    } catch (_) {
      return false;
    }
  }
}
