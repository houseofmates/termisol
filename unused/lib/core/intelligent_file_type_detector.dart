import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class IntelligentFileTypeDetector {
  static const int _maxFileSizeForAnalysis = 10 * 1024 * 1024; // 10MB
  static const int _sampleSize = 8192; // 8KB sample for analysis
  static const int _magicBytesCount = 512; // First 512 bytes for magic number detection
  
  final Map<String, FileTypeSignature> _fileSignatures = {};
  final Map<String, FileTypeInfo> _fileTypeCache = {};
  final Map<String, List<FileTypePattern>> _extensionPatterns = {};
  
  void initialize() {
    _initializeFileSignatures();
    _initializeExtensionPatterns();
    developer.log('🔍 Intelligent File Type Detector initialized');
  }

  void _initializeFileSignatures() {
    // Image formats
    _fileSignatures['png'] = FileTypeSignature(
      extension: 'png',
      mimeType: 'image/png',
      magicBytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      category: FileCategory.image,
      description: 'Portable Network Graphics',
    );
    
    _fileSignatures['jpeg'] = FileTypeSignature(
      extension: 'jpeg',
      mimeType: 'image/jpeg',
      magicBytes: [0xFF, 0xD8, 0xFF],
      category: FileCategory.image,
      description: 'JPEG Image',
    );
    
    _fileSignatures['jpg'] = FileTypeSignature(
      extension: 'jpg',
      mimeType: 'image/jpeg',
      magicBytes: [0xFF, 0xD8, 0xFF],
      category: FileCategory.image,
      description: 'JPEG Image',
    );
    
    _fileSignatures['gif'] = FileTypeSignature(
      extension: 'gif',
      mimeType: 'image/gif',
      magicBytes: [0x47, 0x49, 0x46, 0x38],
      category: FileCategory.image,
      description: 'Graphics Interchange Format',
    );
    
    _fileSignatures['webp'] = FileTypeSignature(
      extension: 'webp',
      mimeType: 'image/webp',
      magicBytes: [0x52, 0x49, 0x46, 0x46],
      category: FileCategory.image,
      description: 'WebP Image',
    );
    
    _fileSignatures['avif'] = FileTypeSignature(
      extension: 'avif',
      mimeType: 'image/avif',
      magicBytes: [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70],
      category: FileCategory.image,
      description: 'AV1 Image File Format',
    );
    
    _fileSignatures['heic'] = FileTypeSignature(
      extension: 'heic',
      mimeType: 'image/heic',
      magicBytes: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70],
      category: FileCategory.image,
      description: 'High Efficiency Image Container',
    );
    
    // Document formats
    _fileSignatures['pdf'] = FileTypeSignature(
      extension: 'pdf',
      mimeType: 'application/pdf',
      magicBytes: [0x25, 0x50, 0x44, 0x46], // %PDF
      category: FileCategory.document,
      description: 'Portable Document Format',
    );
    
    _fileSignatures['docx'] = FileTypeSignature(
      extension: 'docx',
      mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      magicBytes: [0x50, 0x4B, 0x03, 0x04], // ZIP header
      category: FileCategory.document,
      description: 'Microsoft Word Document',
    );
    
    _fileSignatures['xlsx'] = FileTypeSignature(
      extension: 'xlsx',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      magicBytes: [0x50, 0x4B, 0x03, 0x04], // ZIP header
      category: FileCategory.document,
      description: 'Microsoft Excel Spreadsheet',
    );
    
    // Video formats
    _fileSignatures['mp4'] = FileTypeSignature(
      extension: 'mp4',
      mimeType: 'video/mp4',
      magicBytes: [0x66, 0x74, 0x79, 0x70], // ftyp
      category: FileCategory.video,
      description: 'MPEG-4 Video',
    );
    
    _fileSignatures['avi'] = FileTypeSignature(
      extension: 'avi',
      mimeType: 'video/x-msvideo',
      magicBytes: [0x52, 0x49, 0x46, 0x46], // RIFF
      category: FileCategory.video,
      description: 'Audio Video Interleave',
    );
    
    _fileSignatures['webm'] = FileTypeSignature(
      extension: 'webm',
      mimeType: 'video/webm',
      magicBytes: [0x1A, 0x45, 0xDF, 0xA3], // EBML
      category: FileCategory.video,
      description: 'WebM Video',
    );
    
    // Audio formats
    _fileSignatures['mp3'] = FileTypeSignature(
      extension: 'mp3',
      mimeType: 'audio/mpeg',
      magicBytes: [0x49, 0x44, 0x33], // ID3
      category: FileCategory.audio,
      description: 'MPEG Audio Layer 3',
    );
    
    _fileSignatures['wav'] = FileTypeSignature(
      extension: 'wav',
      mimeType: 'audio/wav',
      magicBytes: [0x52, 0x49, 0x46, 0x46], // RIFF
      category: FileCategory.audio,
      description: 'Waveform Audio File',
    );
    
    _fileSignatures['flac'] = FileTypeSignature(
      extension: 'flac',
      mimeType: 'audio/flac',
      magicBytes: [0x66, 0x4C, 0x61, 0x43], // fLaC
      category: FileCategory.audio,
      description: 'Free Lossless Audio Codec',
    );
    
    // Archive formats
    _fileSignatures['zip'] = FileTypeSignature(
      extension: 'zip',
      mimeType: 'application/zip',
      magicBytes: [0x50, 0x4B, 0x03, 0x04], // ZIP
      category: FileCategory.archive,
      description: 'ZIP Archive',
    );
    
    _fileSignatures['tar'] = FileTypeSignature(
      extension: 'tar',
      mimeType: 'application/x-tar',
      magicBytes: [0x75, 0x73, 0x74, 0x61, 0x72], // ustar
      category: FileCategory.archive,
      description: 'TAR Archive',
    );
    
    _fileSignatures['gz'] = FileTypeSignature(
      extension: 'gz',
      mimeType: 'application/gzip',
      magicBytes: [0x1F, 0x8B, 0x08], // GZIP
      category: FileCategory.archive,
      description: 'GZIP Archive',
    );
    
    // Code formats
    _fileSignatures['dart'] = FileTypeSignature(
      extension: 'dart',
      mimeType: 'text/x-dart',
      magicBytes: [], // No magic bytes, text-based
      category: FileCategory.code,
      description: 'Dart Source Code',
    );
    
    _fileSignatures['js'] = FileTypeSignature(
      extension: 'js',
      mimeType: 'application/javascript',
      magicBytes: [], // No magic bytes, text-based
      category: FileCategory.code,
      description: 'JavaScript Source Code',
    );
    
    _fileSignatures['py'] = FileTypeSignature(
      extension: 'py',
      mimeType: 'text/x-python',
      magicBytes: [], // No magic bytes, text-based
      category: FileCategory.code,
      description: 'Python Source Code',
    );
  }

  void _initializeExtensionPatterns() {
    // Common programming language extensions
    _extensionPatterns['code'] = [
      FileTypePattern(extension: 'dart', language: 'Dart'),
      FileTypePattern(extension: 'js', language: 'JavaScript'),
      FileTypePattern(extension: 'ts', language: 'TypeScript'),
      FileTypePattern(extension: 'py', language: 'Python'),
      FileTypePattern(extension: 'java', language: 'Java'),
      FileTypePattern(extension: 'cpp', language: 'C++'),
      FileTypePattern(extension: 'c', language: 'C'),
      FileTypePattern(extension: 'go', language: 'Go'),
      FileTypePattern(extension: 'rs', language: 'Rust'),
      FileTypePattern(extension: 'php', language: 'PHP'),
      FileTypePattern(extension: 'rb', language: 'Ruby'),
      FileTypePattern(extension: 'swift', language: 'Swift'),
      FileTypePattern(extension: 'kt', language: 'Kotlin'),
      FileTypePattern(extension: 'scala', language: 'Scala'),
      FileTypePattern(extension: 'sh', language: 'Shell'),
      FileTypePattern(extension: 'bash', language: 'Bash'),
      FileTypePattern(extension: 'zsh', language: 'Zsh'),
      FileTypePattern(extension: 'fish', language: 'Fish'),
      FileTypePattern(extension: 'ps1', language: 'PowerShell'),
      FileTypePattern(extension: 'bat', language: 'Batch'),
      FileTypePattern(extension: 'cmd', language: 'Command'),
    ];
    
    // Configuration file extensions
    _extensionPatterns['config'] = [
      FileTypePattern(extension: 'json', language: 'JSON'),
      FileTypePattern(extension: 'yaml', language: 'YAML'),
      FileTypePattern(extension: 'yml', language: 'YAML'),
      FileTypePattern(extension: 'xml', language: 'XML'),
      FileTypePattern(extension: 'toml', language: 'TOML'),
      FileTypePattern(extension: 'ini', language: 'INI'),
      FileTypePattern(extension: 'conf', language: 'Config'),
      FileTypePattern(extension: 'env', language: 'Environment'),
      FileTypePattern(extension: 'dockerfile', language: 'Dockerfile'),
      FileTypePattern(extension: 'makefile', language: 'Makefile'),
    ];
    
    // Document extensions
    _extensionPatterns['document'] = [
      FileTypePattern(extension: 'md', language: 'Markdown'),
      FileTypePattern(extension: 'txt', language: 'Text'),
      FileTypePattern(extension: 'rtf', language: 'Rich Text'),
      FileTypePattern(extension: 'odt', language: 'OpenDocument Text'),
      FileTypePattern(extension: 'ods', language: 'OpenDocument Spreadsheet'),
      FileTypePattern(extension: 'odp', language: 'OpenDocument Presentation'),
    ];
  }

  Future<FileTypeInfo> detectFileType(String filePath) async {
    // Check cache first
    if (_fileTypeCache.containsKey(filePath)) {
      return _fileTypeCache[filePath]!;
    }
    
    final file = File(filePath);
    if (!file.existsSync()) {
      return FileTypeInfo(
        extension: 'unknown',
        mimeType: 'application/octet-stream',
        category: FileCategory.unknown,
        description: 'Unknown file type',
        confidence: 0.0,
      );
    }
    
    final fileSize = file.lengthSync();
    
    // Get file extension
    final extension = _getFileExtension(filePath);
    
    // Try magic number detection
    final magicResult = await _detectByMagicNumber(file);
    
    // Try content analysis
    final contentResult = await _analyzeContent(file, extension);
    
    // Combine results
    final finalResult = _combineDetectionResults(
      extension,
      magicResult,
      contentResult,
      fileSize,
    );
    
    // Cache result
    _fileTypeCache[filePath] = finalResult;
    
    return finalResult;
  }

  String _getFileExtension(String filePath) {
    final parts = filePath.split('.');
    if (parts.length < 2) return '';
    
    final extension = parts.last.toLowerCase();
    return extension;
  }

  Future<FileTypeDetection?> _detectByMagicNumber(File file) async {
    try {
      final bytes = await file.openRead(0, _magicBytesCount).first;
      
      for (final entry in _fileSignatures.entries) {
        final signature = entry.value;
        if (_matchesMagicBytes(bytes, signature.magicBytes)) {
          return FileTypeDetection(
            type: signature.extension,
            mimeType: signature.mimeType,
            category: signature.category,
            description: signature.description,
            confidence: 0.9,
            method: DetectionMethod.magicNumber,
          );
        }
      }
    } catch (e) {
      developer.log('🔍 Magic number detection failed: $e');
    }
    
    return null;
  }

  bool _matchesMagicBytes(List<int> fileBytes, List<int> signatureBytes) {
    if (signatureBytes.isEmpty) return false;
    if (fileBytes.length < signatureBytes.length) return false;
    
    for (int i = 0; i < signatureBytes.length; i++) {
      if (fileBytes[i] != signatureBytes[i]) {
        return false;
      }
    }
    
    return true;
  }

  Future<FileTypeDetection?> _analyzeContent(File file, String extension) async {
    try {
      final fileSize = file.lengthSync();
      
      // Don't analyze large files
      if (fileSize > _maxFileSizeForAnalysis) {
        return null;
      }
      
      // Read sample
      final sampleSize = min(fileSize, _sampleSize);
      final bytes = await file.openRead(0, sampleSize).first;
      
      // Try to decode as text
      try {
        final content = utf8.decode(bytes, allowMalformed: true);
        
        // Analyze text content
        return _analyzeTextContent(content, extension);
      } catch (e) {
        // Not text, try binary analysis
        return _analyzeBinaryContent(bytes, extension);
      }
    } catch (e) {
      developer.log('🔍 Content analysis failed: $e');
    }
    
    return null;
  }

  FileTypeDetection? _analyzeTextContent(String content, String extension) {
    // Check for known patterns
    final patterns = {
      'dart': RegExp(r'^\s*import\s+["\']dart:'),
      'js': RegExp(r'^\s*(import|const|let|var|function)\s+'),
      'py': RegExp(r'^\s*(import|def|class|if|for|while)\s+'),
      'json': RegExp(r'^\s*\{.*\}\s*$'),
      'yaml': RegExp(r'^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*:'),
      'xml': RegExp(r'^\s*<\?xml|<[a-zA-Z]'),
      'html': RegExp(r'^\s*<!DOCTYPE|<[hH][tT][mM][lL]'),
      'css': RegExp(r'^\s*[a-zA-Z-]+\s*\{[^}]*\}'),
      'sql': RegExp(r'^\s*(SELECT|INSERT|UPDATE|DELETE|CREATE|DROP)\s+', caseSensitive: false),
      'sh': RegExp(r'^\s*#!/bin/(ba)?sh|^#|^export\s+|^echo\s+'),
      'dockerfile': RegExp(r'^\s*FROM\s+|^RUN\s+|^COPY\s+|^WORKDIR\s+'),
    };
    
    for (final entry in patterns.entries) {
      if (entry.value.hasMatch(content)) {
        final signature = _fileSignatures[entry.key];
        if (signature != null) {
          return FileTypeDetection(
            type: entry.key,
            mimeType: signature.mimeType,
            category: signature.category,
            description: signature.description,
            confidence: 0.8,
            method: DetectionMethod.contentAnalysis,
          );
        }
      }
    }
    
    // Check extension patterns
    for (final entry in _extensionPatterns.entries) {
      for (final pattern in entry.value) {
        if (pattern.extension == extension) {
          return FileTypeDetection(
            type: pattern.extension,
            mimeType: 'text/plain',
            category: FileCategory.text,
            description: '${pattern.language} file',
            confidence: 0.7,
            method: DetectionMethod.extension,
          );
        }
      }
    }
    
    // Default to plain text
    return FileTypeDetection(
      type: 'txt',
      mimeType: 'text/plain',
      category: FileCategory.text,
      description: 'Plain text file',
      confidence: 0.6,
      method: DetectionMethod.contentAnalysis,
    );
  }

  FileTypeDetection? _analyzeBinaryContent(List<int> bytes, String extension) {
    // Binary content analysis
    final entropy = _calculateEntropy(bytes);
    
    if (entropy > 7.0) {
      // High entropy - likely compressed or encrypted
      return FileTypeDetection(
        type: 'binary',
        mimeType: 'application/octet-stream',
        category: FileCategory.binary,
        description: 'Binary data (high entropy)',
        confidence: 0.5,
        method: DetectionMethod.contentAnalysis,
      );
    }
    
    return null;
  }

  double _calculateEntropy(List<int> bytes) {
    final frequencies = <int, int>{};
    
    for (final byte in bytes) {
      frequencies[byte] = (frequencies[byte] ?? 0) + 1;
    }
    
    double entropy = 0.0;
    final length = bytes.length;
    
    for (final frequency in frequencies.values) {
      final probability = frequency / length;
      entropy -= probability * (log(probability) / ln(2));
    }
    
    return entropy;
  }

  FileTypeInfo _combineDetectionResults(
    String extension,
    FileTypeDetection? magicResult,
    FileTypeDetection? contentResult,
    int fileSize,
  ) {
    // Priority: Magic number > Content analysis > Extension
    FileTypeDetection? primary;
    
    if (magicResult != null && magicResult.confidence > 0.8) {
      primary = magicResult;
    } else if (contentResult != null) {
      primary = contentResult;
    } else {
      // Fall back to extension
      final signature = _fileSignatures[extension];
      if (signature != null) {
        primary = FileTypeDetection(
          type: signature.extension,
          mimeType: signature.mimeType,
          category: signature.category,
          description: signature.description,
          confidence: 0.4,
          method: DetectionMethod.extension,
        );
      }
    }
    
    if (primary == null) {
      return FileTypeInfo(
        extension: extension,
        mimeType: 'application/octet-stream',
        category: FileCategory.unknown,
        description: 'Unknown file type',
        confidence: 0.0,
      );
    }
    
    return FileTypeInfo(
      extension: primary.type,
      mimeType: primary.mimeType,
      category: primary.category,
      description: primary.description,
      confidence: primary.confidence,
      fileSize: fileSize,
      detectionMethod: primary.method,
    );
  }

  Future<List<FileTypeInfo>> detectMultipleFileTypes(List<String> filePaths) async {
    final results = <FileTypeInfo>[];
    
    for (final filePath in filePaths) {
      try {
        final typeInfo = await detectFileType(filePath);
        results.add(typeInfo);
      } catch (e) {
        developer.log('🔍 Failed to detect file type for $filePath: $e');
        // Add unknown type
        results.add(FileTypeInfo(
          extension: 'unknown',
          mimeType: 'application/octet-stream',
          category: FileCategory.unknown,
          description: 'Unknown file type',
          confidence: 0.0,
        ));
      }
    }
    
    return results;
  }

  Future<Map<String, int>> analyzeDirectoryTypes(String directoryPath) async {
    final typeCounts = <String, int>{};
    final directory = Directory(directoryPath);
    
    if (!directory.existsSync()) {
      return typeCounts;
    }
    
    try {
      await for (final entity in directory.list()) {
        if (entity is File) {
          final typeInfo = await detectFileType(entity.path);
          final type = typeInfo.category.name;
          typeCounts[type] = (typeCounts[type] ?? 0) + 1;
        }
      }
    } catch (e) {
      developer.log('🔍 Failed to analyze directory $directoryPath: $e');
    }
    
    return typeCounts;
  }

  void clearCache() {
    _fileTypeCache.clear();
    developer.log('🔍 File type cache cleared');
  }

  FileTypeDetectorStats getStats() {
    return FileTypeDetectorStats(
      signatureCount: _fileSignatures.length,
      cacheSize: _fileTypeCache.length,
      patternCount: _extensionPatterns.values
          .map((patterns) => patterns.length)
          .reduce((a, b) => a + b),
    );
  }

  void dispose() {
    _fileTypeCache.clear();
    _fileSignatures.clear();
    _extensionPatterns.clear();
    developer.log('🔍 Intelligent File Type Detector disposed');
  }
}

class FileTypeSignature {
  final String extension;
  final String mimeType;
  final List<int> magicBytes;
  final FileCategory category;
  final String description;

  FileTypeSignature({
    required this.extension,
    required this.mimeType,
    required this.magicBytes,
    required this.category,
    required this.description,
  });
}

class FileTypeInfo {
  final String extension;
  final String mimeType;
  final FileCategory category;
  final String description;
  final double confidence;
  final int? fileSize;
  final DetectionMethod? detectionMethod;

  FileTypeInfo({
    required this.extension,
    required this.mimeType,
    required this.category,
    required this.description,
    required this.confidence,
    this.fileSize,
    this.detectionMethod,
  });
}

class FileTypeDetection {
  final String type;
  final String mimeType;
  final FileCategory category;
  final String description;
  final double confidence;
  final DetectionMethod method;

  FileTypeDetection({
    required this.type,
    required this.mimeType,
    required this.category,
    required this.description,
    required this.confidence,
    required this.method,
  });
}

class FileTypePattern {
  final String extension;
  final String language;

  FileTypePattern({
    required this.extension,
    required this.language,
  });
}

enum FileCategory {
  image,
  video,
  audio,
  document,
  code,
  text,
  archive,
  binary,
  unknown,
}

enum DetectionMethod {
  magicNumber,
  contentAnalysis,
  extension,
}

class FileTypeDetectorStats {
  final int signatureCount;
  final int cacheSize;
  final int patternCount;

  FileTypeDetectorStats({
    required this.signatureCount,
    required this.cacheSize,
    required this.patternCount,
  });
}
