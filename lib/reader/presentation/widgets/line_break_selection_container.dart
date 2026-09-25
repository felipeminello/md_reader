import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Groups every selectable text below it into one selection whose copied text
/// keeps the document's line structure.
///
/// Flutter's default selection delegate concatenates the text of each
/// selected block with no separator, so copying paragraphs, headings and list
/// items yields one run-on line. This container inserts separators based on
/// where each block sits on screen instead.
class LineBreakSelectionContainer extends StatefulWidget {
  const LineBreakSelectionContainer({super.key, required this.child});

  final Widget child;

  @override
  State<LineBreakSelectionContainer> createState() =>
      _LineBreakSelectionContainerState();
}

class _LineBreakSelectionContainerState
    extends State<LineBreakSelectionContainer> {
  final _LineBreakSelectionDelegate _delegate = _LineBreakSelectionDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(delegate: _delegate, child: widget.child);
  }
}

/// Joins the selected text of consecutive selectables with:
/// - nothing, when both are fragments of the same paragraph;
/// - a tab, when they sit side by side on the same row (a list bullet and
///   its item, or the cells of a table row);
/// - a line break, when the next one starts below the previous one.
class _LineBreakSelectionDelegate extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final buffer = StringBuffer();
    Rect? previous;
    var hasContent = false;

    // `selectables` is already sorted in reading order.
    for (final selectable in selectables) {
      final content = selectable.getSelectedContent();
      if (content == null) continue;

      final bounds = MatrixUtils.transformRect(
        selectable.getTransformTo(null),
        Offset.zero & selectable.size,
      );
      if (previous != null && bounds != previous) {
        buffer.write(bounds.top >= previous.bottom - 0.5 ? '\n' : '\t');
      }
      buffer.write(content.plainText);
      previous = bounds;
      hasContent = true;
    }

    return hasContent ? SelectedContent(plainText: buffer.toString()) : null;
  }
}
