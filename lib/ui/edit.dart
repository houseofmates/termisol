import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:path/path.dart' as p;

/// A robust terminal text editor for termisol.
/// Opens files from the `edit <filename>` command.
class EditTerminal extends StatefulWidget {
  final String filePath;
  final String initialContent;
  final Function(String)? onSave;
  final VoidCallback? onClose;
  final bool readOnly;

  const EditTerminal({
    super.key,
    required this.filePath,
    required this.initialContent,
    this.onSave,
    this.onClose,
    this.readOnly = false,
  });

  @override
  State<EditTerminal> createState() => _EditTerminalState();
}

class _EditTerminalState extends State<EditTerminal> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _dirty = false;
  String? _error;

  String get _filename => p.basename(widget.filePath);

  String get _language {
    final ext = p.extension(_filename).toLowerCase();
    switch (ext) {
      case '.dart': return 'dart';
      case '.js': return 'javascript';
      case '.ts': return 'typescript';
      case '.py': return 'python';
      case '.rs': return 'rust';
      case '.go': return 'go';
      case '.c': case '.h': return 'c';
      case '.cpp': case '.cc': case '.hpp': return 'cpp';
      case '.java': return 'java';
      case '.kt': return 'kotlin';
      case '.swift': return 'swift';
      case '.rb': return 'ruby';
      case '.php': return 'php';
      case '.sh': case '.bash': return 'bash';
      case '.json': return 'json';
      case '.yaml': case '.yml': return 'yaml';
      case '.xml': return 'xml';
      case '.html': return 'html';
      case '.css': return 'css';
      case '.md': return 'markdown';
      case '.sql': return 'sql';
      default: return 'plaintext';
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _focusNode = FocusNode();
    _controller.addListener(() {
      if (!_dirty && _controller.text != widget.initialContent) {
        setState(() => _dirty = true);
      }
    });
    if (widget.initialContent.isEmpty) {
      _loadFile();
    }
  }

  Future<void> _loadFile() async {
    try {
      final file = File(widget.filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        _controller.text = content;
        setState(() => _dirty = false);
      }
    } catch (e) {
      setState(() => _error = 'failed to load file: $e');
    }
  }

  Future<void> _saveFile() async {
    try {
      final file = File(widget.filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(_controller.text);
      setState(() => _dirty = false);
      widget.onSave?.call(_controller.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('saved')),
        );
      }
    } catch (e) {
      setState(() => _error = 'failed to save: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFf6b012)),
          onPressed: widget.onClose,
        ),
        title: Text(
          _filename + (_dirty ? ' *' : ''),
          style: const TextStyle(
            color: Color(0xFFf6b012),
            fontSize: 16,
            fontFamily: 'DroidSansMono',
          ),
        ),
        actions: [
          if (!widget.readOnly)
            IconButton(
              icon: const Icon(Icons.save, color: Color(0xFFf6b012)),
              tooltip: 'save (ctrl+s)',
              onPressed: _saveFile,
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFFf6b012)),
            tooltip: 'close',
            onPressed: widget.onClose,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade900,
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                    () => _saveFile(),
                const SingleActivator(LogicalKeyboardKey.keyW, control: true):
                    () => widget.onClose?.call(),
              },
              child: Focus(
                autofocus: true,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  readOnly: widget.readOnly,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    fontFamily: 'DroidSansMono',
                    fontSize: 14,
                    color: Color(0xFFd8ba75),
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                ),
              ),
            ),
          ),
          if (_language != 'plaintext')
            Container(
              width: double.infinity,
              color: const Color(0xFF111111),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _language,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                  fontFamily: 'DroidSansMono',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
