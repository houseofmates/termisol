import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';

/// a robust terminal text editor for termisol.
/// opens files from the `edit <filename>` command.
///
/// keyboard shortcuts:
///   ctrl + z   undo
///   ctrl + x   redo
///   ctrl + s   save
///   ctrl + w   close
///   ctrl + o   open file
///   ctrl + f   toggle find
///   ctrl + v   paste
///   ctrl + c   copy selection
///   ctrl + a   select all
///   ctrl + shift + d   duplicate line
///   tab               insert / indent 2 spaces
///   enter             newline with auto-indent
class EditTerminal extends StatefulWidget {
  final String filePath;
  final String initialContent;
  final VoidCallback? onClose;
  final bool readOnly;

  const EditTerminal({
    super.key,
    required this.filePath,
    required this.initialContent,
    this.onClose,
    this.readOnly = false,
  });

  @override
  State<EditTerminal> createState() => _EditTerminalState();
}

class _EditTerminalState extends State<EditTerminal> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final ScrollController _textScrollController;
  late final ScrollController _lineNumScrollController;
  bool _dirty = false;
  String? _error;
  String? _saveMessage;
  Timer? _saveMessageTimer;
  final _findController = TextEditingController();
  bool _showFind = false;
  // undo / redo stacks
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  bool _isUndoRedo = false; // guard: don't record undo/redo onto the undo stack
  static const _maxUndo = 200;

  static const _tabSize = 2;
  static const _bgColor = Color(0xFF0a0a0a);
  static const _gutterColor = Color(0xFF1a1a1a);
  static const _textColor = Color(0xFFd8ba75);
  static const _lineNumColor = Color(0xFF555555);
  static const _accentColor = Color(0xFFf6b012);

  String get _filename => p.basename(widget.filePath);

  String get _language {
    final ext = p.extension(_filename).toLowerCase();
    return const {
          '.dart': 'dart',
          '.js': 'javascript',
          '.ts': 'typescript',
          '.py': 'python',
          '.rs': 'rust',
          '.go': 'go',
          '.c': 'c',
          '.h': 'c',
          '.cpp': 'cpp',
          '.cc': 'cpp',
          '.hpp': 'cpp',
          '.java': 'java',
          '.kt': 'kotlin',
          '.swift': 'swift',
          '.rb': 'ruby',
          '.php': 'php',
          '.sh': 'bash',
          '.bash': 'bash',
          '.json': 'json',
          '.yaml': 'yaml',
          '.yml': 'yaml',
          '.xml': 'xml',
          '.html': 'html',
          '.css': 'css',
          '.md': 'markdown',
          '.sql': 'sql',
        }[ext] ??
        'plaintext';
  }

  int get _cursorLine {
    final text = _controller.text;
    final sel = _controller.selection;
    if (!sel.isValid || sel.baseOffset < 0) return 1;
    final beforeCursor = text.substring(
      0,
      sel.baseOffset.clamp(0, text.length),
    );
    return '\n'.allMatches(beforeCursor).length + 1;
  }

  int get _cursorCol {
    final text = _controller.text;
    final sel = _controller.selection;
    if (!sel.isValid || sel.baseOffset < 0) return 1;
    final offset = sel.baseOffset.clamp(0, text.length);
    final lastNewline = text.lastIndexOf('\n', offset - 1);
    return offset - (lastNewline == -1 ? 0 : lastNewline);
  }

  int get _lineCount {
    final text = _controller.text;
    if (text.isEmpty) return 1;
    return '\n'.allMatches(text).length + 1;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _focusNode = FocusNode();
    _textScrollController = ScrollController();
    _lineNumScrollController = ScrollController();

    // Sync scroll controllers
    _textScrollController.addListener(_syncScroll);

    _controller.addListener(() {
      if (!_dirty && _controller.text != widget.initialContent) {
        setState(() => _dirty = true);
      }
      // save state for undo (only on user edits, not during undo/redo)
      if (!_isUndoRedo) {
        _saveToUndoStack(_controller.text);
      }
    });

    if (widget.initialContent.isEmpty && widget.filePath.isNotEmpty) {
      _loadFile();
    }
    // seed undo stack with initial state
    if (_undoStack.isEmpty) {
      _undoStack.add(widget.initialContent);
    }
  }

  void _syncScroll() {
    if (_lineNumScrollController.hasClients &&
        _lineNumScrollController.offset != _textScrollController.offset) {
      _lineNumScrollController.jumpTo(_textScrollController.offset);
    }
  }

  void _saveToUndoStack(String text) {
    // don't save consecutive identical states
    if (_undoStack.isNotEmpty && _undoStack.last == text) return;
    _undoStack.add(text);
    if (_undoStack.length > _maxUndo) {
      _undoStack.removeRange(0, _undoStack.length - _maxUndo);
    }
    // clear redo stack on new user action
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.length <= 1) return;
    _isUndoRedo = true;
    _redoStack.add(_undoStack.removeLast());
    final previous = _undoStack.last;
    _controller.text = previous;
    _controller.selection = TextSelection.collapsed(offset: previous.length);
    _isUndoRedo = false;
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _isUndoRedo = true;
    final next = _redoStack.removeLast();
    _undoStack.add(next);
    _controller.text = next;
    _controller.selection = TextSelection.collapsed(offset: next.length);
    _isUndoRedo = false;
  }

  Future<void> _copy() async {
    final sel = _controller.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final text = _controller.text.substring(sel.start, sel.end);
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null || data.text == null) return;
    final sel = _controller.selection;
    final text = _controller.text;
    final insert = data.text!;
    final newText = text.replaceRange(sel.start, sel.end, insert);
    final newOffset = sel.start + insert.length;
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }

  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  Future<void> _loadFile() async {
    try {
      final file = File(widget.filePath);
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (!mounted) return;
        _controller.text = content;
        setState(() => _dirty = false);
      }
    } catch (e, stack) {
      debugPrint('edit: failed to load file: $e\n$stack');
      if (!mounted) return;
      setState(() => _error = 'failed to load file: $e');
    }
  }

  Future<void> _saveFile() async {
    if (widget.readOnly) return;
    try {
      final file = File(widget.filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(_controller.text);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _error = null;
        _saveMessage = 'saved';
      });
      _saveMessageTimer?.cancel();
      _saveMessageTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saveMessage = null);
      });
    } catch (e, stack) {
      debugPrint('edit: failed to save: $e\n$stack');
      if (!mounted) return;
      setState(() => _error = 'failed to save: $e');
    }
  }

  Future<void> _openFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'open file',
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.first;
        final path = picked.path;
        if (path != null) {
          String content = '';
          if (picked.bytes != null) {
            content = String.fromCharCodes(picked.bytes!);
          } else {
            content = await File(path).readAsString();
          }
          if (!mounted) return;
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => EditTerminal(
                filePath: path,
                initialContent: content,
                onClose: widget.onClose,
              ),
            ),
          );
        }
      }
    } catch (e, stack) {
      debugPrint('edit: failed to open file: $e\n$stack');
      setState(() => _error = 'failed to open file: $e');
    }
  }

  void _findNext() {
    final query = _findController.text;
    if (query.isEmpty) return;
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.isValid && sel.baseOffset >= 0 ? sel.baseOffset : 0;
    final idx = text.indexOf(query, start + 1);
    if (idx >= 0) {
      _controller.selection = TextSelection(
        baseOffset: idx,
        extentOffset: idx + query.length,
      );
    } else {
      // wrap around
      final wrapIdx = text.indexOf(query);
      if (wrapIdx >= 0 && wrapIdx != start) {
        _controller.selection = TextSelection(
          baseOffset: wrapIdx,
          extentOffset: wrapIdx + query.length,
        );
      }
    }
  }

  void _findPrevious() {
    final query = _findController.text;
    if (query.isEmpty) return;
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.isValid && sel.baseOffset >= 0
        ? sel.baseOffset
        : text.length;
    final idx = text.lastIndexOf(query, start - 1);
    if (idx >= 0) {
      _controller.selection = TextSelection(
        baseOffset: idx,
        extentOffset: idx + query.length,
      );
    } else {
      // wrap around
      final wrapIdx = text.lastIndexOf(query, text.length);
      if (wrapIdx >= 0 && wrapIdx != start) {
        _controller.selection = TextSelection(
          baseOffset: wrapIdx,
          extentOffset: wrapIdx + query.length,
        );
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _insertTab();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _handleEnter();
      return KeyEventResult.handled;
    }
    if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyD) {
      _duplicateLine();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _insertTab() {
    final sel = _controller.selection;
    if (!sel.isValid) return;
    final text = _controller.text;
    final sb = StringBuffer();

    if (sel.isCollapsed) {
      sb.write(text.substring(0, sel.start));
      sb.write(' ' * _tabSize);
      sb.write(text.substring(sel.start));
      _controller.value = TextEditingValue(
        text: sb.toString(),
        selection: TextSelection.collapsed(offset: sel.start + _tabSize),
      );
    } else {
      // Indent selected lines
      final startLine = text.lastIndexOf('\n', sel.start - 1) + 1;
      final endLine = text.indexOf('\n', sel.end);
      final endPos = endLine == -1 ? text.length : endLine;
      final selectedBlock = text.substring(startLine, endPos);
      final indented = selectedBlock
          .split('\n')
          .map((l) => ' ' * _tabSize + l)
          .join('\n');
      sb.write(text.substring(0, startLine));
      sb.write(indented);
      sb.write(text.substring(endPos));
      _controller.value = TextEditingValue(
        text: sb.toString(),
        selection: TextSelection(
          baseOffset: sel.start + _tabSize,
          extentOffset: sel.end + (indented.length - selectedBlock.length),
        ),
      );
    }
  }

  void _handleEnter() {
    final sel = _controller.selection;
    if (!sel.isValid || sel.start < 0 || sel.end < 0) {
      // Invalid selection: just append newline at end.
      _controller.text = '${_controller.text}\n';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      return;
    }
    if (!sel.isCollapsed) {
      // Replace selection with newline.
      _controller.text =
          '${_controller.text.substring(0, sel.start)}\n${_controller.text.substring(sel.end)}';
      _controller.selection = TextSelection.collapsed(offset: sel.start + 1);
      return;
    }
    final text = _controller.text;
    final lineStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    final line = text.substring(lineStart, sel.start);
    final indentMatch = RegExp(r'^(\s*)').firstMatch(line);
    final indent = indentMatch?.group(1) ?? '';

    // Auto-indent after opening braces
    final extraIndent =
        (line.trimRight().endsWith('{') ||
            line.trimRight().endsWith('(') ||
            line.trimRight().endsWith('['))
        ? ' ' * _tabSize
        : '';

    final newText =
        '${text.substring(0, sel.start)}\n$indent$extraIndent${text.substring(sel.start)}';

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: sel.start + 1 + indent.length + extraIndent.length,
      ),
    );
  }

  void _duplicateLine() {
    final sel = _controller.selection;
    if (!sel.isValid) return;
    final text = _controller.text;
    final lineStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    final lineEnd = text.indexOf('\n', sel.start);
    final endPos = lineEnd == -1 ? text.length : lineEnd;
    final line = text.substring(lineStart, endPos);

    final newText =
        '${text.substring(0, endPos)}\n$line${text.substring(endPos)}';

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: endPos + 1 + line.length),
    );
  }

  @override
  void dispose() {
    _saveMessageTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _textScrollController.dispose();
    _lineNumScrollController.dispose();
    _findController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _accentColor),
          onPressed: widget.onClose,
          tooltip: 'close (ctrl+w)',
        ),
        title: Text(
          '$_filename${_dirty ? ' *' : ''}',
          style: const TextStyle(
            color: _accentColor,
            fontSize: 16,
            fontFamily: 'DroidSansMono',
          ),
        ),
        actions: [
          if (_saveMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  _saveMessage!,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                    fontFamily: 'DroidSansMono',
                  ),
                ),
              ),
            ),
          if (!widget.readOnly)
            IconButton(
              icon: const Icon(Icons.save, color: _accentColor),
              tooltip: 'save (ctrl+s)',
              onPressed: _saveFile,
            ),
          IconButton(
            icon: const Icon(Icons.folder_open, color: _accentColor),
            tooltip: 'open (ctrl+o)',
            onPressed: _openFile,
          ),
          IconButton(
            icon: Icon(
              _showFind ? Icons.find_replace : Icons.search,
              color: _accentColor,
            ),
            tooltip: 'find (ctrl+f)',
            onPressed: () => setState(() => _showFind = !_showFind),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: _accentColor),
            tooltip: 'close (ctrl+w)',
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
          if (_showFind)
            Container(
              color: const Color(0xFF1a1a1a),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _findController,
                      autofocus: true,
                      style: const TextStyle(
                        color: _textColor,
                        fontFamily: 'DroidSansMono',
                        fontSize: 13,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'find',
                        hintStyle: TextStyle(color: Color(0xFF555555)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _findNext(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.keyboard_arrow_up,
                      color: _accentColor,
                      size: 20,
                    ),
                    tooltip: 'previous',
                    onPressed: _findPrevious,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: _accentColor,
                      size: 20,
                    ),
                    tooltip: 'next',
                    onPressed: _findNext,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: _accentColor,
                      size: 20,
                    ),
                    tooltip: 'close find',
                    onPressed: () => setState(() => _showFind = false),
                  ),
                ],
              ),
            ),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.keyZ,
                  control: true,
                ): () => _undo(),
                const SingleActivator(
                  LogicalKeyboardKey.keyX,
                  control: true,
                ): () => _redo(),
                const SingleActivator(
                  LogicalKeyboardKey.keyS,
                  control: true,
                ): () =>
                    unawaited(_saveFile()),
                const SingleActivator(
                  LogicalKeyboardKey.keyW,
                  control: true,
                ): () =>
                    widget.onClose?.call(),
                const SingleActivator(
                  LogicalKeyboardKey.keyO,
                  control: true,
                ): () =>
                    unawaited(_openFile()),
                const SingleActivator(
                  LogicalKeyboardKey.keyF,
                  control: true,
                ): () =>
                    setState(() => _showFind = !_showFind),
                const SingleActivator(
                  LogicalKeyboardKey.keyV,
                  control: true,
                ): () => _paste(),
                const SingleActivator(
                  LogicalKeyboardKey.keyC,
                  control: true,
                ): () => unawaited(_copy()),
                const SingleActivator(
                  LogicalKeyboardKey.keyA,
                  control: true,
                ): () => _selectAll(),
              },
              child: Focus(
                autofocus: true,
                onKeyEvent: _handleKeyEvent,
                child: Row(
                  children: [
                    // Line numbers gutter
                    Container(
                      width: 48,
                      color: _gutterColor,
                      child: ScrollConfiguration(
                        behavior: const ScrollBehavior().copyWith(
                          scrollbars: false,
                          dragDevices: {},
                        ),
                        child: ListView.builder(
                          controller: _lineNumScrollController,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _lineCount,
                          itemBuilder: (context, index) {
                            return Container(
                              height: 20.8, // 14 * 1.4 line height
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: _lineNumColor,
                                  fontSize: 12,
                                  fontFamily: 'DroidSansMono',
                                  height: 1.4,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    // Editor
                    const VerticalDivider(width: 1, color: Color(0xFF333333)),
                    Expanded(
                      child: Scrollbar(
                        controller: _textScrollController,
                        child: SingleChildScrollView(
                          controller: _textScrollController,
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            readOnly: widget.readOnly,
                            maxLines: null,
                            style: const TextStyle(
                              fontFamily: 'DroidSansMono',
                              fontSize: 14,
                              color: _textColor,
                              height: 1.4,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(12),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            scrollPhysics: const NeverScrollableScrollPhysics(),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Status bar
          Container(
            height: 24,
            color: const Color(0xFF1a1a1a),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  'ln $_cursorLine, col $_cursorCol',
                  style: const TextStyle(
                    color: _lineNumColor,
                    fontSize: 11,
                    fontFamily: 'DroidSansMono',
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  _language,
                  style: const TextStyle(
                    color: _lineNumColor,
                    fontSize: 11,
                    fontFamily: 'DroidSansMono',
                  ),
                ),
                const Spacer(),
                Text(
                  '${_controller.text.length} chars',
                  style: const TextStyle(
                    color: _lineNumColor,
                    fontSize: 11,
                    fontFamily: 'DroidSansMono',
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  widget.readOnly ? 'read-only' : 'utf-8',
                  style: const TextStyle(
                    color: _lineNumColor,
                    fontSize: 11,
                    fontFamily: 'DroidSansMono',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
