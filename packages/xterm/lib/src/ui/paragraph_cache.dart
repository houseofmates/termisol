import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:quiver/collection.dart';

/// a cache of laid out [paragraph]s. this is used to avoid laying out the same
/// text multiple times, which is expensive.
class ParagraphCache {
  ParagraphCache(int maximumSize)
      : _cache = LruMap<int, Paragraph>(maximumSize: maximumSize);

  final LruMap<int, Paragraph> _cache;

  /// returns a [paragraph] for the given [key]. [key] is the same as the
  /// key argument to [performandcachelayout].
  Paragraph? getLayoutFromCache(int key) {
    return _cache[key];
  }

  /// applies [style] and [textscaler] to [text] and lays it out to create
  /// a [paragraph]. the [paragraph] is cached and can be retrieved with the
  /// same [key] by calling [getlayoutfromcache].
  Paragraph performAndCacheLayout(
    String text,
    TextStyle style,
    TextScaler textScaler,
    int key,
  ) {
    final builder = ParagraphBuilder(style.getParagraphStyle());
    builder.pushStyle(style.getTextStyle(textScaler: textScaler));
    builder.addText(text);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    _cache[key] = paragraph;
    return paragraph;
  }

  /// clears the cache. this should be called when the same text and style
  /// pair no longer produces the same layout. for example, when a font is
  /// loaded.
  void clear() {
    _cache.clear();
  }

  /// returns the number of [paragraph]s in the cache.
  int get length {
    return _cache.length;
  }
}
