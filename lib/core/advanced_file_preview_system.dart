import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

class AdvancedFilePreviewSystem {
  static const String _configFile = '/home/house/.termisol_preview_config.json';
  static const String _cacheFile = '/home/house/.termisol_preview_cache.json';
  static const int _maxPreviewSize = 10 * 1024 * 1024; // 10MB
  static const int _maxCacheEntries = 1000;
  static const Duration _cleanupInterval = Duration(hours: 1);
  static const Duration _previewTimeout = Duration(seconds: 5);
  
  final Map<String, PreviewCache> _cache = {};
  final Map<String, FilePreview> _previews = {};
  final Map<String, PreviewGenerator> _generators = {};
  final Map<String, List<PreviewPlugin>> _plugins = {};
  
  Timer? _cleanupTimer;
  int _totalPreviews = 0;
  int _totalCacheEntries = 0;
  int _totalGenerators = 0;
  int _totalPlugins = 0;
  
  final StreamController<PreviewEvent> _previewController = 
      StreamController<PreviewEvent>.broadcast();

  void initialize() {
    _loadConfiguration();
    _loadCache();
    _loadGenerators();
    _loadPlugins();
    _initializeDefaultGenerators();
    _startTimers();
    developer.log('👁 Advanced File Preview System initialized');
  }

  void _loadConfiguration() {
    try {
      final file = File(_configFile);
      if (!file.existsSync()) {
        developer.log('👁 No existing preview configuration found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      // Load generators
      for (final entry in data['generators']) {
        final generator = PreviewGenerator.fromJson(entry);
        _generators[generator.id] = generator;
        _totalGenerators++;
      }
      
      // Load plugins
      for (final entry in data['plugins']) {
        final plugins = (entry['plugins'] as List)
            .map((plugin) => PreviewPlugin.fromJson(plugin))
            .toList();
        
        for (final plugin in plugins) {
          _plugins[plugin.id] = plugin;
          _totalPlugins++;
        }
      }
      
      developer.log('👁 Loaded ${_generators.length} generators, ${_plugins.values.fold(0, (sum, list) => sum + list.length)} plugins');
      
    } catch (e) {
      developer.log('👁 Failed to load preview configuration: $e');
    }
  }

  void _loadCache() {
    try {
      final file = File(_cacheFile);
      if (!file.existsSync()) {
        developer.log('👁 No existing preview cache found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['cache']) {
        final cache = PreviewCache.fromJson(entry);
        _cache[cache.id] = cache;
        _totalCacheEntries++;
      }
      
      developer.log('👁 Loaded ${_cache.length} cache entries');
      
    } catch (e) {
      developer.log('👁 Failed to load preview cache: $e');
    }
  }

  void _loadGenerators() {
    // Generators are loaded in _loadConfiguration
  }

  void _loadPlugins() {
    // Plugins are loaded in _loadConfiguration
  }

  void _initializeDefaultGenerators() {
    if (_generators.isEmpty) {
      final defaultGenerators = [
        // Text generator
        PreviewGenerator(
          id: 'text',
          name: 'Text Files',
          description: 'Preview for plain text files',
          extensions: ['.txt', '.md', '.rst', '.log', '.csv', '.json', '.yaml', '.yml', '.xml', '.toml', '.ini', '.cfg', '.conf'],
          mimeType: 'text/plain',
          maxFileSize: _maxPreviewSize,
          encoding: 'utf8',
          syntaxHighlighting: true,
          lineNumbers: true,
          wordWrap: true,
          enabled: true,
          createdAt: DateTime.now(),
        ),
        
        // Image generator
        PreviewGenerator(
          id: 'image',
          name: 'Image Files',
          description: 'Preview for image files',
          extensions: ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.avif', '.svg', '.ico', '.tiff', '.heic', '.psd'],
          mimeType: 'image/*',
          maxFileSize: _maxPreviewSize,
          thumbnailSize: '256x256',
          enableThumbnails: true,
          enableMetadata: true,
          enableZoom: true,
          enabled: true,
          createdAt: DateTime.now(),
        ),
        
        // Video generator
        PreviewGenerator(
          id: 'video',
          name: 'Video Files',
          description: 'Preview for video files',
          extensions: ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.3gp', '.ogv'],
          mimeType: 'video/*',
          maxFileSize: _maxPreviewSize,
          thumbnailSize: '320x180',
          enableThumbnails: true,
          enableMetadata: true,
          enableStreaming: true,
          enabled: true,
          createdAt: DateTime.now(),
        ),
        
        // Audio generator
        PreviewGenerator(
          id: 'audio',
          name: 'Audio Files',
          description: 'Preview for audio files',
          extensions: ['.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma', '.opus'],
          mimeType: 'audio/*',
          maxFileSize: _maxPreviewSize,
          enableWaveform: true,
          enableMetadata: true,
          enableStreaming: true,
          enabled: true,
          createdAt: DateTime.now(),
        ),
        
        // PDF generator
        PreviewGenerator(
          id: 'pdf',
          name: 'PDF Documents',
          description: 'Preview for PDF files',
          extensions: ['.pdf', '.ps', '.eps', '.ai'],
          mimeType: 'application/pdf',
          maxFileSize: _maxPreviewSize,
          enableTextExtraction: true,
          enablePageNavigation: true,
          enableThumbnails: true,
          enabled: true,
          createdAt: DateTime.now(),
        ),
        
        // Code generator
        PreviewGenerator(
          id: 'code',
          name: 'Code Files',
          description: 'Preview for source code files',
          extensions: ['.dart', '.py', '.js', '.ts', '.java', '.kt', '.rs', '.go', '.cpp', '.c', '.h', '.hpp', '.cs', '.php', '.rb', '.swift', '.scala', '.sh', '.bat', '.ps1'],
          mimeType: 'text/x-code',
          maxFileSize: _maxPreviewSize,
          syntaxHighlighting: true,
          lineNumbers: true,
          wordWrap: false,
          enableFolding: true,
          enableMinimap: true,
          enabled: true,
          createdAt: DateTime.now(),
        ),
        
        // Archive generator
        PreviewGenerator(
          id: 'archive',
          name: 'Archive Files',
          description: 'Preview for compressed archives',
          extensions: ['.zip', '.tar', '.gz', '.tgz', '.bz2', '.xz', '.7z', '.rar', '.deb', '.rpm', '.dmg', '.iso'],
          mimeType: 'application/zip',
          maxFileSize: _maxPreviewSize,
          enableListing: true,
          enableExtraction: true,
          enabled: true,
          createdAt: DateTime.now(),
        ),
        
        // Spreadsheet generator
        PreviewGenerator(
          id: 'spreadsheet',
          name: 'Spreadsheet Files',
          description: 'Preview for spreadsheet files',
          extensions: ['.xls', '.xlsx', '.csv', '.ods', '.numbers', '.et'],
          mimeType: 'application/vnd.ms-excel',
          maxFileSize: _maxPreviewSize,
          enableGrid: true,
          enableFormulas: true,
          enableCharts: true,
          enabled: true,
          createdAt: DateTime.now(),
        ),
        
        // Document generator
        PreviewGenerator(
          id: 'document',
          name: 'Document Files',
          description: 'Preview for office documents',
          extensions: ['.doc', '.docx', '.odt', '.rtf', '.wps', '.pages', '.key'],
          mimeType: 'application/msword',
          maxFileSize: _maxPreviewSize,
          enableTextExtraction: true,
          enablePageNavigation: true,
          enableThumbnails: true,
          enabled: true,
          createdAt: DateTime.now(),
        ),
        
        // Binary generator
        PreviewGenerator(
          id: 'binary',
          name: 'Binary Files',
          description: 'Preview for binary files',
          extensions: ['.exe', '.dll', '.so', '.dylib', '.bin', '.dat', '.db', '.sqlite', '.img', '.iso'],
          mimeType: 'application/octet-stream',
          maxFileSize: _maxPreviewSize,
          enableHexView: true,
          enableAnalysis: true,
          enableStrings: true,
          enabled: true,
          createdAt: DateTime.now(),
        ),
      ];
      
      for (final generator in defaultGenerators) {
        _generators[generator.id] = generator;
        _totalGenerators++;
      }
      
      developer.log('👁 Initialized ${defaultGenerators.length} default generators');
      
      _saveConfiguration();
    }
  }

  void _startTimers() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _performCleanup());
  }

  Future<FilePreview?> generatePreview({
    required String filePath,
    String? generatorId,
    Map<String, dynamic>? options,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('File not found: $filePath');
    }
    
    final fileSize = await file.length();
    if (fileSize > _maxPreviewSize) {
      throw Exception('File too large for preview: $fileSize bytes');
    }
    
    // Check cache first
    final cacheKey = _getCacheKey(filePath, options);
    final cached = _cache[cacheKey];
    
    if (cached != null && !isCacheExpired(cached)) {
      developer.log('👁 Using cached preview for: $filePath');
      return cached.preview;
    }
    
    // Determine generator
    final generator = generatorId != null 
        ? _generators[generatorId]
        : _getGeneratorForFile(filePath);
    
    if (generator == null || !generator.enabled) {
      throw Exception('No suitable generator found for: $filePath');
    }
    
    try {
      developer.log('👁 Generating preview for: $filePath (${generator.name})');
      
      final preview = await _generatePreviewWithGenerator(file, generator, options ?? {});
      
      // Cache the result
      await _cachePreview(cacheKey, preview);
      
      _emitEvent(PreviewEvent(
        type: PreviewEventType.previewGenerated,
        filePath: filePath,
        generatorId: generator.id,
        previewId: preview.id,
      ));
      
      return preview;
      
    } catch (e) {
      developer.log('👁 Failed to generate preview for $filePath: $e');
      
      _emitEvent(PreviewEvent(
        type: PreviewEventType.previewFailed,
        filePath: filePath,
        generatorId: generator.id,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  PreviewGenerator? _getGeneratorForFile(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    
    for (final generator in _generators.values) {
      if (generator.extensions.contains(extension)) {
        return generator;
      }
    }
    
    return null;
  }

  Future<FilePreview> _generatePreviewWithGenerator(
    File file,
    PreviewGenerator generator,
    Map<String, dynamic> options,
  ) async {
    final filePath = file.path;
    final fileSize = await file.length();
    final lastModified = await file.lastModified();
    final previewId = _generatePreviewId();
    
    switch (generator.id) {
      case 'text':
        return await _generateTextPreview(file, previewId, options);
      case 'image':
        return await _generateImagePreview(file, previewId, options);
      case 'video':
        return await _generateVideoPreview(file, previewId, options);
      case 'audio':
        return await _generateAudioPreview(file, previewId, options);
      case 'pdf':
        return await _generatePdfPreview(file, previewId, options);
      case 'code':
        return await _generateCodePreview(file, previewId, options);
      case 'archive':
        return await _generateArchivePreview(file, previewId, options);
      case 'spreadsheet':
        return await _generateSpreadsheetPreview(file, previewId, options);
      case 'document':
        return await _generateDocumentPreview(file, previewId, options);
      case 'binary':
        return await _generateBinaryPreview(file, previewId, options);
      default:
        throw Exception('Unknown generator: ${generator.id}');
    }
  }

  Future<FilePreview> _generateTextPreview(
    File file,
    String previewId,
    Map<String, dynamic> options,
  ) async {
    final content = await file.readAsString();
    final lines = content.split('\n');
    
    return FilePreview(
      id: previewId,
      filePath: file.path,
      generatorId: 'text',
      type: PreviewType.text,
      content: content,
      metadata: {
        'line_count': lines.length,
        'character_count': content.length,
        'encoding': options['encoding'] ?? 'utf8',
        'word_count': content.split(RegExp(r'\s+')).length,
        'estimated_read_time': content.length / 1000, // Rough estimate
      },
      thumbnail: null,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
    );
  }

  Future<FilePreview> _generateImagePreview(
    File file,
    String previewId,
    Map<String, dynamic> options,
  ) async {
    final bytes = await file.readAsBytes();
    final thumbnailSize = options['thumbnail_size'] ?? '256x256';
    
    // Generate thumbnail
    final thumbnail = await _generateImageThumbnail(bytes, thumbnailSize);
    
    // Extract metadata
    final metadata = await _extractImageMetadata(bytes);
    
    return FilePreview(
      id: previewId,
      filePath: file.path,
      generatorId: 'image',
      type: PreviewType.image,
      content: base64Encode(bytes),
      metadata: {
        'file_size': bytes.length,
        'format': metadata['format'],
        'width': metadata['width'],
        'height': metadata['height'],
        'color_space': metadata['color_space'],
        'has_transparency': metadata['has_transparency'],
        'thumbnail_size': thumbnailSize,
      },
      thumbnail: thumbnail,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
    );
  }

  Future<FilePreview> _generateVideoPreview(
    File file,
    String previewId,
    Map<String, dynamic> options,
  ) async {
    final bytes = await file.readAsBytes();
    final thumbnailSize = options['thumbnail_size'] ?? '320x180';
    
    // Generate video thumbnail
    final thumbnail = await _generateVideoThumbnail(file.path, thumbnailSize);
    
    // Extract video metadata
    final metadata = await _extractVideoMetadata(file.path);
    
    return FilePreview(
      id: previewId,
      filePath: file.path,
      generatorId: 'video',
      type: PreviewType.video,
      content: 'Video file preview',
      metadata: {
        'file_size': bytes.length,
        'format': metadata['format'],
        'duration': metadata['duration'],
        'width': metadata['width'],
        'height': metadata['height'],
        'fps': metadata['fps'],
        'has_audio': metadata['has_audio'],
        'thumbnail_size': thumbnailSize,
      },
      thumbnail: thumbnail,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
    );
  }

  Future<FilePreview> _generateAudioPreview(
    File file,
    String previewId,
    Map<String, dynamic> options,
  ) async {
    final bytes = await file.readAsBytes();
    
    // Generate waveform
    final waveform = await _generateAudioWaveform(bytes);
    
    // Extract audio metadata
    final metadata = await _extractAudioMetadata(bytes);
    
    return FilePreview(
      id: previewId,
      filePath: file.path,
      generatorId: 'audio',
      type: PreviewType.audio,
      content: 'Audio file preview',
      metadata: {
        'file_size': bytes.length,
        'format': metadata['format'],
        'duration': metadata['duration'],
        'sample_rate': metadata['sample_rate'],
        'channels': metadata['channels'],
        'bitrate': metadata['bitrate'],
        'has_waveform': waveform != null,
      },
      thumbnail: null,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
    );
  }

  Future<FilePreview> _generatePdfPreview(
    File file,
    String previewId,
    Map<String, dynamic> options,
  ) async {
    final bytes = await file.readAsBytes();
    
    // Extract PDF text
    final text = await _extractPdfText(file);
    
    // Generate PDF thumbnail
    final thumbnail = await _generatePdfThumbnail(file.path);
    
    return FilePreview(
      id: previewId,
      filePath: file.path,
      generatorId: 'pdf',
      type: PreviewType.pdf,
      content: text,
      metadata: {
        'file_size': bytes.length,
        'page_count': _countPdfPages(bytes),
        'has_text': text.isNotEmpty,
        'text_length': text.length,
        'has_thumbnail': thumbnail != null,
      },
      thumbnail: thumbnail,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
    );
  }

  Future<FilePreview> _generateCodePreview(
    File file,
    String previewId,
    Map<String, dynamic> options,
  ) async {
    final content = await file.readAsString();
    final extension = path.extension(file.path).toLowerCase();
    
    // Detect language
    final language = _detectCodeLanguage(extension, content);
    
    // Extract code structure
    final structure = _analyzeCodeStructure(content, language);
    
    return FilePreview(
      id: previewId,
      filePath: file.path,
      generatorId: 'code',
      type: PreviewType.code,
      content: content,
      metadata: {
        'language': language,
        'line_count': structure['line_count'],
        'function_count': structure['function_count'],
        'class_count': structure['class_count'],
        'import_count': structure['import_count'],
        'has_syntax_highlighting': true,
        'supports_folding': true,
      },
      thumbnail: null,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
    );
  }

  Future<FilePreview> _generateArchivePreview(
    File file,
    String previewId,
    Map<String, dynamic> options,
  ) async {
    final listing = await _extractArchiveListing(file);
    
    return FilePreview(
      id: previewId,
      filePath: file.path,
      generatorId: 'archive',
      type: PreviewType.archive,
      content: 'Archive file listing',
      metadata: {
        'file_count': listing['file_count'],
        'total_size': listing['total_size'],
        'compression_type': listing['compression_type'],
        'has_listing': listing['files'].isNotEmpty,
      },
      thumbnail: null,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
    );
  }

  Future<FilePreview> _generateSpreadsheetPreview(
    File file,
    String previewId,
    Map<String, dynamic> options,
  ) async {
    final data = await _extractSpreadsheetData(file);
    
    return FilePreview(
      id: previewId,
      filePath: file.path,
      generatorId: 'spreadsheet',
      type: PreviewType.spreadsheet,
      content: 'Spreadsheet data preview',
      metadata: {
        'row_count': data['row_count'],
        'column_count': data['column_count'],
        'sheet_count': data['sheet_count'],
        'has_data': data['rows'].isNotEmpty,
      },
      thumbnail: null,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
    );
  }

  Future<FilePreview> _generateDocumentPreview(
    File file,
    String previewId,
    Map<String, dynamic> options,
  ) async {
    final text = await _extractDocumentText(file);
    final thumbnail = await _generateDocumentThumbnail(file.path);
    
    return FilePreview(
      id: previewId,
      filePath: file.path,
      generatorId: 'document',
      type: PreviewType.document,
      content: text,
      metadata: {
        'file_size': await file.length(),
        'has_text': text.isNotEmpty,
        'text_length': text.length,
        'has_thumbnail': thumbnail != null,
      },
      thumbnail: thumbnail,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
    );
  }

  Future<FilePreview> _generateBinaryPreview(
    File file,
    String previewId,
    Map<String, dynamic> options,
  ) async {
    final bytes = await file.readAsBytes();
    
    // Generate hex view
    final hexView = _generateHexView(bytes);
    
    // Analyze binary
    final analysis = _analyzeBinaryData(bytes);
    
    return FilePreview(
      id: previewId,
      filePath: file.path,
      generatorId: 'binary',
      type: PreviewType.binary,
      content: hexView,
      metadata: {
        'file_size': bytes.length,
        'entropy': analysis['entropy'],
        'file_type': analysis['file_type'],
        'has_strings': analysis['has_strings'],
        'has_executable': analysis['has_executable'],
        'hex_view': true,
      },
      thumbnail: null,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
    );
  }

  Future<String?> _generateImageThumbnail(Uint8List bytes, String size) async {
    // Simplified thumbnail generation
    // In practice, this would use image processing libraries
    try {
      // For now, return a placeholder
      return 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/8+QhVAGIwAAAABJRU5ErkJggg==';
    } catch (e) {
      developer.log('👁 Failed to generate image thumbnail: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _extractImageMetadata(Uint8List bytes) async {
    // Simplified image metadata extraction
    // In practice, this would use image processing libraries
    return {
      'format': 'unknown',
      'width': 0,
      'height': 0,
      'color_space': 'unknown',
      'has_transparency': false,
    };
  }

  Future<String?> _generateVideoThumbnail(String filePath, String size) async {
    // Simplified video thumbnail generation
    // In practice, this would use FFmpeg or similar
    try {
      // For now, return a placeholder
      return 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/8+QhVAGIwAAAABJRU5ErkJggg==';
    } catch (e) {
      developer.log('👁 Failed to generate video thumbnail: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _extractVideoMetadata(String filePath) async {
    // Simplified video metadata extraction
    // In practice, this would use FFmpeg or similar
    return {
      'format': 'unknown',
      'duration': 0.0,
      'width': 0,
      'height': 0,
      'fps': 0.0,
      'has_audio': false,
    };
  }

  Future<String?> _generateAudioWaveform(Uint8List bytes) async {
    // Simplified audio waveform generation
    // In practice, this would use audio processing libraries
    return null;
  }

  Future<Map<String, dynamic>> _extractAudioMetadata(Uint8List bytes) async {
    // Simplified audio metadata extraction
    // In practice, this would use audio processing libraries
    return {
      'format': 'unknown',
      'duration': 0.0,
      'sample_rate': 44100,
      'channels': 2,
      'bitrate': 128000,
    };
  }

  Future<String> _extractPdfText(File file) async {
    // Simplified PDF text extraction
    // In practice, this would use PDF parsing libraries
    try {
      final result = await Process.run('pdftotext', [file.path], timeout: _previewTimeout);
      if (result.exitCode == 0) {
        return result.stdout as String;
      }
    } catch (e) {
      developer.log('👁 Failed to extract PDF text: $e');
    }
    
    return '';
  }

  Future<String?> _generatePdfThumbnail(String filePath) async {
    // Simplified PDF thumbnail generation
    // In practice, this would use Ghostscript or similar
    try {
      final result = await Process.run('gs', [
        '-dNOPAUSE',
        '-dBATCH',
        '-dSAFER',
        '-dTextAlphaBits=4',
        '-dNOPROMPT',
        '-dFirstPage=1',
        '-dLastPage=1',
        '-sDEVICE=png16m',
        '-dDEVICEWIDTH=256',
        '-dDEVICEHEIGHT=256',
        '-sOutputFile=/dev/stdout',
        filePath,
      ], timeout: _previewTimeout);
      
      if (result.exitCode == 0) {
        final pngBytes = result.stdout as String;
        return 'data:image/png;base64,$pngBytes';
      }
    } catch (e) {
      developer.log('👁 Failed to generate PDF thumbnail: $e');
    }
    
    return null;
  }

  int _countPdfPages(Uint8List bytes) {
    // Simplified PDF page counting
    // In practice, this would use PDF parsing libraries
    return 1;
  }

  String _detectCodeLanguage(String extension, String content) {
    final extensionMap = {
      '.dart': 'dart',
      '.py': 'python',
      '.js': 'javascript',
      '.ts': 'typescript',
      '.java': 'java',
      '.kt': 'kotlin',
      '.rs': 'rust',
      '.go': 'go',
      '.cpp': 'cpp',
      '.c': 'c',
      '.h': 'c',
      '.hpp': 'cpp',
      '.cs': 'csharp',
      '.php': 'php',
      '.rb': 'ruby',
      '.swift': 'swift',
      '.scala': 'scala',
      '.sh': 'shell',
      '.bat': 'batch',
      '.ps1': 'powershell',
    };
    
    return extensionMap[extension] ?? 'text';
  }

  Map<String, dynamic> _analyzeCodeStructure(String content, String language) {
    final lines = content.split('\n');
    
    // Simple structure analysis
    final functionCount = RegExp(r'\b(function|def|class|interface|trait|impl|fn)\b').allMatches(content).length;
    final classCount = RegExp(r'\bclass\b').allMatches(content).length;
    final importCount = RegExp(r'\b(import|include|require|use)\b').allMatches(content).length;
    
    return {
      'line_count': lines.length,
      'function_count': functionCount,
      'class_count': classCount,
      'import_count': importCount,
    };
  }

  Future<Map<String, dynamic>> _extractArchiveListing(File file) async {
    // Simplified archive listing
    // In practice, this would use archive libraries
    try {
      String command;
      if (file.path.endsWith('.zip')) {
        command = 'unzip -l "$file"';
      } else if (file.path.endsWith('.tar.gz') || file.path.endsWith('.tgz')) {
        command = 'tar -tzf "$file"';
      } else if (file.path.endsWith('.tar')) {
        command = 'tar -tf "$file"';
      } else {
        return {'file_count': 0, 'total_size': 0, 'compression_type': 'unknown', 'files': []};
      }
      
      final result = await Process.run(command, [], timeout: _previewTimeout);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final lines = output.split('\n');
        final files = <Map<String, dynamic>>[];
        int totalSize = 0;
        
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          
          // Parse file listing (simplified)
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final size = int.tryParse(parts[0]) ?? 0;
            final date = parts[1];
            final time = parts[2];
            final name = parts.sublist(3).join(' ');
            
            files.add({
              'name': name,
              'size': size,
              'date': date,
              'time': time,
            });
            
            totalSize += size;
          }
        }
        
        return {
          'file_count': files.length,
          'total_size': totalSize,
          'compression_type': 'unknown',
          'files': files,
        };
      }
    } catch (e) {
      developer.log('👁 Failed to extract archive listing: $e');
      return {'file_count': 0, 'total_size': 0, 'compression_type': 'unknown', 'files': []};
    }
  }

  Future<Map<String, dynamic>> _extractSpreadsheetData(File file) async {
    // Simplified spreadsheet data extraction
    // In practice, this would use spreadsheet libraries
    try {
      String command;
      if (file.path.endsWith('.csv')) {
        command = 'head -10 "$file"';
      } else if (file.path.endsWith('.xlsx')) {
        command = 'python3 -c "import pandas as pd; print(pd.read_excel(\"$file\").shape)"';
      } else {
        return {'row_count': 0, 'column_count': 0, 'sheet_count': 0, 'rows': []};
      }
      
      final result = await Process.run(command, [], timeout: _previewTimeout);
      if (result.exitCode == 0) {
        final output = result.stdout as String;
        
        if (file.path.endsWith('.csv')) {
          final lines = output.split('\n');
          return {
            'row_count': lines.length,
            'column_count': lines.isNotEmpty ? lines.first.split(',').length : 0,
            'sheet_count': 1,
            'rows': lines.map((line) => line.split(',')).toList(),
          };
        } else {
          // Parse pandas output (simplified)
          final match = RegExp(r'\((\d+),\s*(\d+)\)').firstMatch(output);
          if (match != null) {
            return {
              'row_count': int.tryParse(match.group(1)!) ?? 0,
              'column_count': int.tryParse(match.group(2)!) ?? 0,
              'sheet_count': 1,
              'rows': [],
            };
          }
        }
      }
    } catch (e) {
      developer.log('👁 Failed to extract spreadsheet data: $e');
      return {'row_count': 0, 'column_count': 0, 'sheet_count': 0, 'rows': []};
    }
  }

  Future<String> _extractDocumentText(File file) async {
    // Simplified document text extraction
    // In practice, this would use document parsing libraries
    try {
      if (file.path.endsWith('.pdf')) {
        return await _extractPdfText(file);
      } else if (file.path.endsWith('.docx')) {
        final result = await Process.run('unzip', ['-p', file.path], timeout: _previewTimeout);
        if (result.exitCode == 0) {
          // Extract from docx (simplified)
          return 'Document text extraction not implemented for docx files';
        }
      }
    } catch (e) {
      developer.log('👁 Failed to extract document text: $e');
    }
    
    return '';
  }

  Future<String?> _generateDocumentThumbnail(String filePath) async {
    // Simplified document thumbnail generation
    // In practice, this would use document processing libraries
    return null;
  }

  String _generateHexView(Uint8List bytes) {
    final lines = <String>[];
    
    for (int i = 0; i < bytes.length; i += 16) {
      final hexLine = <String>[];
      
      // Add offset
      hexLine.add('${i.toRadixString(16).padLeft(8, '0')}  ');
      
      // Add hex values
      for (int j = i; j < math.min(i + 16, bytes.length); j++) {
        hexLine.add(bytes[j].toRadixString(16).padLeft(2, '0'));
      }
      
      // Add ASCII representation
      final asciiLine = <String>[];
      for (int j = i; j < math.min(i + 16, bytes.length); j++) {
        final byte = bytes[j];
        if (byte >= 32 && byte <= 126) {
          asciiLine.add(String.fromCharCode(byte));
        } else {
          asciiLine.add('.');
        }
      }
      
      lines.add('${hexLine.join(' ')}  ${asciiLine.join('')}');
    }
    
    return lines.join('\n');
  }

  Map<String, dynamic> _analyzeBinaryData(Uint8List bytes) {
    final entropy = _calculateEntropy(bytes);
    final hasStrings = bytes.any((byte) => byte >= 32 && byte <= 126);
    final hasExecutable = bytes.take(4).toList() == [0x7F, 0x45, 0x4C, 0x46]; // ELF magic
    
    return {
      'entropy': entropy,
      'file_type': _detectFileType(bytes),
      'has_strings': hasStrings,
      'has_executable': hasExecutable,
    };
  }

  double _calculateEntropy(Uint8List bytes) {
    if (bytes.isEmpty) return 0.0;
    
    final frequencies = List.filled(256, 0);
    for (final byte in bytes) {
      frequencies[byte]++;
    }
    
    double entropy = 0.0;
    for (final freq in frequencies) {
      if (freq > 0) {
        final probability = freq / bytes.length;
        entropy -= probability * math.log(probability) / math.log(2);
      }
    }
    
    return entropy;
  }

  String _detectFileType(Uint8List bytes) {
    if (bytes.length < 4) return 'unknown';
    
    // Check common file signatures
    final signatures = {
      [0x50, 0x4B, 0x03, 0x04]: 'pdf',
      [0x89, 0x50, 0x4E, 0x47]: 'png',
      [0xFF, 0xD8, 0xFF, 0xE0]: 'jpg',
      [0x47, 0x49, 0x46, 0x38]: 'gif',
      [0x7F, 0x45, 0x4C, 0x46]: 'elf',
      [0x50, 0x4B, 0x03, 0x04, 0x0A, 0x04, 0x05, 0x00]: 'zip',
    };
    
    for (final entry in signatures.entries) {
      final signature = entry.key;
      if (bytes.length >= signature.length) {
        bool matches = true;
        for (int i = 0; i < signature.length; i++) {
          if (bytes[i] != signature[i]) {
            matches = false;
            break;
          }
        }
        if (matches) {
          return entry.value;
        }
      }
    }
    
    return 'unknown';
  }

  String _getCacheKey(String filePath, Map<String, dynamic> options) {
    final file = File(filePath);
    final modified = await file.lastModified();
    final optionsHash = options.toString();
    
    return '${filePath}_${modified.millisecondsSinceEpoch}_$optionsHash';
  }

  bool isCacheExpired(PreviewCache cache) {
    return DateTime.now().isAfter(cache.expiresAt);
  }

  Future<void> _cachePreview(String cacheKey, FilePreview preview) async {
    if (_cache.length >= _maxCacheEntries) {
      _performCacheCleanup();
    }
    
    final cacheEntry = PreviewCache(
      id: cacheKey,
      preview: preview,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(Duration(hours: 24)),
      accessCount: 1,
      lastAccessed: DateTime.now(),
    );
    
    _cache[cacheKey] = cacheEntry;
    _totalCacheEntries++;
    
    await _saveCache();
  }

  Future<void> _performCacheCleanup() async {
    final cutoffDate = DateTime.now().subtract(Duration(days: 7));
    
    final toRemove = <String>[];
    for (final entry in _cache.entries) {
      if (entry.value.createdAt.isBefore(cutoffDate) && 
          entry.value.accessCount < 2) { // Remove old, unused entries
        toRemove.add(entry.key);
      }
    }
    
    for (final key in toRemove) {
      _cache.remove(key);
      _totalCacheEntries--;
    }
    
    if (toRemove.isNotEmpty) {
      developer.log('👁 Cleaned ${toRemove.length} expired cache entries');
      
      await _saveCache();
    }
  }

  Future<void> _saveCache() async {
    try {
      final file = File(_cacheFile);
      
      final cacheData = _cache.entries.map((entry) => entry.value.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'cache': cacheData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('👁 Failed to save cache: $e');
    }
  }

  Future<void> _saveConfiguration() async {
    try {
      final file = File(_configFile);
      
      final generatorsData = _generators.values.map((generator) => generator.toJson()).toList();
      final pluginsData = <String, dynamic>{};
      
      for (final entry in _plugins.entries) {
        pluginsData[entry.key] = entry.value.map((plugin) => plugin.toJson()).toList();
      }
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'generators': generatorsData,
        'plugins': pluginsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('👁 Failed to save configuration: $e');
    }
  }

  Future<void> _performCleanup() async {
    // Clean expired previews
    final expiredPreviews = <String>[];
    for (final entry in _previews.entries) {
      if (DateTime.now().isAfter(entry.value.expiresAt)) {
        expiredPreviews.add(entry.key);
      }
    }
    
    for (final key in expiredPreviews) {
      _previews.remove(key);
      _totalPreviews--;
    }
    
    // Clean expired cache entries
    await _performCacheCleanup();
    
    if (expiredPreviews.isNotEmpty) {
      developer.log('👁 Cleaned ${expiredPreviews.length} expired previews');
      
      _emitEvent(PreviewEvent(
        type: PreviewEventType.cleanup,
        expiredCount: expiredPreviews.length,
      ));
    }
    
    await _saveConfiguration();
  }

  Future<String> createGenerator({
    required String name,
    required String description,
    required List<String> extensions,
    required String mimeType,
    Map<String, dynamic>? config,
  }) async {
    final generatorId = _generateGeneratorId();
    
    final generator = PreviewGenerator(
      id: generatorId,
      name: name,
      description: description,
      extensions: extensions,
      mimeType: mimeType,
      config: config ?? {},
      maxFileSize: _maxPreviewSize,
      enabled: true,
      createdAt: DateTime.now(),
    );
    
    _generators[generatorId] = generator;
    _totalGenerators++;
    
    developer.log('👁 Created generator: $name');
    
    _emitEvent(PreviewEvent(
      type: PreviewEventType.generatorCreated,
      generatorId: generatorId,
      generatorName: name,
    ));
    
    await _saveConfiguration();
    
    return generatorId;
  }

  Future<String> createPlugin({
    required String name,
    required String description,
    required String generatorId,
    required Map<String, dynamic> config,
  }) async {
    final pluginId = _generatePluginId();
    
    final plugin = PreviewPlugin(
      id: pluginId,
      name: name,
      description: description,
      generatorId: generatorId,
      config: config,
      enabled: true,
      createdAt: DateTime.now(),
    );
    
    if (!_plugins.containsKey(generatorId)) {
      _plugins[generatorId] = <PreviewPlugin>[];
    }
    
    _plugins[generatorId]!.add(plugin);
    _totalPlugins++;
    
    developer.log('👁 Created plugin: $name for generator $generatorId');
    
    _emitEvent(PreviewEvent(
      type: PreviewEventType.pluginCreated,
      pluginId: pluginId,
      pluginName: name,
      generatorId: generatorId,
    ));
    
    await _saveConfiguration();
    
    return pluginId;
  }

  FilePreview? getPreview(String previewId) {
    return _previews[previewId];
  }

  List<FilePreview> getPreviews({String? generatorId}) {
    var previews = _previews.values.toList();
    
    if (generatorId != null) {
      previews = previews.where((preview) => preview.generatorId == generatorId).toList();
    }
    
    return previews;
  }

  PreviewGenerator? getGenerator(String generatorId) {
    return _generators[generatorId];
  }

  List<PreviewGenerator> getGenerators() {
    return _generators.values.toList();
  }

  List<PreviewPlugin> getPlugins({String? generatorId}) {
    if (generatorId != null) {
      return _plugins[generatorId] ?? [];
    }
    
    final allPlugins = <PreviewPlugin>[];
    for (final plugins in _plugins.values) {
      allPlugins.addAll(plugins);
    }
    
    return allPlugins;
  }

  Future<void> clearCache() async {
    _cache.clear();
    _totalCacheEntries = 0;
    
    developer.log('👁 Cleared preview cache');
    
    _emitEvent(PreviewEvent(
      type: PreviewEventType.cacheCleared,
    ));
    
    await _saveCache();
  }

  PreviewStats getStats() {
    return PreviewStats(
      totalPreviews: _totalPreviews,
      totalCacheEntries: _totalCacheEntries,
      totalGenerators: _totalGenerators,
      totalPlugins: _totalPlugins,
      enabledGenerators: _generators.values.where((g) => g.enabled).length,
      enabledPlugins: _plugins.values.fold(0, (sum, plugins) => sum + plugins.length),
      cacheHitRate: _calculateCacheHitRate(),
    );
  }

  double _calculateCacheHitRate() {
    if (_totalPreviews == 0) return 0.0;
    
    int cacheHits = 0;
    for (final entry in _cache.values) {
      cacheHits += entry.accessCount - 1; // First access is not a hit
    }
    
    return cacheHits / _totalPreviews;
  }

  String _generatePreviewId() {
    return 'preview_${DateTime.now().millisecondsSinceEpoch}_$_totalPreviews';
  }

  String _generateGeneratorId() {
    return 'generator_${DateTime.now().millisecondsSinceEpoch}_$_totalGenerators';
  }

  String _generatePluginId() {
    return 'plugin_${DateTime.now().millisecondsSinceEpoch}_$_totalPlugins';
  }

  void _emitEvent(PreviewEvent event) {
    _previewController.add(event);
  }

  Stream<PreviewEvent> get previewEventStream => _previewController.stream;

  void dispose() {
    _cleanupTimer?.cancel();
    
    _cache.clear();
    _previews.clear();
    _generators.clear();
    _plugins.clear();
    _previewController.close();
    
    developer.log('👁 Advanced File Preview System disposed');
  }
}

class FilePreview {
  final String id;
  final String filePath;
  final String generatorId;
  final PreviewType type;
  final String content;
  final Map<String, dynamic> metadata;
  final String? thumbnail;
  final DateTime createdAt;
  final DateTime expiresAt;

  FilePreview({
    required this.id,
    required this.filePath,
    required this.generatorId,
    required this.type,
    required this.content,
    required this.metadata,
    this.thumbnail,
    required this.createdAt,
    required this.expiresAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_path': filePath,
      'generator_id': generatorId,
      'type': type.name,
      'content': content,
      'metadata': metadata,
      'thumbnail': thumbnail,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    };
  }

  factory FilePreview.fromJson(Map<String, dynamic> json) {
    return FilePreview(
      id: json['id'],
      filePath: json['file_path'],
      generatorId: json['generator_id'],
      type: PreviewType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => PreviewType.text,
      ),
      content: json['content'],
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      thumbnail: json['thumbnail'],
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: DateTime.parse(json['expires_at']),
    );
  }
}

class PreviewCache {
  final String id;
  final FilePreview preview;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int accessCount;
  final DateTime lastAccessed;

  PreviewCache({
    required this.id,
    required this.preview,
    required this.createdAt,
    required this.expiresAt,
    required this.accessCount,
    required this.lastAccessed,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'preview': preview.toJson(),
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'access_count': accessCount,
      'last_accessed': lastAccessed.toIso8601String(),
    };
  }

  factory PreviewCache.fromJson(Map<String, dynamic> json) {
    return PreviewCache(
      id: json['id'],
      preview: FilePreview.fromJson(json['preview']),
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: DateTime.parse(json['expires_at']),
      accessCount: json['access_count'] ?? 0,
      lastAccessed: DateTime.parse(json['last_accessed']),
    );
  }
}

class PreviewGenerator {
  final String id;
  final String name;
  final String description;
  final List<String> extensions;
  final String mimeType;
  final Map<String, dynamic> config;
  final int maxFileSize;
  final bool enabled;
  final DateTime createdAt;

  PreviewGenerator({
    required this.id,
    required this.name,
    required this.description,
    required this.extensions,
    required this.mimeType,
    required this.config,
    required this.maxFileSize,
    required this.enabled,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'extensions': extensions,
      'mime_type': mimeType,
      'config': config,
      'max_file_size': maxFileSize,
      'enabled': enabled,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PreviewGenerator.fromJson(Map<String, dynamic> json) {
    return PreviewGenerator(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      extensions: List<String>.from(json['extensions'] ?? []),
      mimeType: json['mime_type'],
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      maxFileSize: json['max_file_size'] ?? _maxPreviewSize,
      enabled: json['enabled'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class PreviewPlugin {
  final String id;
  final String name;
  final String description;
  final String generatorId;
  final Map<String, dynamic> config;
  final bool enabled;
  final DateTime createdAt;

  PreviewPlugin({
    required this.id,
    required this.name,
    required this.description,
    required this.generatorId,
    required this.config,
    required this.enabled,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'generator_id': generatorId,
      'config': config,
      'enabled': enabled,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PreviewPlugin.fromJson(Map<String, dynamic> json) {
    return PreviewPlugin(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      generatorId: json['generator_id'],
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      enabled: json['enabled'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

enum PreviewType {
  text,
  image,
  video,
  audio,
  pdf,
  code,
  archive,
  spreadsheet,
  document,
  binary,
}

enum PreviewEventType {
  previewGenerated,
  previewFailed,
  generatorCreated,
  pluginCreated,
  cacheCleared,
  cleanup,
}

class PreviewEvent {
  final PreviewEventType type;
  final String? filePath;
  final String? generatorId;
  final String? previewId;
  final String? generatorName;
  final String? pluginName;
  final String? error;
  final int? expiredCount;

  PreviewEvent({
    required this.type,
    this.filePath,
    this.generatorId,
    this.previewId,
    this.generatorName,
    this.pluginName,
    this.error,
    this.expiredCount,
  });
}

class PreviewStats {
  final int totalPreviews;
  final int totalCacheEntries;
  final int totalGenerators;
  final int totalPlugins;
  final int enabledGenerators;
  final int enabledPlugins;
  final double cacheHitRate;

  PreviewStats({
    required this.totalPreviews,
    required this.totalCacheEntries,
    required this.totalGenerators,
    required this.totalPlugins,
    required this.enabledGenerators,
    required this.enabledPlugins,
    required this.cacheHitRate,
  });
}
