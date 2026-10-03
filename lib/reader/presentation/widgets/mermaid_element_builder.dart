import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart'
    show MermaidDiagram, MermaidParser;
import 'package:markdown/markdown.dart' as md;
import 'package:mermaid_flowchart/mermaid_flowchart.dart'
    show FlowchartParser, MermaidFlowchart;

/// Replaces ```mermaid fenced code blocks with natively rendered diagrams.
///
/// Registered under the `code` tag of [Markdown.builders]. Returning `null`
/// keeps flutter_markdown's default rendering, so inline code spans and
/// regular code blocks stay untouched.
///
/// Flowcharts (`flowchart` / `graph`) are drawn by the mermaid_flowchart
/// package, which handles subgraphs, multi-line labels and orthogonal edges;
/// the other diagram types are drawn by flutter_mermaid.
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
    if (FlowchartParser.isFlowchart(code)) {
      final chart = const FlowchartParser().parse(code);
      if (chart == null) return null;
      return _fitted(MermaidFlowchart.chart(chart: chart));
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
