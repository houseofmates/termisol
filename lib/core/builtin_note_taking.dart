import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class BuiltinNoteTaking {
  static const String _notesDirectory = '/home/house/termisol_notes';
  static const String _notesFile = '$_notesDirectory/notes.json';
  static const String _categoriesFile = '$_notesDirectory/categories.json';
  static const String _tagsFile = '$_notesDirectory/tags.json';
  static const int _maxNotes = 10000;
  static const int _maxCategories = 100;
  static const int _maxTags = 1000;
  
  final Map<String, Note> _notes = {};
  final Map<String, NoteCategory> _categories = {};
  final Map<String, NoteTag> _tags = {};
  final Map<String, List<String>> _tagIndex = {};
  final Map<String, List<String>> _categoryIndex = {};
  
  Timer? _autoSaveTimer;
  String? _currentNote;
  int _totalNotes = 0;
  int _totalCategories = 0;
  int _totalTags = 0;
  
  final StreamController<NoteEvent> _noteController = 
      StreamController<NoteEvent>.broadcast();

  void initialize() {
    _ensureNotesDirectory();
    _loadNotes();
    _loadCategories();
    _loadTags();
    _setupGNOMEIntegration();
    _startAutoSave();
    developer.log('📝 Built-in Note Taking initialized');
  }

  void _ensureNotesDirectory() {
    final notesDir = Directory(_notesDirectory);
    if (!notesDir.existsSync()) {
      notesDir.createSync(recursive: true);
      notesDir.setPermissionsSync(0o755);
    }
  }

  void _loadNotes() {
    try {
      final file = File(_notesFile);
      if (!file.existsSync()) {
        developer.log('📝 No existing notes file found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['notes']) {
        final note = Note.fromJson(entry);
        _notes[note.id] = note;
        _totalNotes++;
        
        // Update indexes
        _updateIndexes(note);
      }
      
      developer.log('📝 Loaded ${_notes.length} notes');
      
    } catch (e) {
      developer.log('📝 Failed to load notes: $e');
    }
  }

  void _loadCategories() {
    try {
      final file = File(_categoriesFile);
      if (!file.existsSync()) {
        _createDefaultCategories();
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['categories']) {
        final category = NoteCategory.fromJson(entry);
        _categories[category.id] = category;
        _totalCategories++;
      }
      
      developer.log('📝 Loaded ${_categories.length} categories');
      
    } catch (e) {
      developer.log('📝 Failed to load categories: $e');
      _createDefaultCategories();
    }
  }

  void _loadTags() {
    try {
      final file = File(_tagsFile);
      if (!file.existsSync()) {
        developer.log('📝 No existing tags file found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['tags']) {
        final tag = NoteTag.fromJson(entry);
        _tags[tag.id] = tag;
        _totalTags++;
        
        // Update tag index
        _tagIndex.putIfAbsent(tag.name.toLowerCase(), () => <String>[]).add(tag.id);
      }
      
      developer.log('📝 Loaded ${_tags.length} tags');
      
    } catch (e) {
      developer.log('📝 Failed to load tags: $e');
    }
  }

  void _createDefaultCategories() {
    final defaultCategories = [
      NoteCategory(
        id: 'general',
        name: 'General',
        description: 'General notes',
        color: '#6B7280',
        icon: '📝',
        createdAt: DateTime.now(),
        noteCount: 0,
      ),
      NoteCategory(
        id: 'development',
        name: 'Development',
        description: 'Development-related notes',
        color: '#3B82F6',
        icon: '💻',
        createdAt: DateTime.now(),
        noteCount: 0,
      ),
      NoteCategory(
        id: 'terminal',
        name: 'Terminal',
        description: 'Terminal commands and tips',
        color: '#10B981',
        icon: '🖥️',
        createdAt: DateTime.now(),
        noteCount: 0,
      ),
      NoteCategory(
        id: 'ideas',
        name: 'Ideas',
        description: 'Creative ideas and thoughts',
        color: '#8B5CF6',
        icon: '💡',
        createdAt: DateTime.now(),
        noteCount: 0,
      ),
      NoteCategory(
        id: 'tasks',
        name: 'Tasks',
        description: 'Task lists and reminders',
        color: '#F59E0B',
        icon: '✅',
        createdAt: DateTime.now(),
        noteCount: 0,
      ),
    ];
    
    for (final category in defaultCategories) {
      _categories[category.id] = category;
      _totalCategories++;
    }
    
    _saveCategories();
    developer.log('📝 Created default categories');
  }

  void _setupGNOMEIntegration() {
    try {
      // Create GNOME desktop entry for note-taking
      final desktopFile = File('/usr/share/applications/termisol-notes.desktop');
      
      final desktopContent = '''[Desktop Entry]
Version=1.0
Type=Application
Name=Termisol Notes
Comment=Quick notes from Termisol terminal
Exec=termisol --notes
Icon=termisol-notes
Terminal=false
Categories=Utility;Office;
Keywords=notes;quick;terminal;
Actions=NewNote;QuickNote;

[Desktop Action NewNote]
Name=New Note
Exec=termisol --notes --new

[Desktop Action QuickNote]
Name=Quick Note
Exec=termisol --notes --quick
''';
      
      // Try to create desktop entry (may require sudo)
      try {
        desktopFile.parent.createSync(recursive: true);
        desktopFile.writeAsStringSync(desktopContent);
        desktopFile.setPermissionsSync(0o644);
        
        developer.log('📝 Created GNOME desktop entry');
      } catch (e) {
        developer.log('📝 Failed to create GNOME desktop entry (may need sudo): $e');
      }
      
      // Create GNOME shell extension integration
      _createGNOMEShellExtension();
      
    } catch (e) {
      developer.log('📝 Failed to setup GNOME integration: $e');
    }
  }

  void _createGNOMEShellExtension() {
    try {
      final extensionDir = Directory('/home/house/.local/share/gnome-shell/extensions/termisol-notes');
      if (!extensionDir.existsSync()) {
        extensionDir.createSync(recursive: true);
      }
      
      final extensionFile = File('${extensionDir.path}/extension.js');
      final extensionContent = '''const GObject = imports.gi.GObject;
const St = imports.gi.St;
const Main = imports.ui.main;
const PanelMenu = imports.ui.panelMenu;
const PopupMenu = imports.ui.popupMenu;

class Extension {
  constructor() {
    this._indicator = null;
  }

  enable() {
    this._indicator = new PanelMenu.SystemIndicator();
    this._indicator.connect('activate', this._onActivate.bind(this));
    this._indicator.connect('open-menu', this._onOpenMenu.bind(this));
    
    Main.panel.statusArea.indicators.add(this._indicator);
  }

  disable() {
    if (this._indicator) {
      Main.panel.statusArea.indicators.remove(this._indicator);
      this._indicator.destroy();
      this._indicator = null;
    }
  }

  _onActivate() {
    // Launch Termisol with notes
    imports.misc.util.spawn(['termisol', '--notes']);
  }

  _onOpenMenu() {
    // Create quick note menu
    let menu = new PopupMenu.PopupMenu();
    
    let newItem = new PopupMenu.PopupMenuItem('New Note');
    newItem.connect('activate', () => {
      imports.misc.util.spawn(['termisol', '--notes', '--new']);
    });
    menu.addMenuItem(newItem);
    
    let quickItem = new PopupMenu.PopupMenuItem('Quick Note');
    quickItem.connect('activate', () => {
      imports.misc.util.spawn(['termisol', '--notes', '--quick']);
    });
    menu.addMenuItem(quickItem);
    
    menu.open();
  }
}

function init() {
  return new Extension();
}
''';
      
      extensionFile.writeAsStringSync(extensionContent);
      
      final metadataFile = File('${extensionDir.path}/metadata.json');
      final metadataContent = '''{
  "name": "Termisol Notes",
  "description": "Quick note-taking integration for Termisol terminal",
  "uuid": "termisol-notes@houseofmates.github.com",
  "shell-version": ["45", "46", "47", "48"],
  "url": "https://github.com/houseofmates/termisol",
  "version": "1.0"
}''';
      
      metadataFile.writeAsStringSync(metadataContent);
      
      developer.log('📝 Created GNOME shell extension');
      
    } catch (e) {
      developer.log('📝 Failed to create GNOME shell extension: $e');
    }
  }

  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(
      Duration(seconds: 30),
      (_) => _autoSave(),
    );
  }

  void _autoSave() {
    if (_currentNote != null) {
      _saveNotes();
    }
  }

  Future<String> createNote({
    required String title,
    String? content,
    String? categoryId,
    List<String>? tagIds,
    NotePriority? priority,
    bool? isPinned,
    bool? isMarkdown,
    Map<String, dynamic>? metadata,
  }) async {
    if (_notes.length >= _maxNotes) {
      throw Exception('Maximum notes reached: $_maxNotes');
    }
    
    final noteId = _generateNoteId();
    
    final note = Note(
      id: noteId,
      title: title,
      content: content ?? '',
      categoryId: categoryId ?? 'general',
      tagIds: tagIds ?? [],
      priority: priority ?? NotePriority.normal,
      isPinned: isPinned ?? false,
      isMarkdown: isMarkdown ?? true,
      metadata: metadata ?? {},
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      accessedAt: DateTime.now(),
      wordCount: content?.split(' ').length ?? 0,
      characterCount: content?.length ?? 0,
    );
    
    _notes[noteId] = note;
    _totalNotes++;
    
    // Update indexes
    _updateIndexes(note);
    
    // Update category note count
    if (note.categoryId != null) {
      final category = _categories[note.categoryId!];
      if (category != null) {
        category.noteCount++;
      }
    }
    
    developer.log('📝 Created note: $title');
    
    _emitEvent(NoteEvent(
      type: NoteEventType.created,
      noteId: noteId,
      title: title,
      categoryId: note.categoryId,
    ));
    
    await _saveNotes();
    await _saveCategories();
    
    return noteId;
  }

  Future<void> updateNote(String noteId, {
    String? title,
    String? content,
    String? categoryId,
    List<String>? tagIds,
    NotePriority? priority,
    bool? isPinned,
    bool? isMarkdown,
    Map<String, dynamic>? metadata,
  }) async {
    final note = _notes[noteId];
    if (note == null) {
      throw Exception('Note not found: $noteId');
    }
    
    // Update category note counts
    if (categoryId != null && categoryId != note.categoryId) {
      // Decrement old category
      if (note.categoryId != null) {
        final oldCategory = _categories[note.categoryId!];
        if (oldCategory != null) {
          oldCategory.noteCount = max(0, oldCategory.noteCount - 1);
        }
      }
      
      // Increment new category
      final newCategory = _categories[categoryId!];
      if (newCategory != null) {
        newCategory.noteCount++;
      }
    }
    
    // Remove old tag associations
    for (final tagId in note.tagIds) {
      _removeTagFromIndex(tagId, noteId);
    }
    
    // Update note properties
    if (title != null) note.title = title!;
    if (content != null) {
      note.content = content!;
      note.wordCount = content!.split(' ').length;
      note.characterCount = content!.length;
    }
    if (categoryId != null) note.categoryId = categoryId!;
    if (tagIds != null) note.tagIds = tagIds!;
    if (priority != null) note.priority = priority!;
    if (isPinned != null) note.isPinned = isPinned!;
    if (isMarkdown != null) note.isMarkdown = isMarkdown!;
    if (metadata != null) note.metadata.addAll(metadata!);
    
    note.modifiedAt = DateTime.now();
    note.accessedAt = DateTime.now();
    
    // Update indexes
    _updateIndexes(note);
    
    developer.log('📝 Updated note: $noteId');
    
    _emitEvent(NoteEvent(
      type: NoteEventType.updated,
      noteId: noteId,
      title: note.title,
      categoryId: note.categoryId,
    ));
    
    await _saveNotes();
    await _saveCategories();
  }

  Future<void> deleteNote(String noteId) async {
    final note = _notes.remove(noteId);
    if (note == null) {
      throw Exception('Note not found: $noteId');
    }
    
    // Update category note count
    if (note.categoryId != null) {
      final category = _categories[note.categoryId!];
      if (category != null) {
        category.noteCount = max(0, category.noteCount - 1);
      }
    }
    
    // Remove from indexes
    for (final tagId in note.tagIds) {
      _removeTagFromIndex(tagId, noteId);
    }
    
    _totalNotes--;
    
    developer.log('📝 Deleted note: $noteId');
    
    _emitEvent(NoteEvent(
      type: NoteEventType.deleted,
      noteId: noteId,
      title: note.title,
    ));
    
    await _saveNotes();
    await _saveCategories();
  }

  Future<String> createCategory({
    required String name,
    required String description,
    String? color,
    String? icon,
  }) async {
    if (_categories.length >= _maxCategories) {
      throw Exception('Maximum categories reached: $_maxCategories');
    }
    
    final categoryId = _generateCategoryId();
    
    final category = NoteCategory(
      id: categoryId,
      name: name,
      description: description,
      color: color ?? '#6B7280',
      icon: icon ?? '📁',
      createdAt: DateTime.now(),
      noteCount: 0,
    );
    
    _categories[categoryId] = category;
    _totalCategories++;
    
    developer.log('📝 Created category: $name');
    
    _emitEvent(NoteEvent(
      type: NoteEventType.categoryCreated,
      categoryId: categoryId,
      categoryName: name,
    ));
    
    await _saveCategories();
    
    return categoryId;
  }

  Future<String> createTag({
    required String name,
    String? color,
  }) async {
    if (_tags.length >= _maxTags) {
      throw Exception('Maximum tags reached: $_maxTags');
    }
    
    final tagId = _generateTagId();
    
    final tag = NoteTag(
      id: tagId,
      name: name,
      color: color ?? '#3B82F6',
      createdAt: DateTime.now(),
      noteCount: 0,
    );
    
    _tags[tagId] = tag;
    _tagIndex.putIfAbsent(name.toLowerCase(), () => <String>[]).add(tagId);
    _totalTags++;
    
    developer.log('📝 Created tag: $name');
    
    _emitEvent(NoteEvent(
      type: NoteEventType.tagCreated,
      tagId: tagId,
      tagName: name,
    ));
    
    await _saveTags();
    
    return tagId;
  }

  Future<List<Note>> searchNotes({
    String? query,
    String? categoryId,
    List<String>? tagIds,
    NotePriority? priority,
    bool? isPinned,
    DateTime? createdAfter,
    DateTime? createdBefore,
    int? limit,
    String? sortBy,
    bool? ascending,
  }) async {
    var results = _notes.values.toList();
    
    // Apply filters
    if (query != null && query!.isNotEmpty) {
      final searchTerms = query!.toLowerCase().split(' ');
      results = results.where((note) {
        final searchText = '${note.title} ${note.content}'.toLowerCase();
        return searchTerms.every((term) => searchText.contains(term));
      }).toList();
    }
    
    if (categoryId != null) {
      results = results.where((note) => note.categoryId == categoryId).toList();
    }
    
    if (tagIds != null && tagIds!.isNotEmpty) {
      results = results.where((note) {
        return tagIds!.any((tagId) => note.tagIds.contains(tagId));
      }).toList();
    }
    
    if (priority != null) {
      results = results.where((note) => note.priority == priority).toList();
    }
    
    if (isPinned != null) {
      results = results.where((note) => note.isPinned == isPinned).toList();
    }
    
    if (createdAfter != null) {
      results = results.where((note) => note.createdAt.isAfter(createdAfter!)).toList();
    }
    
    if (createdBefore != null) {
      results = results.where((note) => note.createdAt.isBefore(createdBefore!)).toList();
    }
    
    // Apply sorting
    switch (sortBy) {
      case 'title':
        results.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'created':
        results.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'modified':
        results.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
        break;
      case 'accessed':
        results.sort((a, b) => a.accessedAt.compareTo(b.accessedAt));
        break;
      case 'priority':
        results.sort((a, b) => a.priority.index.compareTo(b.priority.index));
        break;
      default:
        results.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
    }
    
    if (ascending == false) {
      results = results.reversed.toList();
    }
    
    // Apply limit
    if (limit != null && limit! > 0) {
      results = results.take(limit!).toList();
    }
    
    return results;
  }

  Future<Note?> getNote(String noteId) async {
    final note = _notes[noteId];
    if (note != null) {
      note.accessedAt = DateTime.now();
      await _saveNotes();
    }
    return note;
  }

  Future<void> pinNote(String noteId) async {
    final note = _notes[noteId];
    if (note == null) {
      throw Exception('Note not found: $noteId');
    }
    
    note.isPinned = true;
    note.modifiedAt = DateTime.now();
    
    developer.log('📝 Pinned note: $noteId');
    
    _emitEvent(NoteEvent(
      type: NoteEventType.pinned,
      noteId: noteId,
    ));
    
    await _saveNotes();
  }

  Future<void> unpinNote(String noteId) async {
    final note = _notes[noteId];
    if (note == null) {
      throw Exception('Note not found: $noteId');
    }
    
    note.isPinned = false;
    note.modifiedAt = DateTime.now();
    
    developer.log('📝 Unpinned note: $noteId');
    
    _emitEvent(NoteEvent(
      type: NoteEventType.unpinned,
      noteId: noteId,
    ));
    
    await _saveNotes();
  }

  Future<String> exportNotes({
    String? format,
    String? categoryId,
    List<String>? tagIds,
  }) async {
    final exportFormat = format ?? 'json';
    final notesToExport = await searchNotes(
      categoryId: categoryId,
      tagIds: tagIds,
    );
    
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'termisol_notes_$timestamp.$exportFormat';
    final filePath = '$_notesDirectory/$fileName';
    
    switch (exportFormat) {
      case 'json':
        final data = {
          'version': '1.0',
          'exported_at': DateTime.now().toIso8601String(),
          'notes': notesToExport.map((note) => note.toJson()).toList(),
        };
        await File(filePath).writeAsString(jsonEncode(data));
        break;
        
      case 'markdown':
        final markdown = notesToExport.map((note) => _noteToMarkdown(note)).join('\n\n---\n\n');
        await File(filePath).writeAsString(markdown);
        break;
        
      case 'txt':
        final text = notesToExport.map((note) => '# ${note.title}\n\n${note.content}').join('\n\n---\n\n');
        await File(filePath).writeAsString(text);
        break;
        
      default:
        throw Exception('Unsupported export format: $exportFormat');
    }
    
    developer.log('📝 Exported ${notesToExport.length} notes to: $filePath');
    
    _emitEvent(NoteEvent(
      type: NoteEventType.exported,
      filePath: filePath,
      format: exportFormat,
      noteCount: notesToExport.length,
    ));
    
    return filePath;
  }

  String _noteToMarkdown(Note note) {
    final category = note.categoryId != null ? _categories[note.categoryId!] : null;
    final tags = note.tagIds.map((tagId) => _tags[tagId]?.name ?? '').where((name) => name.isNotEmpty).toList();
    
    var markdown = '# ${note.title}\n\n';
    
    if (category != null || tags.isNotEmpty) {
      markdown += '**';
      if (category != null) {
        markdown += '${category!.icon} ${category!.name}';
      }
      if (tags.isNotEmpty) {
        if (category != null) markdown += ' | ';
        markdown += tags.map((tag) => '#$tag').join(' ');
      }
      markdown += '**\n\n';
    }
    
    markdown += note.content;
    
    if (note.metadata.isNotEmpty) {
      markdown += '\n\n---\n\n**Metadata:**\n';
      note.metadata.forEach((key, value) {
        markdown += '- $key: $value\n';
      });
    }
    
    return markdown;
  }

  Future<void> importNotes(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('File not found: $filePath');
    }
    
    final content = await file.readAsString();
    final extension = filePath.split('.').last.toLowerCase();
    
    int importedCount = 0;
    
    try {
      switch (extension) {
        case 'json':
          final data = jsonDecode(content);
          for (final entry in data['notes']) {
            final note = Note.fromJson(entry);
            
            // Generate new ID to avoid conflicts
            note.id = _generateNoteId();
            note.createdAt = DateTime.now();
            note.modifiedAt = DateTime.now();
            note.accessedAt = DateTime.now();
            
            _notes[note.id] = note;
            _totalNotes++;
            _updateIndexes(note);
            importedCount++;
          }
          break;
          
        case 'md':
        case 'markdown':
          final notes = _parseMarkdownNotes(content);
          for (final note in notes) {
            note.id = _generateNoteId();
            _notes[note.id] = note;
            _totalNotes++;
            _updateIndexes(note);
            importedCount++;
          }
          break;
          
        case 'txt':
          final notes = _parseTextNotes(content);
          for (final note in notes) {
            note.id = _generateNoteId();
            _notes[note.id] = note;
            _totalNotes++;
            _updateIndexes(note);
            importedCount++;
          }
          break;
          
        default:
          throw Exception('Unsupported import format: $extension');
      }
      
      await _saveNotes();
      
      developer.log('📝 Imported $importedCount notes from: $filePath');
      
      _emitEvent(NoteEvent(
        type: NoteEventType.imported,
        filePath: filePath,
        noteCount: importedCount,
      ));
      
    } catch (e) {
      developer.log('📝 Failed to import notes: $e');
      rethrow;
    }
  }

  List<Note> _parseMarkdownNotes(String content) {
    final notes = <Note>[];
    final sections = content.split('\n\n---\n\n');
    
    for (final section in sections) {
      final lines = section.split('\n');
      if (lines.isEmpty || !lines.first.startsWith('# ')) continue;
      
      final title = lines.first.substring(2).trim();
      final contentLines = <String>[];
      bool inContent = false;
      
      for (final line in lines.skip(1)) {
        if (line.startsWith('**') && line.endsWith('**')) {
          continue; // Skip metadata lines
        }
        if (line.startsWith('---')) {
          break; // End of metadata
        }
        if (line.isNotEmpty) {
          inContent = true;
        }
        if (inContent) {
          contentLines.add(line);
        }
      }
      
      final noteContent = contentLines.join('\n').trim();
      
      if (title.isNotEmpty || noteContent.isNotEmpty) {
        notes.add(Note(
          id: '', // Will be set by caller
          title: title,
          content: noteContent,
          categoryId: 'general',
          tagIds: [],
          priority: NotePriority.normal,
          isPinned: false,
          isMarkdown: true,
          metadata: {},
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          accessedAt: DateTime.now(),
          wordCount: noteContent.split(' ').length,
          characterCount: noteContent.length,
        ));
      }
    }
    
    return notes;
  }

  List<Note> _parseTextNotes(String content) {
    final notes = <Note>[];
    final sections = content.split('\n\n---\n\n');
    
    for (final section in sections) {
      final lines = section.split('\n');
      if (lines.isEmpty || !lines.first.startsWith('# ')) continue;
      
      final title = lines.first.substring(2).trim();
      final contentLines = <String>[];
      bool inContent = false;
      
      for (final line in lines.skip(1)) {
        if (line.startsWith('---')) {
          break; // End of note
        }
        if (line.isNotEmpty) {
          inContent = true;
        }
        if (inContent) {
          contentLines.add(line);
        }
      }
      
      final noteContent = contentLines.join('\n').trim();
      
      if (title.isNotEmpty || noteContent.isNotEmpty) {
        notes.add(Note(
          id: '', // Will be set by caller
          title: title,
          content: noteContent,
          categoryId: 'general',
          tagIds: [],
          priority: NotePriority.normal,
          isPinned: false,
          isMarkdown: false,
          metadata: {},
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
          accessedAt: DateTime.now(),
          wordCount: noteContent.split(' ').length,
          characterCount: noteContent.length,
        ));
      }
    }
    
    return notes;
  }

  void _updateIndexes(Note note) {
    // Update category index
    if (note.categoryId != null) {
      _categoryIndex.putIfAbsent(note.categoryId!, () => <String>[]).add(note.id);
    }
    
    // Update tag index
    for (final tagId in note.tagIds) {
      _addTagToIndex(tagId, note.id);
    }
  }

  void _addTagToIndex(String tagId, String noteId) {
    final tag = _tags[tagId];
    if (tag != null) {
      _tagIndex.putIfAbsent(tag.name.toLowerCase(), () => <String>[]).add(noteId);
      tag.noteCount++;
    }
  }

  void _removeTagFromIndex(String tagId, String noteId) {
    final tag = _tags[tagId];
    if (tag != null) {
      final tagNotes = _tagIndex[tag.name.toLowerCase()];
      if (tagNotes != null) {
        tagNotes.remove(noteId);
        if (tagNotes.isEmpty) {
          _tagIndex.remove(tag.name.toLowerCase());
        }
      }
      tag.noteCount = max(0, tag.noteCount - 1);
    }
  }

  Future<void> _saveNotes() async {
    try {
      final file = File(_notesFile);
      
      final notesData = _notes.values.map((note) => note.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'notes': notesData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('📝 Failed to save notes: $e');
    }
  }

  Future<void> _saveCategories() async {
    try {
      final file = File(_categoriesFile);
      
      final categoriesData = _categories.values.map((category) => category.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'categories': categoriesData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('📝 Failed to save categories: $e');
    }
  }

  Future<void> _saveTags() async {
    try {
      final file = File(_tagsFile);
      
      final tagsData = _tags.values.map((tag) => tag.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'tags': tagsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('📝 Failed to save tags: $e');
    }
  }

  Note? getCurrentNote() {
    return _currentNote != null ? _notes[_currentNote!] : null;
  }

  void setCurrentNote(String? noteId) {
    _currentNote = noteId;
  }

  List<Note> getNotes() {
    return _notes.values.toList();
  }

  List<NoteCategory> getCategories() {
    return _categories.values.toList();
  }

  List<NoteTag> getTags() {
    return _tags.values.toList();
  }

  List<Note> getPinnedNotes() {
    return _notes.values.where((note) => note.isPinned).toList();
  }

  List<Note> getRecentNotes({int? limit}) {
    var recentNotes = _notes.values.toList();
    recentNotes.sort((a, b) => b.accessedAt.compareTo(a.accessedAt));
    
    if (limit != null && limit! > 0) {
      recentNotes = recentNotes.take(limit!).toList();
    }
    
    return recentNotes;
  }

  NoteTakingStats getStats() {
    return NoteTakingStats(
      totalNotes: _totalNotes,
      totalCategories: _totalCategories,
      totalTags: _totalTags,
      totalWords: _notes.values.fold(0, (sum, note) => sum + note.wordCount),
      totalCharacters: _notes.values.fold(0, (sum, note) => sum + note.characterCount),
      averageWordsPerNote: _notes.isNotEmpty 
          ? _notes.values.fold(0, (sum, note) => sum + note.wordCount) / _notes.length 
          : 0.0,
      pinnedNotes: _notes.values.where((note) => note.isPinned).length,
      notesByCategory: _categories.values.map((category) => MapEntry(
        category.name,
        category.noteCount,
      )).toList(),
      tagsByPopularity: _tags.values
          .where((tag) => tag.noteCount > 0)
          .map((tag) => MapEntry(tag.name, tag.noteCount))
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  String _generateNoteId() {
    return 'note_${DateTime.now().millisecondsSinceEpoch}_$_totalNotes';
  }

  String _generateCategoryId() {
    return 'cat_${DateTime.now().millisecondsSinceEpoch}_$_totalCategories';
  }

  String _generateTagId() {
    return 'tag_${DateTime.now().millisecondsSinceEpoch}_$_totalTags';
  }

  void _emitEvent(NoteEvent event) {
    _noteController.add(event);
  }

  Stream<NoteEvent> get noteEventStream => _noteController.stream;

  void dispose() {
    _autoSaveTimer?.cancel();
    
    _notes.clear();
    _categories.clear();
    _tags.clear();
    _tagIndex.clear();
    _categoryIndex.clear();
    _noteController.close();
    
    developer.log('📝 Built-in Note Taking disposed');
  }
}

class Note {
  final String id;
  String title;
  final String content;
  final String? categoryId;
  final List<String> tagIds;
  final NotePriority priority;
  final bool isPinned;
  final bool isMarkdown;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  DateTime modifiedAt;
  DateTime accessedAt;
  final int wordCount;
  final int characterCount;

  Note({
    required this.id,
    required this.title,
    required this.content,
    this.categoryId,
    required this.tagIds,
    required this.priority,
    required this.isPinned,
    required this.isMarkdown,
    required this.metadata,
    required this.createdAt,
    required this.modifiedAt,
    required this.accessedAt,
    required this.wordCount,
    required this.characterCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'category_id': categoryId,
      'tag_ids': tagIds,
      'priority': priority.name,
      'is_pinned': isPinned,
      'is_markdown': isMarkdown,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'modified_at': modifiedAt.toIso8601String(),
      'accessed_at': accessedAt.toIso8601String(),
      'word_count': wordCount,
      'character_count': characterCount,
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      categoryId: json['category_id'],
      tagIds: List<String>.from(json['tag_ids'] ?? []),
      priority: NotePriority.values.firstWhere(
        (priority) => priority.name == json['priority'],
        orElse: () => NotePriority.normal,
      ),
      isPinned: json['is_pinned'] ?? false,
      isMarkdown: json['is_markdown'] ?? true,
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      createdAt: DateTime.parse(json['created_at']),
      modifiedAt: DateTime.parse(json['modified_at']),
      accessedAt: DateTime.parse(json['accessed_at']),
      wordCount: json['word_count'] ?? 0,
      characterCount: json['character_count'] ?? 0,
    );
  }
}

class NoteCategory {
  final String id;
  String name;
  final String description;
  final String color;
  final String icon;
  final DateTime createdAt;
  int noteCount;

  NoteCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.icon,
    required this.createdAt,
    required this.noteCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'icon': icon,
      'created_at': createdAt.toIso8601String(),
      'note_count': noteCount,
    };
  }

  factory NoteCategory.fromJson(Map<String, dynamic> json) {
    return NoteCategory(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      color: json['color'],
      icon: json['icon'],
      createdAt: DateTime.parse(json['created_at']),
      noteCount: json['note_count'] ?? 0,
    );
  }
}

class NoteTag {
  final String id;
  final String name;
  final String color;
  final DateTime createdAt;
  int noteCount;

  NoteTag({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
    required this.noteCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'created_at': createdAt.toIso8601String(),
      'note_count': noteCount,
    };
  }

  factory NoteTag.fromJson(Map<String, dynamic> json) {
    return NoteTag(
      id: json['id'],
      name: json['name'],
      color: json['color'],
      createdAt: DateTime.parse(json['created_at']),
      noteCount: json['note_count'] ?? 0,
    );
  }
}

enum NotePriority {
  low,
  normal,
  high,
  urgent,
}

enum NoteEventType {
  created,
  updated,
  deleted,
  pinned,
  unpinned,
  categoryCreated,
  categoryUpdated,
  categoryDeleted,
  tagCreated,
  tagUpdated,
  tagDeleted,
  exported,
  imported,
}

class NoteEvent {
  final NoteEventType type;
  final String? noteId;
  final String? title;
  final String? categoryId;
  final String? categoryName;
  final String? tagId;
  final String? tagName;
  final String? filePath;
  final String? format;
  final int? noteCount;

  NoteEvent({
    required this.type,
    this.noteId,
    this.title,
    this.categoryId,
    this.categoryName,
    this.tagId,
    this.tagName,
    this.filePath,
    this.format,
    this.noteCount,
  });
}

class NoteTakingStats {
  final int totalNotes;
  final int totalCategories;
  final int totalTags;
  final int totalWords;
  final int totalCharacters;
  final double averageWordsPerNote;
  final int pinnedNotes;
  final List<MapEntry<String, int>> notesByCategory;
  final List<MapEntry<String, int>> tagsByPopularity;

  NoteTakingStats({
    required this.totalNotes,
    required this.totalCategories,
    required this.totalTags,
    required this.totalWords,
    required this.totalCharacters,
    required this.averageWordsPerNote,
    required this.pinnedNotes,
    required this.notesByCategory,
    required this.tagsByPopularity,
  });
}
