import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Directory Tracking - Intelligent directory bookmarking and tracking
/// 
/// Implements comprehensive directory tracking:
/// - Intelligent directory bookmarking
/// - Directory usage analytics
/// - Smart directory suggestions
/// - Directory history with context
/// - Project and workspace detection
class DirectoryTracking {
  bool _isInitialized = false;
  
  // Directory bookmarks
  final Map<String, DirectoryBookmark> _bookmarks = {};
  final List<String> _bookmarkNames = [];
  
  // Directory history
  final List<DirectoryHistory> _history = [];
  final Map<String, DirectoryUsage> _usageStats = {};
  
  // Project detection
  final Map<String, ProjectInfo> _projects = {};
  final Map<String, String> _projectRoots = {};
  
  // Smart suggestions
  final Map<String, DirectorySuggestion> _suggestions = {};
  final Map<String, double> _directoryScores = {};
  
  // Configuration
  DirectoryTrackingConfig _config = DirectoryTrackingConfig();
  
  // Current state
  String? _currentDirectory;
  String? _currentProject;
  
  DirectoryTracking();
  
  bool get isInitialized => _isInitialized;
  Map<String, DirectoryBookmark> get bookmarks => Map.unmodifiable(_bookmarks);
  List<DirectoryHistory> get history => List.unmodifiable(_history);
  Map<String, ProjectInfo> get projects => Map.unmodifiable(_projects);
  String? get currentDirectory => _currentDirectory;
  String? get currentProject => _currentProject;
  
  /// Initialize directory tracking
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load configuration
      await _loadConfiguration();
      
      // Load persistent data
      await _loadPersistentData();
      
      // Detect current directory
      await _detectCurrentDirectory();
      
      // Setup directory monitoring
      _setupDirectoryMonitoring();
      
      _isInitialized = true;
      debugPrint('📁 Directory Tracking initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Directory Tracking: $e');
    }
  }
  
  /// Load configuration
  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('${Platform.environment['HOME']}/.termisol/directory_tracking_config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _config = DirectoryTrackingConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load directory tracking config: $e');
    }
  }
  
  /// Load persistent data
  Future<void> _loadPersistentData() async {
    try {
      final dataFile = File('${Platform.environment['HOME']}/.termisol/directory_data.json');
      if (await dataFile.exists()) {
        final content = await dataFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        // Load bookmarks
        final bookmarksData = data['bookmarks'] as Map<String, dynamic>?;
        if (bookmarksData != null) {
          for (final entry in bookmarksData.entries) {
            _bookmarks[entry.key] = DirectoryBookmark.fromJson(entry.value as Map<String, dynamic>);
          }
          _bookmarkNames.add(entry.key);
        }
        
        // Load history
        final historyData = data['history'] as List<dynamic>?;
        if (historyData != null) {
          _history.clear();
          for (final item in historyData) {
            _history.add(DirectoryHistory.fromJson(item as Map<String, dynamic>));
          }
        }
        
        // Load usage statistics
        final usageData = data['usageStats'] as Map<String, dynamic>?;
        if (usageData != null) {
          for (final entry in usageData.entries) {
            _usageStats[entry.key] = DirectoryUsage.fromJson(entry.value as Map<String, dynamic>);
          }
        }
        
        // Load projects
        final projectsData = data['projects'] as Map<String, dynamic>?;
        if (projectsData != null) {
          for (final entry in projectsData.entries) {
            _projects[entry.key] = ProjectInfo.fromJson(entry.value as Map<String, dynamic>);
          }
        }
        
        // Load project roots
        final projectRootsData = data['projectRoots'] as Map<String, dynamic>?;
        if (projectRootsData != null) {
          _projectRoots.addAll(projectRootsData.cast<String, String>());
        }
        
        debugPrint('📂 Loaded directory tracking data');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load directory tracking data: $e');
    }
  }
  
  /// Detect current directory
  Future<void> _detectCurrentDirectory() async {
    try {
      final result = await Process.run('pwd', [], runInShell: true);
      if (result.exitCode == 0) {
        _currentDirectory = (result.stdout as String).trim();
        await _analyzeDirectory(_currentDirectory!);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to detect current directory: $e');
    }
  }
  
  /// Setup directory monitoring
  void _setupDirectoryMonitoring() {
    // Setup periodic directory analysis
    Timer.periodic(const Duration(seconds: 30), (_) {
      _analyzeCurrentDirectory();
    });
    debugPrint('👁️ Directory monitoring setup');
  }
  
  /// Analyze current directory
  Future<void> _analyzeCurrentDirectory() async {
    if (_currentDirectory == null) return;
    
    try {
      final directory = Directory(_currentDirectory!);
      if (!await directory.exists()) return;
      
      // Update usage statistics
      _updateUsageStats(_currentDirectory!);
      
      // Detect project
      await _detectProject(_currentDirectory!);
      
      // Update directory scores
      _updateDirectoryScores(_currentDirectory!);
      
      // Add to history
      _addToHistory(_currentDirectory!);
    } catch (e) {
      debugPrint('⚠️ Failed to analyze directory: $e');
    }
  }
  
  /// Update usage statistics
  void _updateUsageStats(String path) {
    final normalizedPath = _normalizePath(path);
    
    if (!_usageStats.containsKey(normalizedPath)) {
      _usageStats[normalizedPath] = DirectoryUsage(
        path: normalizedPath,
        visitCount: 0,
        totalTime: Duration.zero,
        lastVisited: DateTime.now(),
        firstVisited: DateTime.now(),
        averageSessionTime: Duration.zero,
      );
    }
    
    final usage = _usageStats[normalizedPath]!;
    usage.visitCount++;
    usage.lastVisited = DateTime.now();
    
    debugPrint('📊 Updated usage stats for: $normalizedPath');
  }
  
  /// Detect project in directory
  Future<void> _detectProject(String path) async {
    try {
      final directory = Directory(path);
      final projectInfo = await _analyzeProject(directory);
      
      if (projectInfo != null) {
        _projects[projectInfo.name] = projectInfo;
        _projectRoots[path] = projectInfo.name;
        _currentProject = projectInfo.name;
        
        debugPrint('📦 Detected project: ${projectInfo.name}');
      } else {
        _currentProject = null;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to detect project: $e');
    }
  }
  
  /// Analyze project directory
  Future<ProjectInfo?> _analyzeProject(Directory directory) async {
    try {
      final path = directory.path;
      
      // Check for common project files
      final projectFiles = [
        'package.json', 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml',
        'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml',
        'go.mod', 'go.sum', 'go.work',
        'requirements.txt', 'pyproject.toml', 'Pipfile', 'Pipfile.lock',
        'Gemfile', 'Gemfile.lock', 'Rakefile',
        'composer.json', 'composer.lock',
        'pom.xml', 'build.gradle', 'build.gradle.kts', 'settings.gradle',
        'CMakeLists.txt', 'Makefile', 'configure.ac', 'setup.py',
        '.git', '.hg', '.svn',
        'Dockerfile', 'docker-compose.yml', 'docker-compose.yaml',
        'k8s', 'kubernetes', 'charts',
        'terraform', 'tf', 'tfstate',
        'ansible', 'playbook.yml',
        'vagrantfile', 'Vagrantfile',
        'README.md', 'README.txt', 'CHANGELOG.md',
      ];
      
      final foundFiles = <String>[];
      await for (final entity in directory.list()) {
        if (entity is File) {
          final name = entity.path.split('/').last;
          if (projectFiles.contains(name)) {
            foundFiles.add(name);
          }
        }
      }
      
      if (foundFiles.isEmpty) return null;
      
      // Determine project type
      final projectType = _determineProjectType(foundFiles);
      
      // Get project name
      final projectName = _getProjectName(path);
      
      // Analyze project structure
      final structure = await _analyzeProjectStructure(directory);
      
      return ProjectInfo(
        name: projectName,
        type: projectType,
        path: path,
        files: foundFiles,
        structure: structure,
        lastModified: (await directory.stat()).modified,
        detectedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to analyze project: $e');
      return null;
    }
  }
  
  /// Determine project type
  ProjectType _determineProjectType(List<String> files) {
    if (files.contains('package.json') || files.contains('package-lock.json')) {
      return ProjectType.nodejs;
    } else if (files.contains('Cargo.toml')) {
      return ProjectType.rust;
    } else if (files.contains('go.mod')) {
      return ProjectType.go;
    } else if (files.contains('requirements.txt') || files.contains('pyproject.toml')) {
      return ProjectType.python;
    } else if (files.contains('Gemfile')) {
      return ProjectType.ruby;
    } else if (files.contains('composer.json')) {
      return ProjectType.php;
    } else if (files.contains('pom.xml') || files.contains('build.gradle')) {
      return ProjectType.java;
    } else if (files.contains('CMakeLists.txt') || files.contains('Makefile')) {
      return ProjectType.c_cpp;
    } else if (files.contains('Dockerfile') || files.contains('docker-compose.yml')) {
      return ProjectType.docker;
    } else if (files.contains('terraform') || files.contains('tf')) {
      return ProjectType.terraform;
    } else if (files.contains('ansible')) {
      return ProjectType.ansible;
    } else if (files.contains('.git')) {
      return ProjectType.generic;
    }
    
    return ProjectType.unknown;
  }
  
  /// Get project name
  String _getProjectName(String path) {
    final parts = path.split('/');
    return parts.isNotEmpty ? parts.last : 'unknown';
  }
  
  /// Analyze project structure
  Future<ProjectStructure> _analyzeProjectStructure(Directory directory) async {
    final structure = ProjectStructure();
    
    try {
      await for (final entity in directory.list()) {
        final name = entity.path.split('/').last;
        
        if (entity is Directory) {
          structure.directories.add(name);
        } else {
          structure.files.add(name);
        }
      }
      
      // Calculate statistics
      structure.totalFiles = structure.files.length;
      structure.totalDirectories = structure.directories.length;
      structure.totalSize = await _calculateDirectorySize(directory);
      
    } catch (e) {
      debugPrint('⚠️ Failed to analyze project structure: $e');
    }
    
    return structure;
  }
  
  /// Calculate directory size
  Future<int> _calculateDirectorySize(Directory directory) async {
    int totalSize = 0;
    
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to calculate directory size: $e');
    }
    
    return totalSize;
  }
  
  /// Update directory scores
  void _updateDirectoryScores(String path) {
    final normalizedPath = _normalizePath(path);
    final usage = _usageStats[normalizedPath];
    
    if (usage == null) return;
    
    double score = 0.0;
    
    // Visit frequency score
    score += usage.visitCount * 0.3;
    
    // Recency score
    final hoursSince = DateTime.now().difference(usage.lastVisited).inHours;
    score += max(0.0, 10.0 - hoursSince * 0.1);
    
    // Session duration score
    score += usage.averageSessionTime.inMinutes * 0.2;
    
    // Project bonus
    if (_projectRoots.containsKey(path)) {
      score += 5.0;
    }
    
    _directoryScores[normalizedPath] = score;
  }
  
  /// Add to history
  void _addToHistory(String path) {
    final normalizedPath = _normalizePath(path);
    
    // Remove existing entry
    _history.removeWhere((entry) => entry.path == normalizedPath);
    
    // Add new entry
    _history.insert(0, DirectoryHistory(
      path: normalizedPath,
      timestamp: DateTime.now(),
      project: _projectRoots[normalizedPath],
      sessionDuration: Duration.zero,
    ));
    
    // Limit history size
    while (_history.length > _config.maxHistorySize) {
      _history.removeLast();
    }
  }
  
  /// Add directory bookmark
  void addBookmark(String name, String path, {String? description, List<String>? tags}) {
    final normalizedPath = _normalizePath(path);
    
    _bookmarks[name] = DirectoryBookmark(
      name: name,
      path: normalizedPath,
      description: description ?? '',
      tags: tags ?? [],
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
      accessCount: 0,
    );
    
    if (!_bookmarkNames.contains(name)) {
      _bookmarkNames.add(name);
    }
    
    _savePersistentData();
    debugPrint('🔖 Added directory bookmark: $name -> $normalizedPath');
  }
  
  /// Remove directory bookmark
  void removeBookmark(String name) {
    _bookmarks.remove(name);
    _bookmarkNames.remove(name);
    
    _savePersistentData();
    debugPrint('🗑️ Removed directory bookmark: $name');
  }
  
  /// Get directory bookmark
  DirectoryBookmark? getBookmark(String name) {
    return _bookmarks[name];
  }
  
  /// Get bookmark suggestions
  List<DirectoryBookmark> getBookmarkSuggestions(String partial) {
    if (partial.trim().isEmpty) return [];
    
    final lowerPartial = partial.toLowerCase();
    final suggestions = <DirectoryBookmark>[];
    
    for (final name in _bookmarkNames) {
      if (name.toLowerCase().contains(lowerPartial)) {
        final bookmark = _bookmarks[name]!;
        suggestions.add(bookmark);
      }
    }
    
    // Sort by relevance
    suggestions.sort((a, b) => _calculateBookmarkScore(b, partial).compareTo(_calculateBookmarkScore(a, partial)));
    
    return suggestions.take(_config.maxSuggestions).toList();
  }
  
  /// Calculate bookmark score
  double _calculateBookmarkScore(DirectoryBookmark bookmark, String partial) {
    double score = 0.0;
    
    // Name match score
    final name = bookmark.name.toLowerCase();
    final search = partial.toLowerCase();
    
    if (name.startsWith(search)) {
      score += 10.0;
    } else if (name.contains(search)) {
      score += 5.0;
    }
    
    // Access frequency bonus
    score += bookmark.accessCount * 0.1;
    
    // Recency bonus
    final daysSince = DateTime.now().difference(bookmark.lastAccessed).inDays;
    score += max(0.0, 5.0 - daysSince * 0.5);
    
    // Tag relevance
    for (final tag in bookmark.tags) {
      if (tag.toLowerCase().contains(search)) {
        score += 2.0;
      }
    }
    
    return score;
  }
  
  /// Get smart directory suggestions
  List<DirectorySuggestion> getSmartSuggestions(String partial, {String? currentPath}) {
    final suggestions = <DirectorySuggestion>[];
    
    if (partial.trim().isEmpty) {
      // Return top directories by score
      final sortedDirectories = _directoryScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      for (final entry in sortedDirectories.take(_config.maxSuggestions)) {
        suggestions.add(DirectorySuggestion(
          path: entry.key,
          type: SuggestionType.frequent,
          score: entry.value,
          reason: 'Frequently accessed directory',
        ));
      }
    } else {
      // Path-based suggestions
      suggestions.addAll(_getPathSuggestions(partial, currentPath));
      
      // Project-based suggestions
      suggestions.addAll(_getProjectSuggestions(partial));
      
      // History-based suggestions
      suggestions.addAll(_getHistorySuggestions(partial));
    }
    
    // Sort by score
    suggestions.sort((a, b) => b.score.compareTo(a.score));
    
    return suggestions.take(_config.maxSuggestions).toList();
  }
  
  /// Get path suggestions
  List<DirectorySuggestion> _getPathSuggestions(String partial, String? currentPath) {
    final suggestions = <DirectorySuggestion>[];
    final basePath = currentPath ?? _currentDirectory ?? '';
    
    try {
      final directory = Directory(basePath);
      if (!await directory.exists()) return suggestions;
      
      await for (final entity in directory.list()) {
        if (entity is Directory) {
          final name = entity.path.split('/').last;
          if (name.toLowerCase().contains(partial.toLowerCase())) {
            suggestions.add(DirectorySuggestion(
              path: entity.path,
              type: SuggestionType.path,
              score: _calculatePathScore(entity.path, partial),
              reason: 'Directory in current path',
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get path suggestions: $e');
    }
    
    return suggestions;
  }
  
  /// Get project suggestions
  List<DirectorySuggestion> _getProjectSuggestions(String partial) {
    final suggestions = <DirectorySuggestion>[];
    
    for (final project in _projects.values) {
      if (project.name.toLowerCase().contains(partial.toLowerCase())) {
        suggestions.add(DirectorySuggestion(
          path: project.path,
          type: SuggestionType.project,
          score: _calculateProjectScore(project, partial),
          reason: 'Project directory: ${project.name}',
          metadata: {
            'projectName': project.name,
            'projectType': project.type.toString(),
          },
        ));
      }
    }
    
    return suggestions;
  }
  
  /// Get history suggestions
  List<DirectorySuggestion> _getHistorySuggestions(String partial) {
    final suggestions = <DirectorySuggestion>[];
    
    for (final entry in _history) {
      if (entry.path.toLowerCase().contains(partial.toLowerCase())) {
        suggestions.add(DirectorySuggestion(
          path: entry.path,
          type: SuggestionType.history,
          score: _calculateHistoryScore(entry, partial),
          reason: 'Recently accessed directory',
          metadata: {
            'lastVisited': entry.timestamp.toIso8601String(),
            'project': entry.project,
          },
        ));
      }
    }
    
    return suggestions;
  }
  
  /// Calculate path score
  double _calculatePathScore(String path, String partial) {
    double score = 0.0;
    
    final name = path.split('/').last.toLowerCase();
    final search = partial.toLowerCase();
    
    if (name.startsWith(search)) {
      score += 10.0;
    } else if (name.contains(search)) {
      score += 5.0;
    }
    
    return score;
  }
  
  /// Calculate project score
  double _calculateProjectScore(ProjectInfo project, String partial) {
    double score = 0.0;
    
    final name = project.name.toLowerCase();
    final search = partial.toLowerCase();
    
    if (name.startsWith(search)) {
      score += 10.0;
    } else if (name.contains(search)) {
      score += 5.0;
    }
    
    // Project type bonus
    if (project.type != ProjectType.unknown) {
      score += 2.0;
    }
    
    return score;
  }
  
  /// Calculate history score
  double _calculateHistoryScore(DirectoryHistory entry, String partial) {
    double score = 0.0;
    
    final path = entry.path.toLowerCase();
    final search = partial.toLowerCase();
    
    if (path.contains(search)) {
      score += 5.0;
    }
    
    // Recency bonus
    final hoursSince = DateTime.now().difference(entry.timestamp).inHours;
    score += max(0.0, 10.0 - hoursSince * 0.1);
    
    return score;
  }
  
  /// Navigate to directory
  Future<bool> navigateToDirectory(String path) async {
    try {
      final normalizedPath = _normalizePath(path);
      final directory = Directory(normalizedPath);
      
      if (!await directory.exists()) {
        debugPrint('⚠️ Directory does not exist: $normalizedPath');
        return false;
      }
      
      // Change directory
      final result = await Process.run('cd', [normalizedPath], runInShell: true);
      if (result.exitCode == 0) {
        _currentDirectory = normalizedPath;
        await _analyzeDirectory(normalizedPath);
        
        debugPrint('📁 Navigated to directory: $normalizedPath');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to navigate to directory: $e');
    }
    
    return false;
  }
  
  /// Navigate to bookmark
  Future<bool> navigateToBookmark(String name) async {
    final bookmark = _bookmarks[name];
    if (bookmark == null) {
      debugPrint('⚠️ Bookmark not found: $name');
      return false;
    }
    
    // Update access count
    bookmark.accessCount++;
    bookmark.lastAccessed = DateTime.now();
    
    return await navigateToDirectory(bookmark.path);
  }
  
  /// Get directory usage statistics
  DirectoryUsage? getUsageStats(String path) {
    final normalizedPath = _normalizePath(path);
    return _usageStats[normalizedPath];
  }
  
  /// Get project information
  ProjectInfo? getProjectInfo(String path) {
    final normalizedPath = _normalizePath(path);
    
    // Check if this is a project root
    for (final entry in _projectRoots.entries) {
      if (normalizedPath.startsWith(entry.key)) {
        return _projects[entry.value];
      }
    }
    
    return null;
  }
  
  /// Get directory statistics
  DirectoryStatistics getStatistics() {
    return DirectoryStatistics(
      totalBookmarks: _bookmarks.length,
      totalHistory: _history.length,
      totalProjects: _projects.length,
      totalUsageStats: _usageStats.length,
      mostVisitedDirectories: _getMostVisitedDirectories(),
      mostRecentDirectories: _getMostRecentDirectories(),
      projectTypes: _getProjectTypeDistribution(),
      currentDirectory: _currentDirectory,
      currentProject: _currentProject,
    );
  }
  
  /// Get most visited directories
  List<String> _getMostVisitedDirectories() {
    return _usageStats.entries
        .toList()
        ..sort((a, b) => b.value.visitCount.compareTo(a.value.visitCount))
        .take(10)
        .map((e) => e.key)
        .toList();
  }
  
  /// Get most recent directories
  List<String> _getMostRecentDirectories() {
    return _history
        .take(10)
        .map((e) => e.path)
        .toList();
  }
  
  /// Get project type distribution
  Map<ProjectType, int> _getProjectTypeDistribution() {
    final distribution = <ProjectType, int>{};
    
    for (final project in _projects.values) {
      distribution[project.type] = (distribution[project.type] ?? 0) + 1;
    }
    
    return distribution;
  }
  
  /// Normalize path
  String _normalizePath(String path) {
    return path.replaceAll(RegExp(r'/+'), '/').replaceAll(RegExp(r'/$'), '');
  }
  
  /// Save persistent data
  Future<void> _savePersistentData() async {
    try {
      final data = {
        'bookmarks': _bookmarks.map((key, bookmark) => MapEntry(key, bookmark.toJson())).toMap(),
        'history': _history.map((entry) => entry.toJson()).toList(),
        'usageStats': _usageStats.map((key, usage) => MapEntry(key, usage.toJson())).toMap(),
        'projects': _projects.map((key, project) => MapEntry(key, project.toJson())).toMap(),
        'projectRoots': _projectRoots,
        'lastSaved': DateTime.now().toIso8601String(),
      };
      
      final dataFile = File('${Platform.environment['HOME']}/.termisol/directory_data.json');
      await dataFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save directory tracking data: $e');
    }
  }
  
  /// Export directory data
  String exportDirectoryData() {
    final data = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'bookmarks': _bookmarks.map((key, bookmark) => MapEntry(key, bookmark.toJson())).toMap(),
      'history': _history.map((entry) => entry.toJson()).toList(),
      'usageStats': _usageStats.map((key, usage) => MapEntry(key, usage.toJson())).toMap(),
      'projects': _projects.map((key, project) => MapEntry(key, project.toJson())).toMap(),
      'projectRoots': _projectRoots,
    };
    
    return jsonEncode(data);
  }
  
  /// Import directory data
  bool importDirectoryData(String jsonData) {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      
      // Import bookmarks
      final bookmarksData = data['bookmarks'] as Map<String, dynamic>?;
      if (bookmarksData != null) {
        for (final entry in bookmarksData.entries) {
          _bookmarks[entry.key] = DirectoryBookmark.fromJson(entry.value as Map<String, dynamic>);
          if (!_bookmarkNames.contains(entry.key)) {
            _bookmarkNames.add(entry.key);
          }
        }
      }
      
      // Import history
      final historyData = data['history'] as List<dynamic>?;
      if (historyData != null) {
        _history.clear();
        for (final item in historyData) {
          _history.add(DirectoryHistory.fromJson(item as Map<String, dynamic>));
        }
      }
      
      // Import usage statistics
      final usageData = data['usageStats'] as Map<String, dynamic>?;
      if (usageData != null) {
        for (final entry in usageData.entries) {
          _usageStats[entry.key] = DirectoryUsage.fromJson(entry.value as Map<String, dynamic>);
        }
      }
      
      // Import projects
      final projectsData = data['projects'] as Map<String, dynamic>?;
      if (projectsData != null) {
        for (final entry in projectsData.entries) {
          _projects[entry.key] = ProjectInfo.fromJson(entry.value as Map<String, dynamic>);
        }
      }
      
      // Import project roots
      final projectRootsData = data['projectRoots'] as Map<String, dynamic>?;
      if (projectRootsData != null) {
        _projectRoots.addAll(projectRootsData.cast<String, String>());
      }
      
      _savePersistentData();
      debugPrint('📥 Imported directory data successfully');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to import directory data: $e');
      return false;
    }
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await _savePersistentData();
    
    _bookmarks.clear();
    _bookmarkNames.clear();
    _history.clear();
    _usageStats.clear();
    _projects.clear();
    _projectRoots.clear();
    _suggestions.clear();
    _directoryScores.clear();
    
    _currentDirectory = null;
    _currentProject = null;
    
    _isInitialized = false;
    debugPrint('📁 Directory Tracking disposed');
  }
}

/// Directory bookmark data structure
class DirectoryBookmark {
  final String name;
  final String path;
  final String description;
  final List<String> tags;
  final DateTime createdAt;
  DateTime lastAccessed;
  int accessCount;
  
  DirectoryBookmark({
    required this.name,
    required this.path,
    required this.description,
    required this.tags,
    required this.createdAt,
    required this.lastAccessed,
    required this.accessCount,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'description': description,
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
    'lastAccessed': lastAccessed.toIso8601String(),
    'accessCount': accessCount,
  };
  
  factory DirectoryBookmark.fromJson(Map<String, dynamic> json) => DirectoryBookmark(
    name: json['name'] as String,
    path: json['path'] as String,
    description: json['description'] as String,
    tags: List<String>.from(json['tags'] as List? ?? []),
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastAccessed: DateTime.parse(json['lastAccessed'] as String),
    accessCount: json['accessCount'] as int,
  );
}

/// Directory history data structure
class DirectoryHistory {
  final String path;
  final DateTime timestamp;
  final String? project;
  Duration sessionDuration;
  
  DirectoryHistory({
    required this.path,
    required this.timestamp,
    this.project,
    required this.sessionDuration,
  });
  
  Map<String, dynamic> toJson() => {
    'path': path,
    'timestamp': timestamp.toIso8601String(),
    'project': project,
    'sessionDuration': sessionDuration.inMilliseconds,
  };
  
  factory DirectoryHistory.fromJson(Map<String, dynamic> json) => DirectoryHistory(
    path: json['path'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    project: json['project'] as String?,
    sessionDuration: Duration(milliseconds: json['sessionDuration'] as int? ?? 0),
  );
}

/// Directory usage statistics
class DirectoryUsage {
  final String path;
  final int visitCount;
  final Duration totalTime;
  final DateTime lastVisited;
  final DateTime firstVisited;
  final Duration averageSessionTime;
  
  DirectoryUsage({
    required this.path,
    required this.visitCount,
    required this.totalTime,
    required this.lastVisited,
    required this.firstVisited,
    required this.averageSessionTime,
  });
  
  Map<String, dynamic> toJson() => {
    'path': path,
    'visitCount': visitCount,
    'totalTime': totalTime.inMilliseconds,
    'lastVisited': lastVisited.toIso8601String(),
    'firstVisited': firstVisited.toIso8601String(),
    'averageSessionTime': averageSessionTime.inMilliseconds,
  };
  
  factory DirectoryUsage.fromJson(Map<String, dynamic> json) => DirectoryUsage(
    path: json['path'] as String,
    visitCount: json['visitCount'] as int,
    totalTime: Duration(milliseconds: json['totalTime'] as int? ?? 0),
    lastVisited: DateTime.parse(json['lastVisited'] as String),
    firstVisited: DateTime.parse(json['firstVisited'] as String),
    averageSessionTime: Duration(milliseconds: json['averageSessionTime'] as int? ?? 0),
  );
}

/// Project information
class ProjectInfo {
  final String name;
  final ProjectType type;
  final String path;
  final List<String> files;
  final ProjectStructure structure;
  final DateTime lastModified;
  final DateTime detectedAt;
  
  ProjectInfo({
    required this.name,
    required this.type,
    required this.path,
    required this.files,
    required this.structure,
    required this.lastModified,
    required this.detectedAt,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.toString(),
    'path': path,
    'files': files,
    'structure': structure.toJson(),
    'lastModified': lastModified.toIso8601String(),
    'detectedAt': detectedAt.toIso8601String(),
  };
  
  factory ProjectInfo.fromJson(Map<String, dynamic> json) => ProjectInfo(
    name: json['name'] as String,
    type: ProjectType.values.firstWhere(
      (t) => t.toString() == json['type'],
      orElse: () => ProjectType.unknown,
    ),
    path: json['path'] as String,
    files: List<String>.from(json['files'] as List? ?? []),
    structure: ProjectStructure.fromJson(json['structure'] as Map<String, dynamic>),
    lastModified: DateTime.parse(json['lastModified'] as String),
    detectedAt: DateTime.parse(json['detectedAt'] as String),
  );
}

/// Project structure
class ProjectStructure {
  final List<String> files = [];
  final List<String> directories = [];
  int totalFiles = 0;
  int totalDirectories = 0;
  int totalSize = 0;
  
  ProjectStructure();
  
  Map<String, dynamic> toJson() => {
    'files': files,
    'directories': directories,
    'totalFiles': totalFiles,
    'totalDirectories': totalDirectories,
    'totalSize': totalSize,
  };
  
  factory ProjectStructure.fromJson(Map<String, dynamic> json) {
    final structure = ProjectStructure();
    structure.files = List<String>.from(json['files'] as List? ?? []);
    structure.directories = List<String>.from(json['directories'] as List? ?? []);
    structure.totalFiles = json['totalFiles'] as int? ?? 0;
    structure.totalDirectories = json['totalDirectories'] as int? ?? 0;
    structure.totalSize = json['totalSize'] as int? ?? 0;
    return structure;
  }
}

/// Directory suggestion
class DirectorySuggestion {
  final String path;
  final SuggestionType type;
  final double score;
  final String reason;
  final Map<String, dynamic>? metadata;
  
  DirectorySuggestion({
    required this.path,
    required this.type,
    required this.score,
    required this.reason,
    this.metadata,
  });
}

/// Directory tracking configuration
class DirectoryTrackingConfig {
  final int maxHistorySize;
  final int maxSuggestions;
  final bool enableProjectDetection;
  final bool enableUsageTracking;
  final Duration cleanupInterval;
  final int retentionDays;
  
  DirectoryTrackingConfig({
    this.maxHistorySize = 1000,
    this.maxSuggestions = 10,
    this.enableProjectDetection = true,
    this.enableUsageTracking = true,
    this.cleanupInterval = const Duration(hours: 1),
    this.retentionDays = 90,
  });
  
  Map<String, dynamic> toJson() => {
    'maxHistorySize': maxHistorySize,
    'maxSuggestions': maxSuggestions,
    'enableProjectDetection': enableProjectDetection,
    'enableUsageTracking': enableUsageTracking,
    'cleanupInterval': cleanupInterval.inMilliseconds,
    'retentionDays': retentionDays,
  };
  
  factory DirectoryTrackingConfig.fromJson(Map<String, dynamic> json) {
    return DirectoryTrackingConfig(
      maxHistorySize: json['maxHistorySize'] as int? ?? 1000,
      maxSuggestions: json['maxSuggestions'] as int? ?? 10,
      enableProjectDetection: json['enableProjectDetection'] as bool? ?? true,
      enableUsageTracking: json['enableUsageTracking'] as bool? ?? true,
      cleanupInterval: Duration(milliseconds: json['cleanupInterval'] as int? ?? 3600000),
      retentionDays: json['retentionDays'] as int? ?? 90,
    );
  }
}

/// Directory statistics
class DirectoryStatistics {
  final int totalBookmarks;
  final int totalHistory;
  final int totalProjects;
  final int totalUsageStats;
  final List<String> mostVisitedDirectories;
  final List<String> mostRecentDirectories;
  final Map<ProjectType, int> projectTypes;
  final String? currentDirectory;
  final String? currentProject;
  
  DirectoryStatistics({
    required this.totalBookmarks,
    required this.totalHistory,
    required this.totalProjects,
    required this.totalUsageStats,
    required this.mostVisitedDirectories,
    required this.mostRecentDirectories,
    required this.projectTypes,
    this.currentDirectory,
    this.currentProject,
  });
}

/// Project type enumeration
enum ProjectType {
  nodejs,
  rust,
  go,
  python,
  ruby,
  php,
  java,
  c_cpp,
  docker,
  terraform,
  ansible,
  generic,
  unknown,
}

/// Suggestion type enumeration
enum SuggestionType {
  frequent,
  path,
  project,
  history,
  bookmark,
}
