import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../config/pkm_theme.dart';

class FileViewer {
  final Map<String, FileViewCache> _cache = {};
  static const int _maxCacheEntries = 20;

  Future<FileViewResult> openFile(String path) async {
    if (_cache.containsKey(path)) {
      return _cache[path]!.result;
    }

    try {
      final file = File(path);
      if (!await file.exists()) {
        return FileViewResult(
          path: path,
          viewType: ViewType.error,
          errorMessage: 'File not found',
        );
      }

      final ext = path.split('.').last.toLowerCase();
      final viewType = _detectViewType(path, ext);
      final content = await file.readAsString();
      final stat = await file.stat();

      final result = FileViewResult(
        path: path,
        viewType: viewType,
        filename: path.split('/').last,
        sizeBytes: stat.size,
        modifiedAt: stat.modified,
        rawContent: content,
        parsedContent: _parseContent(content, viewType),
        extension: ext,
      );

      _cache[path] = FileViewCache(result: result);
      if (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }

      return result;
    } catch (e) {
      return FileViewResult(
        path: path,
        viewType: ViewType.error,
        errorMessage: 'Failed to open file: $e',
      );
    }
  }

  ViewType _detectViewType(String path, String ext) {
    switch (ext) {
      case 'md':
      case 'markdown':
        return ViewType.markdown;
      case 'json':
        return ViewType.json;
      case 'yaml':
      case 'yml':
        return ViewType.yaml;
      case 'csv':
        return ViewType.csv;
      case 'tsv':
        return ViewType.tsv;
      case 'xml':
      case 'html':
      case 'htm':
        return ViewType.xml;
      case 'log':
        return ViewType.log;
      case 'env':
        return ViewType.properties;
      case 'ini':
      case 'cfg':
      case 'conf':
      case 'toml':
        return ViewType.properties;
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
      case 'go':
      case 'rs':
      case 'java':
      case 'c':
      case 'cpp':
      case 'h':
      case 'hpp':
      case 'swift':
      case 'kt':
      case 'rb':
      case 'php':
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'fish':
      case 'sql':
        return ViewType.code;
      case 'txt':
        return ViewType.text;
      case 'diff':
      case 'patch':
        return ViewType.diff;
      default:
        return ViewType.text;
    }
  }

  dynamic _parseContent(String content, ViewType viewType) {
    switch (viewType) {
      case ViewType.json:
        try {
          return jsonDecode(content);
        } catch (_) {
          return null;
        }
      case ViewType.csv:
        return _parseCsv(content);
      case ViewType.tsv:
        return _parseCsv(content, separator: '\t');
      case ViewType.yaml:
        return _parseYamlShallow(content);
      case ViewType.properties:
        return _parseProperties(content);
      default:
        return null;
    }
  }

  ParsedCsv _parseCsv(String content, {String separator = ','}) {
    final lines = content.split('\n');
    if (lines.isEmpty) return ParsedCsv(headers: [], rows: []);

    final headers = _splitCsvLine(lines.first, separator);
    final rows = <List<String>>[];

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      rows.add(_splitCsvLine(line, separator));
    }

    return ParsedCsv(headers: headers, rows: rows);
  }

  List<String> _splitCsvLine(String line, String separator) {
    final result = <String>[];
    var current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == separator && !inQuotes) {
        result.add(current.toString().trim());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }

    result.add(current.toString().trim());
    return result;
  }

  List<YamlEntry> _parseYamlShallow(String content) {
    final entries = <YamlEntry>[];
    final lines = content.split('\n');

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final indent = line.length - line.trimLeft().length;
      final colonIdx = line.indexOf(':');

      if (colonIdx > 0) {
        final key = line.substring(0, colonIdx).trim();
        final value = line.substring(colonIdx + 1).trim();
        entries.add(YamlEntry(
          key: key,
          value: value.isEmpty ? null : value,
          indent: indent,
        ));
      } else if (line.trim().startsWith('-')) {
        entries.add(YamlEntry(
          key: line.trim(),
          value: null,
          indent: indent,
        ));
      } else {
        entries.add(YamlEntry(
          key: line.trim(),
          value: null,
          indent: indent,
        ));
      }
    }

    return entries;
  }

  Map<String, String> _parseProperties(String content) {
    final props = <String, String>{};
    final lines = content.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith(';')) {
        continue;
      }

      final eqIdx = trimmed.indexOf('=');
      if (eqIdx > 0) {
        final key = trimmed.substring(0, eqIdx).trim();
        final value = trimmed.substring(eqIdx + 1).trim();
        props[key] = value;
      }
    }

    return props;
  }

  void clearCache() {
    _cache.clear();
  }
}

class FileViewResult {
  final String path;
  final ViewType viewType;
  final String? filename;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String? rawContent;
  final dynamic parsedContent;
  final String? extension;
  final String? errorMessage;

  FileViewResult({
    required this.path,
    required this.viewType,
    this.filename,
    this.sizeBytes,
    this.modifiedAt,
    this.rawContent,
    this.parsedContent,
    this.extension,
    this.errorMessage,
  });

  String get sizeFormatted {
    if (sizeBytes == null) return '--';
    if (sizeBytes! < 1024) return '${sizeBytes} B';
    if (sizeBytes! < 1024 * 1024) return '${(sizeBytes! / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  int get lineCount {
    if (rawContent == null) return 0;
    return '\n'.allMatches(rawContent!).length + 1;
  }
}

class FileViewCache {
  final FileViewResult result;

  FileViewCache({required this.result});
}

class ParsedCsv {
  final List<String> headers;
  final List<List<String>> rows;

  ParsedCsv({required this.headers, required this.rows});

  int get columnCount => headers.length;
  int get rowCount => rows.length;
}

class YamlEntry {
  final String key;
  final String? value;
  final int indent;

  YamlEntry({
    required this.key,
    required this.value,
    required this.indent,
  });

  int get depth => indent ~/ 2;
}

enum ViewType {
  markdown,
  json,
  yaml,
  csv,
  tsv,
  xml,
  log,
  properties,
  code,
  diff,
  text,
  error,
}

/// Widget that renders file content with syntax highlighting and pretty-print
class FileViewerWidget extends StatefulWidget {
  final FileViewResult result;

  const FileViewerWidget({super.key, required this.result});

  @override
  State<FileViewerWidget> createState() => _FileViewerWidgetState();
}

class _FileViewerWidgetState extends State<FileViewerWidget> {
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;
  final Set<int> _collapsedSections = {};

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0d0d0d),
        border: Border(bottom: BorderSide(color: const Color(0xFF1a1a1a), width: 1)),
      ),
      child: Row(
        children: [
          Icon(_viewTypeIcon(), size: 14, color: _viewTypeColor()),
          const SizedBox(width: 8),
          Text(
            widget.result.filename ?? widget.result.path.split('/').last,
            style: const TextStyle(
              color: Color(0xFF999999),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${widget.result.sizeFormatted} | ${widget.result.lineCount} lines | ${widget.result.viewType.name}',
            style: const TextStyle(color: Color(0xFF666666), fontSize: 9),
          ),
          if (_showSearch) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 160,
              height: 24,
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Color(0xFFCDD6E0), fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'search...',
                  hintStyle: const TextStyle(color: Color(0xFF666666), fontSize: 11),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFF2a2a2a)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1a1a1a),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              ),
            ),
          ],
          const SizedBox(width: 4),
          InkWell(
            onTap: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) _searchQuery = '';
            }),
            child: Icon(
              Icons.search,
              size: 14,
              color: _showSearch ? const Color(0xFF7CB9FF) : const Color(0xFF666666),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (widget.result.errorMessage != null) {
      return Center(
        child: Text(
          widget.result.errorMessage!,
          style: const TextStyle(color: Colors.red, fontSize: 12),
        ),
      );
    }

    switch (widget.result.viewType) {
      case ViewType.markdown:
        return _buildMarkdownView();
      case ViewType.json:
        return _buildJsonView();
      case ViewType.yaml:
        return _buildYamlView();
      case ViewType.csv:
      case ViewType.tsv:
        return _buildCsvView();
      case ViewType.properties:
        return _buildPropertiesView();
      case ViewType.code:
        return _buildCodeView();
      default:
        return _buildPlainTextView();
    }
  }

  Widget _buildMarkdownView() {
    final lines = _filterLines(widget.result.rawContent?.split('\n') ?? []);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: lines.length,
      itemBuilder: (ctx, i) => _buildMarkdownLine(lines[i], i),
    );
  }

  Widget _buildMarkdownLine(String line, int index) {
    final trimmed = line.trim();

    if (trimmed.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          trimmed.substring(4),
          style: const TextStyle(
            color: Color(0xFFE6DB74),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      );
    }
    if (trimmed.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(
          trimmed.substring(3),
          style: const TextStyle(
            color: Color(0xFFF92672),
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      );
    }
    if (trimmed.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(
          trimmed.substring(2),
          style: const TextStyle(
            color: Color(0xFFF92672),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      );
    }
    if (trimmed.startsWith('```')) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a1a),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          trimmed.replaceAll('```', ''),
          style: const TextStyle(color: Color(0xFF666666), fontSize: 10),
        ),
      );
    }
    if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      return Padding(
        padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('  \u2022  ', style: TextStyle(color: Color(0xFF7CB9FF), fontSize: 11)),
            Expanded(
              child: Text(
                trimmed.substring(2),
                style: const TextStyle(color: Color(0xFF999999), fontSize: 12, fontFamily: 'monospace', height: 1.5),
              ),
            ),
          ],
        ),
      );
    }
    if (trimmed.startsWith('> ')) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: const Color(0xFF7CB9FF).withOpacity(0.3), width: 2)),
        ),
        child: Text(
          trimmed.substring(2),
          style: TextStyle(color: const Color(0xFF999999).withOpacity(0.7), fontSize: 12, fontFamily: 'monospace', fontStyle: FontStyle.italic),
        ),
      );
    }
    if (trimmed.isEmpty) {
      return const SizedBox(height: 4);
    }

    return _highlightMarkdownInline(line);
  }

  Widget _highlightMarkdownInline(String line) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'(`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*|\[[^\]]+\]\([^)]+\))');
    var lastEnd = 0;

    for (final match in regex.allMatches(line)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: line.substring(lastEnd, match.start),
          style: const TextStyle(color: Color(0xFF999999), fontSize: 12, fontFamily: 'monospace'),
        ));
      }

      final matched = match.group(0)!;
      if (matched.startsWith('`') && matched.endsWith('`')) {
        spans.add(TextSpan(
          text: matched.substring(1, matched.length - 1),
          style: const TextStyle(
            color: Color(0xFFE6DB74),
            fontSize: 12,
            fontFamily: 'monospace',
            backgroundColor: Color(0xFF1a1a1a),
          ),
        ));
      } else if (matched.startsWith('**') && matched.endsWith('**')) {
        spans.add(TextSpan(
          text: matched.substring(2, matched.length - 2),
          style: const TextStyle(
            color: Color(0xFFCDD6E0),
            fontSize: 12,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ));
      } else if (matched.startsWith('*') && matched.endsWith('*')) {
        spans.add(TextSpan(
          text: matched.substring(1, matched.length - 1),
          style: const TextStyle(
            color: Color(0xFFCDD6E0),
            fontSize: 12,
            fontFamily: 'monospace',
            fontStyle: FontStyle.italic,
          ),
        ));
      } else if (matched.startsWith('[') && matched.contains('](')) {
        final text = RegExp(r'\[([^\]]+)\]').firstMatch(matched)?.group(1) ?? matched;
        spans.add(TextSpan(
          text: text,
          style: const TextStyle(
            color: Color(0xFF7CB9FF),
            fontSize: 12,
            fontFamily: 'monospace',
            decoration: TextDecoration.underline,
          ),
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < line.length) {
      spans.add(TextSpan(
        text: line.substring(lastEnd),
        style: const TextStyle(color: Color(0xFF999999), fontSize: 12, fontFamily: 'monospace'),
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(text: TextSpan(children: spans)),
    );
  }

  Widget _buildJsonView() {
    dynamic parsed = widget.result.parsedContent;
    if (parsed == null) {
      return _buildPlainTextView();
    }

    final formatted = const JsonEncoder.withIndent('  ').convert(parsed);
    final lines = _filterLines(formatted.split('\n'));

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: lines.length,
      itemBuilder: (ctx, i) {
        final line = lines[i];
        Color color = const Color(0xFFCDD6E0);

        if (line.contains('"') && line.contains(':')) {
          final keyPart = line.split(':')[0];
          if (keyPart.contains('"')) {
            final keyEnd = line.indexOf('":');
            if (keyEnd > 0) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF444444), fontSize: 9)),
                  ),
                  Text(
                    line.substring(0, keyEnd + 1) + ':',
                    style: const TextStyle(color: Color(0xFF7CB9FF), fontSize: 11, fontFamily: 'monospace', height: 1.6),
                  ),
                  Expanded(
                    child: Text(
                      line.substring(keyEnd + 2),
                      style: TextStyle(
                        color: line.contains('"') ? const Color(0xFFE6DB74) : const Color(0xFFA6E22E),
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              );
            }
          }
        }

        if (line.contains('{') || line.contains('}') || line.contains('[') || line.contains(']')) {
          color = const Color(0xFFF92672);
        } else if (line.contains('true') || line.contains('false') || line.contains('null')) {
          color = const Color(0xFFAE81FF);
        } else if (RegExp(r'\d+\.?\d*').hasMatch(line.replaceAll(RegExp(r'[",\[\]{}]'), '').trim())) {
          color = const Color(0xFFA6E22E);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF444444), fontSize: 9)),
              ),
              Expanded(
                child: Text(
                  line,
                  style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace', height: 1.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildYamlView() {
    final parsed = widget.result.parsedContent;
    final lines = _filterLines(widget.result.rawContent?.split('\n') ?? []);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: lines.length,
      itemBuilder: (ctx, i) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        final indent = line.length - trimmed.length;

        Color color = const Color(0xFFCDD6E0);
        if (trimmed.contains(':') && !trimmed.startsWith('-')) {
          color = const Color(0xFF7CB9FF);
        } else if (trimmed.startsWith('- ')) {
          color = const Color(0xFFA6E22E);
        } else if (trimmed.startsWith('#') || trimmed.isEmpty) {
          color = const Color(0xFF666666);
        } else if (RegExp(r'\d+\.?\d*').hasMatch(trimmed.split(':').last.trim()) &&
            trimmed.split(':').last.trim().length < 10) {
          color = const Color(0xFFA6E22E);
        } else if (['true', 'false', 'null', 'yes', 'no'].contains(trimmed.split(':').last.trim().toLowerCase())) {
          color = const Color(0xFFAE81FF);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF444444), fontSize: 9)),
              ),
              SizedBox(width: indent.toDouble()),
              Expanded(
                child: Text(
                  trimmed,
                  style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace', height: 1.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCsvView() {
    final parsed = widget.result.parsedContent as ParsedCsv?;
    final lines = _filterLines(widget.result.rawContent?.split('\n') ?? []);

    if (parsed == null || parsed.headers.isEmpty) {
      return _buildPlainTextView();
    }

    final allColumns = [parsed.headers, ...parsed.rows];
    final colWidths = List<int>.filled(parsed.columnCount, 0);
    for (final row in allColumns) {
      for (var c = 0; c < row.length && c < parsed.columnCount; c++) {
        if (row[c].length > colWidths[c]) colWidths[c] = row[c].length;
      }
    }

    final separator = widget.result.viewType == ViewType.tsv ? '\t' : ',';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCsvRow(parsed.headers, colWidths, isHeader: true),
              const SizedBox(height: 2),
              ...parsed.rows.asMap().entries.map((e) =>
                _buildCsvRow(e.value, colWidths, rowIndex: e.key)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCsvRow(List<String> cells, List<int> colWidths, {bool isHeader = false, int? rowIndex}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      decoration: BoxDecoration(
        color: isHeader
            ? const Color(0xFF1a1a1a)
            : (rowIndex != null && rowIndex % 2 == 0
                ? const Color(0xFF0d0d0d)
                : Colors.transparent),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: List.generate(colWidths.length, (c) {
          final text = c < cells.length ? cells[c] : '';
          final width = colWidths[c].clamp(6, 60) * 9.0;
          return Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isHeader ? const Color(0xFF7CB9FF) : const Color(0xFFCDD6E0),
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPropertiesView() {
    final parsed = widget.result.parsedContent as Map<String, String>?;
    if (parsed == null || parsed.isEmpty) return _buildPlainTextView();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: parsed.length,
      itemBuilder: (ctx, i) {
        final key = parsed.keys.elementAt(i);
        final value = parsed[key]!;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(key, style: TextStyle(color: const Color(0xFF7CB9FF), fontSize: 11, fontFamily: 'monospace')),
              const Text(' = ', style: TextStyle(color: Color(0xFF666666), fontSize: 11, fontFamily: 'monospace')),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(color: const Color(0xFFA6E22E), fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCodeView() {
    final lines = _filterLines(widget.result.rawContent?.split('\n') ?? []);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: lines.length,
      itemBuilder: (ctx, i) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                padding: const EdgeInsets.only(right: 8),
                alignment: Alignment.centerRight,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(color: Color(0xFF444444), fontSize: 9, fontFamily: 'monospace'),
                ),
              ),
              Expanded(
                child: Text(
                  lines[i],
                  style: const TextStyle(color: Color(0xFFCDD6E0), fontSize: 11, fontFamily: 'monospace', height: 1.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlainTextView() {
    final lines = _filterLines(widget.result.rawContent?.split('\n') ?? []);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: lines.length,
      itemBuilder: (ctx, i) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                padding: const EdgeInsets.only(right: 8),
                alignment: Alignment.centerRight,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(color: Color(0xFF444444), fontSize: 9, fontFamily: 'monospace'),
                ),
              ),
              Expanded(
                child: Text(
                  lines[i],
                  style: const TextStyle(color: Color(0xFF999999), fontSize: 11, fontFamily: 'monospace', height: 1.6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<String> _filterLines(List<String> lines) {
    if (_searchQuery.isEmpty) return lines;
    return lines.where((l) => l.toLowerCase().contains(_searchQuery)).toList();
  }

  IconData _viewTypeIcon() {
    switch (widget.result.viewType) {
      case ViewType.markdown: return Icons.article;
      case ViewType.json: return Icons.data_object;
      case ViewType.yaml: return Icons.settings;
      case ViewType.csv:
      case ViewType.tsv: return Icons.table_chart;
      case ViewType.code: return Icons.code;
      case ViewType.diff: return Icons.difference;
      case ViewType.properties: return Icons.tune;
      default: return Icons.description;
    }
  }

  Color _viewTypeColor() {
    switch (widget.result.viewType) {
      case ViewType.markdown: return const Color(0xFFF92672);
      case ViewType.json: return const Color(0xFFE6DB74);
      case ViewType.yaml: return const Color(0xFF7CB9FF);
      case ViewType.csv:
      case ViewType.tsv: return const Color(0xFFA6E22E);
      case ViewType.code: return const Color(0xFFAE81FF);
      default: return const Color(0xFF666666);
    }
  }
}