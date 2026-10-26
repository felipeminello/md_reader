import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/find_bloc.dart';
import '../../bloc/find_event.dart';
import '../../bloc/find_state.dart';
import '../../data/text_search.dart';

/// Makes the rendered document below it searchable by the [FindBloc].
///
/// It reads the text actually on screen (every [RenderParagraph] under
/// [child], in reading order) instead of the Markdown source, so offsets in a
/// [TextMatch] map straight to glyphs. It then paints a highlight over every
/// occurrence and scrolls the current one into view. Must sit inside the
/// document's scroll view, so the highlights scroll along with the text.
class FindHighlighter extends StatefulWidget {
  const FindHighlighter({super.key, required this.child});

  final Widget child;

  @override
  State<FindHighlighter> createState() => _FindHighlighterState();
}

class _FindHighlighterState extends State<FindHighlighter> {
  final GlobalKey _contentKey = GlobalKey();

  /// Repaints the highlights when a nested scrollable (a wide code block)
  /// scrolls sideways, since that moves the text without relaying us out.
  final ValueNotifier<int> _nestedScroll = ValueNotifier(0);

  /// The paragraphs whose text was last sent with [FindContentChanged]; a
  /// [TextMatch.segment] indexes into this list.
  List<RenderParagraph> _paragraphs = const [];
  List<String> _segments = const [];

  @override
  void initState() {
    super.initState();
    _scheduleIndexing();
  }

  @override
  void didUpdateWidget(FindHighlighter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new document or theme rebuilds the text, possibly into new paragraphs.
    _scheduleIndexing();
  }

  @override
  void dispose() {
    _nestedScroll.dispose();
    super.dispose();
  }

  void _scheduleIndexing() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _index());
  }

  /// Collects the paragraphs laid out under [FindHighlighter.child] and
  /// reports their text to the [FindBloc].
  void _index() {
    if (!mounted) return;
    final root = _contentKey.currentContext?.findRenderObject();
    if (root == null) return;

    final paragraphs = <RenderParagraph>[];
    void collect(RenderObject node) {
      if (node is RenderParagraph) paragraphs.add(node);
      node.visitChildren(collect);
    }

    collect(root);
    final segments = [
      for (final paragraph in paragraphs)
        // Placeholders (inline widgets) stay in as one character each, so
        // offsets line up with the paragraph's own text positions.
        paragraph.text.toPlainText(includeSemanticsLabels: false),
    ];

    setState(() => _paragraphs = paragraphs);
    if (!listEquals(segments, _segments)) {
      _segments = segments;
      context.read<FindBloc>().add(FindContentChanged(segments));
    }
  }

  /// Scrolls every enclosing scrollable so [match] is visible, with some room
  /// above and below it. Does nothing if it already is.
  void _reveal(TextMatch match) {
    final paragraph = _paragraphFor(match);
    if (paragraph == null) return;
    final boxes = _boxesOf(paragraph, match);
    if (boxes.isEmpty) return;

    final rect = boxes.reduce((a, b) => a.expandToInclude(b));
    paragraph.showOnScreen(
      rect: Rect.fromLTRB(
        rect.left - 24,
        rect.top - 96,
        rect.right + 24,
        rect.bottom + 96,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  RenderParagraph? _paragraphFor(TextMatch match) {
    if (match.segment >= _paragraphs.length) return null;
    final paragraph = _paragraphs[match.segment];
    return paragraph.attached ? paragraph : null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FindBloc, FindState>(
      listenWhen: (previous, current) =>
          current.isOpen && !previous.isOpen ||
          current.revealRequests != previous.revealRequests,
      listener: (context, state) {
        // The text may have changed since it was indexed (an image that
        // failed to load shows its alt text instead), so refresh on open.
        if (state.isOpen) _index();
        final match = state.currentMatch;
        if (match != null) _reveal(match);
      },
      buildWhen: (previous, current) =>
          !listEquals(previous.matches, current.matches) ||
          previous.currentIndex != current.currentIndex,
      builder: (context, state) {
        return NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _nestedScroll.value++;
            return false;
          },
          child: CustomPaint(
            foregroundPainter: _HighlightPainter(
              contentKey: _contentKey,
              paragraphs: _paragraphs,
              matches: state.matches,
              currentIndex: state.currentIndex,
              repaint: _nestedScroll,
            ),
            child: KeyedSubtree(key: _contentKey, child: widget.child),
          ),
        );
      },
    );
  }
}

/// Boxes covering [match] in [paragraph]'s own coordinates, one per line it
/// spans.
List<Rect> _boxesOf(RenderParagraph paragraph, TextMatch match) {
  return [
    for (final box in paragraph.getBoxesForSelection(
      TextSelection(baseOffset: match.start, extentOffset: match.end),
    ))
      box.toRect(),
  ];
}

/// Paints a translucent marker over every occurrence, a stronger one over the
/// current occurrence — the same convention as a browser's *Find*.
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.contentKey,
    required this.paragraphs,
    required this.matches,
    required this.currentIndex,
    required super.repaint,
  });

  static const Color _matchColor = Color(0x80FFD54F);
  static const Color _currentColor = Color(0xA6FF9100);

  final GlobalKey contentKey;
  final List<RenderParagraph> paragraphs;
  final List<TextMatch> matches;
  final int currentIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (matches.isEmpty) return;
    final content = contentKey.currentContext?.findRenderObject();
    if (content is! RenderBox || !content.attached) return;

    final matchPaint = Paint()..color = _matchColor;
    final currentPaint = Paint()..color = _currentColor;

    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      if (match.segment >= paragraphs.length) continue;
      final paragraph = paragraphs[match.segment];
      if (!paragraph.attached) continue;

      final transform = paragraph.getTransformTo(content);
      final clip = _visibleArea(paragraph, content);
      for (final box in _boxesOf(paragraph, match)) {
        final rect = MatrixUtils.transformRect(transform, box).intersect(clip);
        if (rect.width <= 0 || rect.height <= 0) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          i == currentIndex ? currentPaint : matchPaint,
        );
      }
    }
  }

  /// The part of [content] where [paragraph] can show, in [content]'s
  /// coordinates: text scrolled out of a nested viewport (a code block wider
  /// than the window) is clipped there, so its highlight must be too.
  Rect _visibleArea(RenderParagraph paragraph, RenderBox content) {
    var area = Rect.largest;
    for (var node = paragraph.parent;
        node != null && node != content;
        node = node.parent) {
      if (node is RenderBox && node is RenderAbstractViewport) {
        area = area.intersect(
          MatrixUtils.transformRect(
            node.getTransformTo(content),
            Offset.zero & node.size,
          ),
        );
      }
    }
    return area;
  }

  @override
  bool shouldRepaint(_HighlightPainter oldDelegate) =>
      !identical(oldDelegate.paragraphs, paragraphs) ||
      !listEquals(oldDelegate.matches, matches) ||
      oldDelegate.currentIndex != currentIndex;
}
