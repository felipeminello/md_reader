import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders an image referenced by a Markdown document.
///
/// [uri] must already be resolved (see `MarkdownDocument.resolveImageUri`):
/// `http`/`https` URLs are downloaded, `data:` URIs are decoded inline and
/// `file:` URIs are read from disk. Raster formats go through [Image]; SVGs,
/// which Flutter cannot decode natively, go through [SvgPicture]. Anything
/// that fails to load degrades to a small placeholder showing the alt text
/// instead of an empty gap.
class MarkdownImage extends StatelessWidget {
  const MarkdownImage({
    super.key,
    required this.uri,
    this.alt,
    this.width,
    this.height,
  });

  final Uri uri;

  /// Alternative text from `![alt](...)`, used for accessibility and the
  /// error placeholder.
  final String? alt;

  /// Explicit size from flutter_markdown's `image.png#WIDTHxHEIGHT` syntax.
  final double? width;
  final double? height;

  bool get _isSvgPath => uri.path.toLowerCase().endsWith('.svg');

  @override
  Widget build(BuildContext context) {
    return switch (uri.scheme) {
      'http' || 'https' => _network(),
      'data' => _data(),
      'file' => _file(),
      _ => _ImageErrorPlaceholder(alt: alt),
    };
  }

  Widget _network() {
    final url = uri.toString();
    final svg = _svg(SvgPicture.network(url, errorBuilder: _svgError));
    if (_isSvgPath) return svg;
    return Image.network(
      url,
      width: width,
      height: height,
      semanticLabel: alt,
      // Many SVGs (e.g. shields.io badges) are served without a `.svg`
      // extension, so a raster decode failure gets one more try as SVG.
      errorBuilder: (context, error, stackTrace) => svg,
    );
  }

  Widget _data() {
    final data = uri.data;
    if (data == null || !data.mimeType.startsWith('image/')) {
      return _ImageErrorPlaceholder(alt: alt);
    }
    final bytes = data.contentAsBytes();
    if (data.mimeType == 'image/svg+xml') {
      return _svg(SvgPicture.memory(bytes, errorBuilder: _svgError));
    }
    return Image.memory(
      bytes,
      width: width,
      height: height,
      semanticLabel: alt,
      errorBuilder: _rasterError,
    );
  }

  Widget _file() {
    final File file;
    try {
      file = File.fromUri(uri);
    } on UnsupportedError {
      return _ImageErrorPlaceholder(alt: alt);
    }
    if (_isSvgPath) return _svg(SvgPicture.file(file, errorBuilder: _svgError));
    return Image.file(
      file,
      width: width,
      height: height,
      semanticLabel: alt,
      errorBuilder: _rasterError,
    );
  }

  /// Applies the requested size and alt text to an [SvgPicture] built by one
  /// of its named constructors.
  Widget _svg(SvgPicture picture) {
    return Semantics(
      label: alt,
      image: true,
      child: SizedBox(width: width, height: height, child: picture),
    );
  }

  Widget _rasterError(BuildContext context, Object error, StackTrace? stack) =>
      _ImageErrorPlaceholder(alt: alt);

  Widget _svgError(BuildContext context, Object error, StackTrace stack) =>
      _ImageErrorPlaceholder(alt: alt);
}

/// Shown in place of an image that could not be loaded: a broken-image icon
/// followed by the alt text, so the reader still knows what was meant there.
class _ImageErrorPlaceholder extends StatelessWidget {
  const _ImageErrorPlaceholder({this.alt});

  final String? alt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = alt?.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          if (label != null && label.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
