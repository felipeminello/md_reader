import 'package:flutter/material.dart';

import 'flowchart.dart';
import 'flowchart_layout.dart';
import 'flowchart_painter.dart';

/// Draws a parsed Mermaid [Flowchart] at its natural size.
///
/// Text is measured with the surrounding font so the layout matches what is
/// painted. The layout is cached and only recomputed when the chart or the
/// text styles change.
class FlowchartDiagram extends StatefulWidget {
  const FlowchartDiagram({super.key, required this.chart});

  final Flowchart chart;

  @override
  State<FlowchartDiagram> createState() => _FlowchartDiagramState();
}

class _FlowchartDiagramState extends State<FlowchartDiagram> {
  FlowchartLayout? _layout;
  FlowchartTextStyles? _styles;

  @override
  void didUpdateWidget(FlowchartDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chart != widget.chart) _layout = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = FlowchartTextStyles.from(
      theme.textTheme.bodyMedium ?? DefaultTextStyle.of(context).style,
    );
    if (_layout == null || styles != _styles) {
      _styles = styles;
      _layout = FlowchartLayout.compute(widget.chart, styles.measure);
    }
    final layout = _layout!;

    return CustomPaint(
      size: layout.size,
      painter: FlowchartPainter(
        chart: widget.chart,
        layout: layout,
        styles: styles,
        palette: FlowchartPalette.of(theme.brightness),
      ),
    );
  }
}
