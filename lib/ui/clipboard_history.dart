import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent clipboard history manager.
///
/// Stores up to [maxEntries] clipboard items in a JSON file in the
/// application documents directory. Items are kept in MRU order.
class ClipboardHistoryManager {
  static const String _fileName = 'clipboard_history.json';
  static const int defaultMaxEntries = 50;

  final int maxEntries;
  final List<ClipboardEntry> _entries = [];

  ClipboardHistoryManager({this.maxEntries = defaultMaxEntries});

  /// Load history from disk.
  Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) return;

      final json = jsonDecode(await file.readAsString()) as List<dynamic>;
      _entries.clear();
      for (final item in json) {
        _entries.add(ClipboardEntry.fromJson(item as Map<String, dynamic>));
      }
    } catch (e) {
      debugPrint('[ClipboardHistory] Load failed: $e');
    }
  }

  /// Save history to disk.
  Future<void> save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      final json = _entries.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('[ClipboardHistory] Save failed: $e');
    }
  }

  /// Add a new item to the history. Duplicates are moved to the front.
  Future<void> add(String text) async {
    if (text.isEmpty) return;

    // Remove existing duplicate.
    _entries.removeWhere((e) => e.text == text);

    _entries.insert(0, ClipboardEntry(text: text, timestamp: DateTime.now()));

    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }

    await save();
  }

  /// Get all history entries.
  List<ClipboardEntry> get entries => List.unmodifiable(_entries);

  /// Clear all history.
  Future<void> clear() async {
    _entries.clear();
    await save();
  }
}

/// A single clipboard history entry.
class ClipboardEntry {
  final String text;
  final DateTime timestamp;

  ClipboardEntry({required this.text, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'text': text,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ClipboardEntry.fromJson(Map<String, dynamic> json) {
    return ClipboardEntry(
      text: json['text'] ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}

/// A floating overlay for selecting from clipboard history.
class ClipboardHistoryOverlay extends StatelessWidget {
  final ClipboardHistoryManager manager;
  final ValueChanged<String> onSelect;
  final VoidCallback onClose;

  const ClipboardHistoryOverlay({
    super.key,
    required this.manager,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final entries = manager.entries;
    return Positioned(
      top: 56,
      right: 16,
      width: 360,
      child: Material(
        color: const Color(0xFF1a1a1a),
        borderRadius: BorderRadius.circular(8),
        elevation: 8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Clipboard History',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () async {
                          await manager.clear();
                          onClose();
                        },
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF333333), height: 1),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No clipboard history yet.',
                  style: TextStyle(color: Colors.grey, fontFamily: 'monospace'),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        entry.text.replaceAll('\n', '↵'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      subtitle: Text(
                        _formatTime(entry.timestamp),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                      onTap: () {
                        onSelect(entry.text);
                        onClose();
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
