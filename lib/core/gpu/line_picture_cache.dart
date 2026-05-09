import 'dart:ui';

import 'package:xterm/xterm.dart' show BufferLine;

class _CachedPicture {
  final int hash;
  final Picture picture;

  _CachedPicture(this.hash, this.picture);
}

/// LRU-style cache that stores [Picture] recordings of terminal lines.
///
/// Each visible line is keyed by its buffer index. The content hash of the
/// [BufferLine] is stored alongside the picture so that mutations are detected
/// and the stale picture is discarded.
class LinePictureCache {
  static const int _maxSize = 500;

  final Map<int, _CachedPicture> _cache = {};

  /// Returns a cached [Picture] for [lineIndex] if the line content has not
  /// changed since the picture was recorded.
  Picture? get(int lineIndex, BufferLine line) {
    final cached = _cache[lineIndex];
    if (cached == null) return null;

    final currentHash = _hashLine(line);
    if (cached.hash != currentHash) {
      _cache.remove(lineIndex)?.picture.dispose();
      return null;
    }
    return cached.picture;
  }

  /// Stores a newly recorded [Picture] for [lineIndex].
  void put(int lineIndex, BufferLine line, Picture picture) {
    if (_cache.length >= _maxSize) {
      _evictEldest();
    }
    _cache.remove(lineIndex)?.picture.dispose();
    _cache[lineIndex] = _CachedPicture(_hashLine(line), picture);
  }

  /// Clears the entire cache and disposes all native picture resources.
  void clear() {
    for (final entry in _cache.values) {
      entry.picture.dispose();
    }
    _cache.clear();
  }

  void _evictEldest() {
    final eldest = _cache.keys.first;
    _cache.remove(eldest)?.picture.dispose();
  }

  /// Fast rolling hash over the raw cell data of [line].
  static int _hashLine(BufferLine line) {
    final data = line.data;
    final len = line.length * 4;
    var h = 0;
    for (var i = 0; i < len; i++) {
      h = h * 31 ^ data[i];
    }
    return h;
  }
}
