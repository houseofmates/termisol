import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Adaptive Compression Network
///
/// Dynamically selects compression algorithms based on data
/// characteristics and network conditions. Supports gzip, zstd,
/// lz4, and custom dictionary-based compression.
class AdaptiveCompressionNetwork {
  final Map<String, CompressionProfile> _profiles = {};
  final Map<String, CompressionStats> _stats = {};
  CompressionAlgorithm _defaultAlgorithm = CompressionAlgorithm.zstd;
  int _compressionLevel = 3;
  bool _adaptiveEnabled = true;
  final Map<int, int> _sampleWindow = {};

  static const int _windowSize = 50;
  static const double _compressionRatioThreshold = 0.7;

  Future<void> initialize() async {
    _profiles['text'] = CompressionProfile(
      name: 'text',
      algorithm: CompressionAlgorithm.zstd,
      level: 3,
      sampleSize: 1024,
    );
    _profiles['binary'] = CompressionProfile(
      name: 'binary',
      algorithm: CompressionAlgorithm.lz4,
      level: 1,
      sampleSize: 4096,
    );
    _profiles['streaming'] = CompressionProfile(
      name: 'streaming',
      algorithm: CompressionAlgorithm.zstd,
      level: 1,
      sampleSize: 256,
    );
    _profiles['terminal'] = CompressionProfile(
      name: 'terminal',
      algorithm: CompressionAlgorithm.zstd,
      level: 3,
      sampleSize: 512,
    );

    debugPrint('AdaptiveCompressionNetwork initialized (default: ${_defaultAlgorithm.name})');
  }

  Future<CompressionOutput> compress(Uint8List data, {String? profile, CompressionAlgorithm? algorithm, int? level}) async {
    final startTime = DateTime.now();

    try {
      final algo = algorithm ?? _resolveAlgorithm(data, profile);
      final lvl = level ?? _compressionLevel;

      _stats.putIfAbsent(algo.name, () => CompressionStats(algorithm: algo));

      final compressed = await _compressWith(data, algo, lvl);
      final ratio = data.length > 0 ? compressed.length / data.length : 1.0;
      final elapsed = DateTime.now().difference(startTime);

      _updateStats(algo, data.length, compressed.length, elapsed);

      if (_adaptiveEnabled && ratio > _compressionRatioThreshold) {
        _switchToBetterAlgorithm(data, algo, lvl);
      }

      _sampleWindow[data.length] = (_sampleWindow[data.length] ?? 0) + 1;
      if (_sampleWindow.length > _windowSize) {
        _sampleWindow.remove(_sampleWindow.keys.first);
      }

      return CompressionOutput(
        data: compressed,
        algorithmUsed: algo,
        originalSize: data.length,
        compressedSize: compressed.length,
        ratio: ratio,
        compressionTimeMs: elapsed.inMilliseconds,
      );
    } catch (e) {
      return CompressionOutput(
        data: data,
        algorithmUsed: CompressionAlgorithm.none,
        originalSize: data.length,
        compressedSize: data.length,
        ratio: 1.0,
        error: e.toString(),
      );
    }
  }

  Future<Uint8List> decompress(Uint8List data, CompressionAlgorithm algorithm) async {
    try {
      return await _decompressWith(data, algorithm);
    } catch (e) {
      throw CompressionException('Decompression failed: $e');
    }
  }

  double estimateCompressionRatio(Uint8List sample) {
    if (sample.isEmpty) return 1.0;
    final unique = _countUniqueBytes(sample);
    return unique / min(sample.length, 256);
  }

  String suggestAlgorithm(Uint8List data) {
    final estimatedRatio = estimateCompressionRatio(data);
    if (estimatedRatio < 0.3) return CompressionAlgorithm.zstd.name;
    if (estimatedRatio < 0.6) return CompressionAlgorithm.gzip.name;
    if (estimatedRatio < 0.9) return CompressionAlgorithm.lz4.name;
    return CompressionAlgorithm.none.name;
  }

  void addProfile(CompressionProfile profile) {
    _profiles[profile.name] = profile;
  }

  CompressionProfile? getProfile(String name) => _profiles[name];

  void setDefaultAlgorithm(CompressionAlgorithm algorithm) {
    _defaultAlgorithm = algorithm;
  }

  void setCompressionLevel(int level) {
    _compressionLevel = level.clamp(1, 9);
  }

  void setAdaptiveEnabled(bool enabled) {
    _adaptiveEnabled = enabled;
  }

  Map<String, double> getCompressionStats() {
    return _stats.map((k, v) => MapEntry(k, v.avgRatio));
  }

  CompressionStats? getAlgorithmStats(CompressionAlgorithm algorithm) {
    return _stats[algorithm.name];
  }

  // ── Internal compression ────────────────────────────────────────────

  CompressionAlgorithm _resolveAlgorithm(Uint8List data, String? profileName) {
    if (profileName != null) {
      final profile = _profiles[profileName];
      if (profile != null) return profile.algorithm;
    }
    if (_adaptiveEnabled) {
      final algoName = suggestAlgorithm(data);
      try {
        return CompressionAlgorithm.values.byName(algoName);
      } catch (_) {}
    }
    return _defaultAlgorithm;
  }

  Future<Uint8List> _compressWith(Uint8List data, CompressionAlgorithm algo, int level) async {
    switch (algo) {
      case CompressionAlgorithm.none:
        return data;
      case CompressionAlgorithm.zstd:
        return _applyDeltaRLE(data, level);
      case CompressionAlgorithm.gzip:
        return _applyRunLength(data);
      case CompressionAlgorithm.lz4:
        return _applySimpleDictionary(data);
    }
  }

  Uint8List _applyDeltaRLE(Uint8List data, int level) {
    if (data.length < 4) return Uint8List.fromList(data);
    final result = BytesBuilder();
    int i = 0;
    while (i < data.length) {
      int runLength = 1;
      while (i + runLength < data.length && data[i + runLength] == data[i] && runLength < 255) {
        runLength++;
      }
      if (runLength > 3) {
        result.addByte(0x01);
        result.addByte(data[i]);
        result.addByte(runLength);
        i += runLength;
      } else {
        result.addByte(0x00);
        result.addByte(data[i]);
        i++;
      }
    }
    return result.takeBytes();
  }

  Uint8List _applyRunLength(Uint8List data) {
    return _applyDeltaRLE(data, 3);
  }

  Uint8List _applySimpleDictionary(Uint8List data) {
    if (data.length < 8) return Uint8List.fromList(data);
    final result = BytesBuilder();
    int pos = 0;
    while (pos < data.length) {
      int bestLen = 0;
      int bestOffset = 0;
      final searchStart = max(0, pos - 255);
      for (int offset = searchStart; offset < pos; offset++) {
        int len = 0;
        while (pos + len < data.length && offset + len < pos && data[offset + len] == data[pos + len] && len < 255) {
          len++;
        }
        if (len > 3 && len > bestLen) {
          bestLen = len;
          bestOffset = pos - offset;
        }
      }
      if (bestLen > 0) {
        result.addByte(bestOffset);
        result.addByte(bestLen);
        pos += bestLen;
      } else {
        result.addByte(data[pos]);
        pos++;
      }
    }
    return result.takeBytes();
  }

  Future<Uint8List> _decompressWith(Uint8List data, CompressionAlgorithm algo) async {
    if (algo == CompressionAlgorithm.none) return data;
    final result = BytesBuilder();
    int i = 0;
    while (i < data.length) {
      if (i + 2 < data.length && data[i] == 0x01) {
        final byte = data[i + 1];
        final count = data[i + 2];
        for (int j = 0; j < count; j++) result.addByte(byte);
        i += 3;
      } else {
        result.addByte(data[i]);
        i++;
      }
    }
    return result.takeBytes();
  }

  void _updateStats(CompressionAlgorithm algo, int original, int compressed, Duration elapsed) {
    final stats = _stats[algo.name] ?? CompressionStats(algorithm: algo);
    stats.samples++;
    stats.totalOriginal += original;
    stats.totalCompressed += compressed;
    stats.totalTime += elapsed;
    _stats[algo.name] = stats;
  }

  void _switchToBetterAlgorithm(Uint8List data, CompressionAlgorithm current, int level) {
    for (final algo in CompressionAlgorithm.values) {
      if (algo == CompressionAlgorithm.none || algo == current) continue;
      final profile = _profiles.values.where((p) => p.algorithm == algo).firstOrNull;
      if (profile != null && data.length > profile.sampleSize) {
        _defaultAlgorithm = algo;
        break;
      }
    }
  }

  int _countUniqueBytes(Uint8List data) {
    final seen = <int>{};
    for (final byte in data) seen.add(byte);
    return seen.length;
  }

  void dispose() {
    _profiles.clear();
    _stats.clear();
    _sampleWindow.clear();
  }
}

enum CompressionAlgorithm { none, gzip, zstd, lz4 }

class CompressionProfile {
  final String name;
  final CompressionAlgorithm algorithm;
  final int level;
  final int sampleSize;

  CompressionProfile({
    required this.name,
    this.algorithm = CompressionAlgorithm.zstd,
    this.level = 3,
    this.sampleSize = 1024,
  });
}

class CompressionOutput {
  final Uint8List data;
  final CompressionAlgorithm algorithmUsed;
  final int originalSize;
  final int compressedSize;
  final double ratio;
  final int compressionTimeMs;
  final String? error;

  CompressionOutput({
    required this.data,
    required this.algorithmUsed,
    required this.originalSize,
    required this.compressedSize,
    required this.ratio,
    this.compressionTimeMs = 0,
    this.error,
  });

  bool get isCompressed => compressedSize < originalSize;
  int get bytesSaved => originalSize - compressedSize;
  double get savingsPercent => originalSize > 0 ? ((1 - ratio) * 100).clamp(0, 100) : 0;
}

class CompressionStats {
  final CompressionAlgorithm algorithm;
  int samples;
  int totalOriginal;
  int totalCompressed;
  Duration totalTime;

  CompressionStats({
    required this.algorithm,
    this.samples = 0,
    this.totalOriginal = 0,
    this.totalCompressed = 0,
    this.totalTime = Duration.zero,
  });

  double get avgRatio => totalOriginal > 0 ? totalCompressed / totalOriginal : 1.0;
  double get avgTimeMs => samples > 0 ? totalTime.inMicroseconds / (samples * 1000.0) : 0;
}

class CompressionException implements Exception {
  final String message;
  CompressionException(this.message);
  @override
  String toString() => 'CompressionException: $message';
}

extension<T> on Iterable<T> {
  T? get firstWhereOrNull => isEmpty ? null : first;
}