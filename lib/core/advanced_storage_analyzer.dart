import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:process_run/process_run.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Advanced storage analyzer with intelligent optimization strategies
/// 
/// Features:
/// - Predictive storage analysis
/// - Smart file categorization
/// - Duplicate file detection
/// - Storage health monitoring
/// - Automated optimization recommendations
class AdvancedStorageAnalyzer {
  final StreamController<StorageAnalysisEvent> _eventController = StreamController<StorageAnalysisEvent>.broadcast();
  
  final Map<String, FileCategory> _fileCategories = {};
  final List<DuplicateGroup> _duplicates = [];
  final List<StorageHealthIssue> _healthIssues = [];
  final Map<String, double> _growthTrends = {};
  
  Timer? _analysisTimer;
  bool _isInitialized = false;
  late SharedPreferences _prefs;
  
  Stream<StorageAnalysisEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Load historical data
      await _loadHistoricalData();
      
      // Start periodic analysis
      _analysisTimer = Timer.periodic(const Duration(hours: 6), (_) {
        _performComprehensiveAnalysis();
      });
      
      _isInitialized = true;
      
      _eventController.add(StorageAnalysisEvent(
        type: StorageAnalysisEventType.initialized,
        message: 'Advanced storage analyzer initialized',
      ));
      
      debugPrint('📊 Advanced Storage Analyzer initialized');
    } catch (e) {
      debugPrint('Failed to initialize advanced storage analyzer: $e');
    }
  }
  
  Future<void> _loadHistoricalData() async {
    try {
      final categoriesJson = _prefs.getString('file_categories');
      if (categoriesJson != null) {
        final categoriesMap = jsonDecode(categoriesJson);
        _fileCategories = categoriesMap.map((key, value) => 
          MapEntry(key, FileCategory.fromJson(value)));
      }
      
      final trendsJson = _prefs.getString('growth_trends');
      if (trendsJson != null) {
        _growthTrends = Map<String, double>.from(jsonDecode(trendsJson));
      }
    } catch (e) {
      debugPrint('Failed to load historical data: $e');
    }
  }
  
  Future<void> _performComprehensiveAnalysis() async {
    try {
      _eventController.add(StorageAnalysisEvent(
        type: StorageAnalysisEventType.analysis_started,
        message: 'Starting comprehensive storage analysis',
      ));
      
      // Analyze file categories
      await _analyzeFileCategories();
      
      // Detect duplicates
      await _detectDuplicates();
      
      // Check storage health
      await _checkStorageHealth();
      
      // Analyze growth trends
      await _analyzeGrowthTrends();
      
      // Generate recommendations
      await _generateOptimizationRecommendations();
      
      // Save analysis results
      await _saveAnalysisResults();
      
      _eventController.add(StorageAnalysisEvent(
        type: StorageAnalysisEventType.analysis_completed,
        message: 'Comprehensive storage analysis completed',
        data: {
          'categories': _fileCategories.length,
          'duplicates': _duplicates.length,
          'health_issues': _healthIssues.length,
        },
      ));
      
    } catch (e) {
      _eventController.add(StorageAnalysisEvent(
        type: StorageAnalysisEventType.error,
        message: 'Analysis failed: $e',
      ));
    }
  }
  
  Future<void> _analyzeFileCategories() async {
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      final result = await run('find', [homeDir, '-type', 'f', '-exec', 'du', '-h', '{}', '+']);
      
      final lines = result.stdout.split('\n');
      final categoryMap = <String, List<FileInfo>>{};
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        final parts = line.trim().split('\t');
        if (parts.length >= 2) {
          final sizeStr = parts[0];
          final filePath = parts[1];
          final category = _categorizeFile(filePath);
          
          final fileInfo = FileInfo(
            path: filePath,
            size: _parseSize(sizeStr),
            category: category,
            lastModified: await _getFileLastModified(filePath),
          );
          
          categoryMap.putIfAbsent(category, () => []).add(fileInfo);
        }
      }
      
      // Update file categories with statistics
      _fileCategories.clear();
      for (final entry in categoryMap.entries) {
        final files = entry.value;
        final totalSize = files.fold(0.0, (sum, file) => sum + file.size);
        
        _fileCategories[entry.key] = FileCategory(
          name: entry.key,
          files: files,
          totalSize: totalSize,
          averageSize: totalSize / files.length,
          fileCount: files.length,
        );
      }
      
    } catch (e) {
      debugPrint('Failed to analyze file categories: $e');
    }
  }
  
  String _categorizeFile(String filePath) {
    final extension = filePath.toLowerCase().split('.').last;
    
    // Document categories
    if (['pdf', 'doc', 'docx', 'txt', 'rtf', 'odt'].contains(extension)) {
      return 'Documents';
    }
    
    // Media categories
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp'].contains(extension)) {
      return 'Images';
    }
    
    if (['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv'].contains(extension)) {
      return 'Videos';
    }
    
    if (['mp3', 'wav', 'flac', 'aac', 'ogg'].contains(extension)) {
      return 'Audio';
    }
    
    // Development categories
    if (['dart', 'py', 'js', 'ts', 'java', 'cpp', 'c', 'go', 'rs'].contains(extension)) {
      return 'Source Code';
    }
    
    if (['json', 'yaml', 'xml', 'toml', 'ini'].contains(extension)) {
      return 'Configuration';
    }
    
    // Archive categories
    if (['zip', 'tar', 'gz', 'rar', '7z'].contains(extension)) {
      return 'Archives';
    }
    
    // System categories
    if (filePath.contains('/tmp/') || filePath.contains('/temp/')) {
      return 'Temporary';
    }
    
    if (filePath.contains('/cache/') || filePath.contains('/Cache/')) {
      return 'Cache';
    }
    
    return 'Other';
  }
  
  Future<void> _detectDuplicates() async {
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      final result = await run('find', [homeDir, '-type', 'f', '-exec', 'md5sum', '{}', '+']);
      
      final lines = result.stdout.split('\n');
      final hashMap = <String, List<String>>{};
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        final parts = line.trim().split('  ');
        if (parts.length >= 2) {
          final hash = parts[0];
          final filePath = parts.sublist(1).join('  ');
          
          hashMap.putIfAbsent(hash, () => []).add(filePath);
        }
      }
      
      // Create duplicate groups
      _duplicates.clear();
      for (final entry in hashMap.entries) {
        if (entry.value.length > 1) {
          final files = entry.value.map((path) => FileInfo(
            path: path,
            size: await _getFileSize(path),
            category: _categorizeFile(path),
            lastModified: await _getFileLastModified(path),
          )).toList();
          
          final totalSize = files.fold(0.0, (sum, file) => sum + file.size);
          
          _duplicates.add(DuplicateGroup(
            hash: entry.key,
            files: files,
            duplicateCount: files.length,
            wastedSpace: totalSize - files.first.size, // Keep one, delete rest
          ));
        }
      }
      
    } catch (e) {
      debugPrint('Failed to detect duplicates: $e');
    }
  }
  
  Future<void> _checkStorageHealth() async {
    try {
      _healthIssues.clear();
      
      // Check disk usage
      final dfResult = await run('df', ['-h', '/']);
      final dfLines = dfResult.stdout.split('\n');
      
      for (final line in dfLines) {
        if (line.startsWith('/dev/')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 5) {
            final usedPercent = parts[4].replaceAll('%', '');
            final usage = int.tryParse(usedPercent) ?? 0;
            
            if (usage > 90) {
              _healthIssues.add(StorageHealthIssue(
                type: HealthIssueType.high_disk_usage,
                severity: IssueSeverity.critical,
                description: 'Disk usage is ${usage}% (>90%)',
                recommendation: 'Free up disk space immediately',
              ));
            } else if (usage > 80) {
              _healthIssues.add(StorageHealthIssue(
                type: HealthIssueType.high_disk_usage,
                severity: IssueSeverity.warning,
                description: 'Disk usage is ${usage}% (>80%)',
                recommendation: 'Consider cleaning up unnecessary files',
              ));
            }
          }
        }
      }
      
      // Check for large temporary files
      final tempResult = await run('find', ['/tmp', '-type', 'f', '-size', '+100M']);
      final tempFiles = tempResult.stdout.split('\n').where((f) => f.trim().isNotEmpty).toList();
      
      if (tempFiles.isNotEmpty) {
        _healthIssues.add(StorageHealthIssue(
          type: HealthIssueType.large_temp_files,
          severity: IssueSeverity.medium,
          description: '${tempFiles.length} large temporary files found',
          recommendation: 'Clean temporary files to free space',
        ));
      }
      
      // Check for old cache files
      final cacheResult = await run('find', [
        Platform.environment['HOME'] ?? '', '-name', 'cache', '-type', 'd'
      ]);
      final cacheDirs = cacheResult.stdout.split('\n').where((d) => d.trim().isNotEmpty).toList();
      
      for (final cacheDir in cacheDirs) {
        final cacheSizeResult = await run('du', ['-sh', cacheDir]);
        final sizeStr = cacheSizeResult.stdout.split('\t').first;
        final size = _parseSize(sizeStr);
        
        if (size > 1024) { // > 1GB
          _healthIssues.add(StorageHealthIssue(
            type: HealthIssueType.large_cache,
            severity: IssueSeverity.medium,
            description: 'Large cache directory: $cacheDir (${sizeStr})',
            recommendation: 'Clear cache to free space',
          ));
        }
      }
      
    } catch (e) {
      debugPrint('Failed to check storage health: $e');
    }
  }
  
  Future<void> _analyzeGrowthTrends() async {
    try {
      final currentUsage = await _getCurrentDiskUsage();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // Store current usage
      _growthTrends[timestamp.toString()] = currentUsage;
      
      // Keep only last 30 days of data
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      _growthTrends.removeWhere((key, value) => int.tryParse(key) ?? 0 < thirtyDaysAgo);
      
      // Calculate growth rate
      if (_growthTrends.length >= 2) {
        final sortedKeys = _growthTrends.keys.toList()..sort();
        final oldest = _growthTrends[sortedKeys.first]!;
        final newest = _growthTrends[sortedKeys.last]!;
        final growthRate = ((newest - oldest) / oldest) * 100;
        
        if (growthRate > 10) {
          _healthIssues.add(StorageHealthIssue(
            type: HealthIssueType.rapid_growth,
            severity: IssueSeverity.warning,
            description: 'Storage growing rapidly (${growthRate.toStringAsFixed(1)}%)',
            recommendation: 'Monitor usage and consider cleanup',
          ));
        }
      }
      
    } catch (e) {
      debugPrint('Failed to analyze growth trends: $e');
    }
  }
  
  Future<void> _generateOptimizationRecommendations() async {
    final recommendations = <OptimizationRecommendation>[];
    
    // Analyze file categories for cleanup opportunities
    for (final category in _fileCategories.values) {
      if (category.name == 'Temporary' && category.totalSize > 500) {
        recommendations.add(OptimizationRecommendation(
          type: RecommendationType.cleanup_temp,
          priority: RecommendationPriority.high,
          description: 'Clean temporary files (${category.totalSize.toStringAsFixed(1)} GB)',
          estimatedSpaceSaved: category.totalSize * 0.9,
          action: 'Delete temporary files',
        ));
      }
      
      if (category.name == 'Cache' && category.totalSize > 1000) {
        recommendations.add(OptimizationRecommendation(
          type: RecommendationType.cleanup_cache,
          priority: RecommendationPriority.medium,
          description: 'Clear cache files (${category.totalSize.toStringAsFixed(1)} GB)',
          estimatedSpaceSaved: category.totalSize * 0.8,
          action: 'Clear application caches',
        ));
      }
    }
    
    // Duplicate file recommendations
    if (_duplicates.isNotEmpty) {
      final totalWastedSpace = _duplicates.fold(0.0, (sum, group) => sum + group.wastedSpace);
      recommendations.add(OptimizationRecommendation(
        type: RecommendationType.remove_duplicates,
        priority: RecommendationPriority.high,
        description: 'Remove duplicate files (${_duplicates.length} groups, ${totalWastedSpace.toStringAsFixed(1)} GB)',
        estimatedSpaceSaved: totalWastedSpace,
        action: 'Review and remove duplicate files',
      ));
    }
    
    // Send recommendations
    _eventController.add(StorageAnalysisEvent(
      type: StorageAnalysisEventType.recommendations_generated,
      message: 'Generated ${recommendations.length} optimization recommendations',
      data: {
        'recommendations': recommendations.map((r) => r.toJson()).toList(),
      },
    ));
  }
  
  Future<void> _saveAnalysisResults() async {
    try {
      // Save file categories
      final categoriesMap = _fileCategories.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs.setString('file_categories', jsonEncode(categoriesMap));
      
      // Save growth trends
      await _prefs.setString('growth_trends', jsonEncode(_growthTrends));
      
      // Save analysis timestamp
      await _prefs.setString('last_analysis', DateTime.now().toIso8601String());
      
    } catch (e) {
      debugPrint('Failed to save analysis results: $e');
    }
  }
  
  // Helper methods
  double _parseSize(String sizeStr) {
    final units = {'B': 1, 'K': 1024, 'M': 1024 * 1024, 'G': 1024 * 1024 * 1024, 'T': 1024 * 1024 * 1024 * 1024};
    
    for (final unit in units.entries) {
      if (sizeStr.contains(unit.key)) {
        final number = double.tryParse(sizeStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
        return number * unit.value / (1024 * 1024 * 1024); // Convert to GB
      }
    }
    
    return 0.0;
  }
  
  Future<double> _getCurrentDiskUsage() async {
    try {
      final result = await run('df', ['/', '--output=used']);
      final lines = result.stdout.split('\n');
      if (lines.length >= 2) {
        final usedStr = lines[1].trim();
        final usedBytes = int.tryParse(usedStr) ?? 0;
        return usedBytes / (1024 * 1024 * 1024); // Convert to GB
      }
    } catch (e) {
      debugPrint('Failed to get current disk usage: $e');
    }
    return 0.0;
  }
  
  Future<double> _getFileSize(String filePath) async {
    try {
      final result = await run('stat', ['-c', '%s', filePath]);
      final sizeBytes = int.tryParse(result.stdout.trim()) ?? 0;
      return sizeBytes / (1024 * 1024 * 1024); // Convert to GB
    } catch (e) {
      return 0.0;
    }
  }
  
  Future<DateTime> _getFileLastModified(String filePath) async {
    try {
      final result = await run('stat', ['-c', '%Y', filePath]);
      final timestamp = int.tryParse(result.stdout.trim()) ?? 0;
      return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    } catch (e) {
      return DateTime.now();
    }
  }
  
  Future<void> dispose() async {
    _analysisTimer?.cancel();
    _eventController.close();
    debugPrint('📊 Advanced Storage Analyzer disposed');
  }
}

// Data models
class FileCategory {
  final String name;
  final List<FileInfo> files;
  final double totalSize;
  final double averageSize;
  final int fileCount;
  
  FileCategory({
    required this.name,
    required this.files,
    required this.totalSize,
    required this.averageSize,
    required this.fileCount,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'totalSize': totalSize,
    'averageSize': averageSize,
    'fileCount': fileCount,
  };
  
  factory FileCategory.fromJson(Map<String, dynamic> json) => FileCategory(
    name: json['name'],
    files: [], // Files not persisted
    totalSize: json['totalSize']?.toDouble() ?? 0.0,
    averageSize: json['averageSize']?.toDouble() ?? 0.0,
    fileCount: json['fileCount'] ?? 0,
  );
}

class FileInfo {
  final String path;
  final double size;
  final String category;
  final DateTime lastModified;
  
  FileInfo({
    required this.path,
    required this.size,
    required this.category,
    required this.lastModified,
  });
}

class DuplicateGroup {
  final String hash;
  final List<FileInfo> files;
  final int duplicateCount;
  final double wastedSpace;
  
  DuplicateGroup({
    required this.hash,
    required this.files,
    required this.duplicateCount,
    required this.wastedSpace,
  });
}

class StorageHealthIssue {
  final HealthIssueType type;
  final IssueSeverity severity;
  final String description;
  final String recommendation;
  
  StorageHealthIssue({
    required this.type,
    required this.severity,
    required this.description,
    required this.recommendation,
  });
}

class OptimizationRecommendation {
  final RecommendationType type;
  final RecommendationPriority priority;
  final String description;
  final double estimatedSpaceSaved;
  final String action;
  
  OptimizationRecommendation({
    required this.type,
    required this.priority,
    required this.description,
    required this.estimatedSpaceSaved,
    required this.action,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type.name,
    'priority': priority.name,
    'description': description,
    'estimatedSpaceSaved': estimatedSpaceSaved,
    'action': action,
  };
}

enum StorageAnalysisEventType {
  initialized,
  analysis_started,
  analysis_completed,
  recommendations_generated,
  error,
}

class StorageAnalysisEvent {
  final StorageAnalysisEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  
  StorageAnalysisEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}

enum HealthIssueType {
  high_disk_usage,
  large_temp_files,
  large_cache,
  rapid_growth,
  low_disk_space,
}

enum IssueSeverity {
  low,
  medium,
  warning,
  critical,
}

enum RecommendationType {
  cleanup_temp,
  cleanup_cache,
  remove_duplicates,
  compress_files,
  archive_old_files,
}

enum RecommendationPriority {
  low,
  medium,
  high,
}
