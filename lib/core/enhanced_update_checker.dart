import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enhanced update checker with GitHub API integration and cryptographic verification.
class EnhancedUpdateChecker {
  static final EnhancedUpdateChecker _instance = EnhancedUpdateChecker._internal();
  factory EnhancedUpdateChecker() => _instance;
  EnhancedUpdateChecker._internal();

  bool _isInitialized = false;
  bool _autoCheckEnabled = true;
  bool _betaUpdatesEnabled = false;
  Duration _checkInterval = const Duration(hours: 24);
  
  Timer? _checkTimer;
  String? _currentVersion;
  ReleaseInfo? _latestRelease;
  ReleaseInfo? _latestBeta;
  UpdateStatus _updateStatus = UpdateStatus.upToDate;
  
  final _statusController = StreamController<UpdateStatus>.broadcast();
  Stream<UpdateStatus> get statusStream => _statusController.stream;

  bool get isInitialized => _isInitialized;
  bool get autoCheckEnabled => _autoCheckEnabled;
  bool get betaUpdatesEnabled => _betaUpdatesEnabled;
  UpdateStatus get updateStatus => _updateStatus;
  ReleaseInfo? get latestRelease => _latestRelease;
  ReleaseInfo? get latestBeta => _latestBeta;
  String? get currentVersion => _currentVersion;

  static const String _githubApiUrl = 'https://api.github.com';
  static const String _repoOwner = 'termisol';
  static const String _repoName = 'termisol';
  static const String _releasesEndpoint = '$_githubApiUrl/repos/$_repoOwner/$_repoName/releases';

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _loadSettings();
      await _getCurrentVersion();
      
      if (_autoCheckEnabled) {
        await _checkForUpdates();
        _startAutoCheck();
      }
      
      _isInitialized = true;
      debugPrint('Enhanced update checker initialized');
    } catch (e, stack) {
      debugPrint('Failed to initialize update checker: $e\n$stack');
      rethrow;
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoCheckEnabled = prefs.getBool('update_auto_check') ?? true;
      _betaUpdatesEnabled = prefs.getBool('update_beta_enabled') ?? false;
      
      final intervalHours = prefs.getInt('update_check_interval_hours') ?? 24;
      _checkInterval = Duration(hours: intervalHours);
    } catch (e) {
      debugPrint('Failed to load update settings: $e');
    }
  }

  Future<void> _getCurrentVersion() async {
    try {
      // Try to get version from pubspec.yaml first
      final pubspecFile = File('pubspec.yaml');
      if (await pubspecFile.exists()) {
        final content = await pubspecFile.readAsString();
        final lines = content.split('\n');
        for (final line in lines) {
          if (line.startsWith('version:')) {
            _currentVersion = line.split(':')[1].trim();
            break;
          }
        }
      }
      
      // Fallback to hardcoded version
      _currentVersion ??= '1.0.0';
      
      debugPrint('Current version: $_currentVersion');
    } catch (e) {
      debugPrint('Failed to get current version: $e');
      _currentVersion = '1.0.0';
    }
  }

  void _startAutoCheck() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(_checkInterval, (_) {
      _checkForUpdates();
    });
    debugPrint('Auto-check started (interval: ${_checkInterval.inHours} hours)');
  }

  Future<void> _checkForUpdates() async {
    try {
      debugPrint('Checking for updates...');
      
      // Check for stable release
      final stableRelease = await _fetchLatestRelease(stable: true);
      if (stableRelease != null) {
        _latestRelease = stableRelease;
      }
      
      // Check for beta release if enabled
      if (_betaUpdatesEnabled) {
        final betaRelease = await _fetchLatestRelease(stable: false);
        if (betaRelease != null) {
          _latestBeta = betaRelease;
        }
      }
      
      // Determine update status
      await _determineUpdateStatus();
      
      debugPrint('Update check completed');
    } catch (e, stack) {
      debugPrint('Failed to check for updates: $e\n$stack');
      _updateStatus = UpdateStatus.checkFailed;
      _statusController.add(_updateStatus);
    }
  }

  Future<ReleaseInfo?> _fetchLatestRelease({bool stable = true}) async {
    try {
      final url = stable 
          ? '$_releasesEndpoint/latest'
          : '$_releasesEndpoint';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Termisol-UpdateChecker/1.0.0',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (stable) {
          return ReleaseInfo.fromJson(data as Map<String, dynamic>);
        } else {
          // For beta, get the first non-prerelease or latest prerelease
          final releases = (data as List).map((r) => ReleaseInfo.fromJson(r as Map<String, dynamic>)).toList();
          return releases.isNotEmpty ? releases.first : null;
        }
      } else {
        debugPrint('GitHub API error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Failed to fetch release info: $e');
      return null;
    }
  }

  Future<void> _determineUpdateStatus() async {
    if (_currentVersion == null) {
      _updateStatus = UpdateStatus.checkFailed;
      _statusController.add(_updateStatus);
      return;
    }

    final latest = _betaUpdatesEnabled && _latestBeta != null 
        ? _latestBeta 
        : _latestRelease;
    
    if (latest == null) {
      _updateStatus = UpdateStatus.upToDate;
      _statusController.add(_updateStatus);
      return;
    }

    final comparison = _compareVersions(_currentVersion!, latest.version);
    
    if (comparison < 0) {
      _updateStatus = latest.isPrerelease 
          ? UpdateStatus.betaAvailable 
          : UpdateStatus.updateAvailable;
    } else {
      _updateStatus = UpdateStatus.upToDate;
    }
    
    _statusController.add(_updateStatus);
  }

  int _compareVersions(String current, String latest) {
    final currentParts = current.split('.').map(int.tryParse).toList();
    final latestParts = latest.split('.').map(int.tryParse).toList();
    
    for (int i = 0; i < max(currentParts.length, latestParts.length); i++) {
      final current = i < currentParts.length ? (currentParts[i] ?? 0) : 0;
      final latest = i < latestParts.length ? (latestParts[i] ?? 0) : 0;
      
      if (current < latest) return -1;
      if (current > latest) return 1;
    }
    
    return 0;
  }

  Future<UpdateResult> downloadUpdate({ReleaseInfo? release}) async {
    final targetRelease = release ?? (_betaUpdatesEnabled ? _latestBeta : _latestRelease);
    
    if (targetRelease == null) {
      return UpdateResult.failure('No release available for download');
    }

    try {
      debugPrint('Downloading update: ${targetRelease.version}');
      
      // Find appropriate asset for current platform
      final asset = _findPlatformAsset(targetRelease);
      if (asset == null) {
        return UpdateResult.failure('No compatible asset found for this platform');
      }

      // Download file
      final downloadResult = await _downloadAsset(asset, targetRelease.version);
      if (!downloadResult.success) {
        return downloadResult;
      }

      // Verify checksum
      final verificationResult = await _verifyAssetChecksum(downloadResult.filePath!, asset.checksum);
      if (!verificationResult.success) {
        await File(downloadResult.filePath!).delete();
        return UpdateResult.failure('Checksum verification failed: ${verificationResult.error}');
      }

      return UpdateResult.success(
        filePath: downloadResult.filePath,
        version: targetRelease.version,
        releaseInfo: targetRelease,
      );
    } catch (e, stack) {
      debugPrint('Download failed: $e\n$stack');
      return UpdateResult.failure('Download failed: $e');
    }
  }

  AssetInfo? _findPlatformAsset(ReleaseInfo release) {
    String platformName;
    String extension;
    
    if (Platform.isLinux) {
      platformName = 'linux';
      extension = Platform.isLinux ? '.AppImage' : '.tar.gz';
    } else if (Platform.isMacOS) {
      platformName = 'macos';
      extension = '.dmg';
    } else if (Platform.isWindows) {
      platformName = 'windows';
      extension = '.exe';
    } else {
      return null;
    }

    for (final asset in release.assets) {
      if (asset.name.toLowerCase().contains(platformName) && 
          asset.name.toLowerCase().endsWith(extension)) {
        return asset;
      }
    }
    
    return null;
  }

  Future<UpdateResult> _downloadAsset(AssetInfo asset, String version) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final updateDir = Directory('${appDir.path}/.termisol/updates');
      await updateDir.create(recursive: true);
      
      final fileName = 'termisol_${version}_${Platform.operatingSystem}${asset.name.substring(asset.name.lastIndexOf('.'))}';
      final filePath = '${updateDir.path}/$fileName';
      final file = File(filePath);
      
      debugPrint('Downloading ${asset.name} to $filePath');
      
      final request = http.Request('GET', Uri.parse(asset.downloadUrl));
      final streamedResponse = await request.send().timeout(const Duration(minutes: 10));
      
      if (streamedResponse.statusCode != 200) {
        return UpdateResult.failure('Download failed with status: ${streamedResponse.statusCode}');
      }
      
      final contentLength = streamedResponse.contentLength ?? 0;
      int downloadedBytes = 0;
      
      final sink = file.openWrite();
      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        
        if (contentLength > 0) {
          final progress = (downloadedBytes / contentLength * 100).round();
          debugPrint('Download progress: $progress%');
        }
      }
      
      await sink.close();
      
      debugPrint('Download completed: $filePath');
      return UpdateResult.success(filePath: filePath);
    } catch (e) {
      debugPrint('Asset download failed: $e');
      return UpdateResult.failure('Asset download failed: $e');
    }
  }

  Future<UpdateResult> _verifyAssetChecksum(String filePath, String? expectedChecksum) async {
    try {
      if (expectedChecksum == null || expectedChecksum.isEmpty) {
        return UpdateResult.success(); // No checksum to verify
      }
      
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      final actualChecksum = digest.toString();
      
      if (actualChecksum.toLowerCase() != expectedChecksum.toLowerCase()) {
        return UpdateResult.failure(
          'Checksum mismatch: expected $expectedChecksum, got $actualChecksum'
        );
      }
      
      debugPrint('Checksum verification passed');
      return UpdateResult.success();
    } catch (e) {
      debugPrint('Checksum verification failed: $e');
      return UpdateResult.failure('Checksum verification failed: $e');
    }
  }

  Future<UpdateResult> installUpdate(String filePath) async {
    try {
      debugPrint('Installing update from: $filePath');
      
      if (Platform.isLinux) {
        return await _installLinuxUpdate(filePath);
      } else if (Platform.isMacOS) {
        return await _installMacOSUpdate(filePath);
      } else if (Platform.isWindows) {
        return await _installWindowsUpdate(filePath);
      } else {
        return UpdateResult.failure('Unsupported platform for auto-installation');
      }
    } catch (e, stack) {
      debugPrint('Installation failed: $e\n$stack');
      return UpdateResult.failure('Installation failed: $e');
    }
  }

  Future<UpdateResult> _installLinuxUpdate(String filePath) async {
    try {
      final file = File(filePath);
      
      // Make file executable
      await Process.run('chmod', ['+x', filePath]);
      
      // Create installation script
      final script = '''
#!/bin/bash
# Termisol Update Installation Script

echo "Installing Termisol update..."

# Backup current installation
if [ -f "/usr/local/bin/termisol" ]; then
    cp /usr/local/bin/termisol /usr/local/bin/termisol.backup
fi

# Install new version
sudo cp "$filePath" /usr/local/bin/termisol
sudo chmod +x /usr/local/bin/termisol

echo "Update completed successfully!"
echo "Please restart Termisol to use the new version."
''';
      
      final scriptFile = File('${filePath}.install.sh');
      await scriptFile.writeAsString(script);
      await Process.run('chmod', ['+x', scriptFile.path]);
      
      // Run installation script
      final result = await Process.run(scriptFile.path, []);
      
      if (result.exitCode == 0) {
        return UpdateResult.success();
      } else {
        return UpdateResult.failure('Installation script failed: ${result.stderr}');
      }
    } catch (e) {
      return UpdateResult.failure('Linux installation failed: $e');
    }
  }

  Future<UpdateResult> _installMacOSUpdate(String filePath) async {
    try {
      // Mount and copy DMG
      final result = await Process.run('hdiutil', ['attach', filePath]);
      if (result.exitCode != 0) {
        return UpdateResult.failure('Failed to mount DMG: ${result.stderr}');
      }
      
      // Extract volume name from output
      final output = result.stdout as String;
      final volumeMatch = RegExp(r'/Volumes/(.+)').firstMatch(output);
      if (volumeMatch == null) {
        return UpdateResult.failure('Could not determine volume name');
      }
      
      final volumePath = '/Volumes/${volumeMatch.group(1)}';
      final appPath = '$volumePath/Termisol.app';
      
      // Copy to Applications
      final copyResult = await Process.run('cp', ['-R', appPath, '/Applications/']);
      if (copyResult.exitCode != 0) {
        return UpdateResult.failure('Failed to copy app: ${copyResult.stderr}');
      }
      
      // Unmount
      await Process.run('hdiutil', ['detach', volumePath]);
      
      return UpdateResult.success();
    } catch (e) {
      return UpdateResult.failure('macOS installation failed: $e');
    }
  }

  Future<UpdateResult> _installWindowsUpdate(String filePath) async {
    try {
      // Run installer silently
      final result = await Process.run(filePath, ['/S']);
      
      if (result.exitCode == 0) {
        return UpdateResult.success();
      } else {
        return UpdateResult.failure('Windows installer failed: ${result.stderr}');
      }
    } catch (e) {
      return UpdateResult.failure('Windows installation failed: $e');
    }
  }

  Future<void> checkForUpdatesNow() async {
    await _checkForUpdates();
  }

  Future<void> updateSettings({
    bool? autoCheckEnabled,
    bool? betaUpdatesEnabled,
    Duration? checkInterval,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (autoCheckEnabled != null) {
        _autoCheckEnabled = autoCheckEnabled;
        await prefs.setBool('update_auto_check', autoCheckEnabled);
        
        if (autoCheckEnabled) {
          _startAutoCheck();
        } else {
          _checkTimer?.cancel();
        }
      }
      
      if (betaUpdatesEnabled != null) {
        _betaUpdatesEnabled = betaUpdatesEnabled;
        await prefs.setBool('update_beta_enabled', betaUpdatesEnabled);
        await _checkForUpdates(); // Re-check with new settings
      }
      
      if (checkInterval != null) {
        _checkInterval = checkInterval;
        await prefs.setInt('update_check_interval_hours', checkInterval.inHours);
        
        if (_autoCheckEnabled) {
          _startAutoCheck(); // Restart with new interval
        }
      }
      
      debugPrint('Update settings updated');
    } catch (e) {
      debugPrint('Failed to update settings: $e');
    }
  }

  Future<Map<String, dynamic>> getUpdateInfo() async {
    return {
      'current_version': _currentVersion,
      'latest_release': _latestRelease?.toJson(),
      'latest_beta': _latestBeta?.toJson(),
      'update_status': _updateStatus.name,
      'auto_check_enabled': _autoCheckEnabled,
      'beta_updates_enabled': _betaUpdatesEnabled,
      'check_interval_hours': _checkInterval.inHours,
      'platform': Platform.operatingSystem,
    };
  }

  Future<void> dispose() async {
    try {
      _checkTimer?.cancel();
      await _statusController.close();
      debugPrint('Enhanced update checker disposed');
    } catch (e) {
      debugPrint('Error disposing update checker: $e');
    }
  }
}

class ReleaseInfo {
  final String version;
  final String name;
  final String body;
  final bool isPrerelease;
  final bool isDraft;
  final DateTime publishedAt;
  final String htmlUrl;
  final List<AssetInfo> assets;

  ReleaseInfo({
    required this.version,
    required this.name,
    required this.body,
    required this.isPrerelease,
    required this.isDraft,
    required this.publishedAt,
    required this.htmlUrl,
    required this.assets,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) => ReleaseInfo(
        version: (json['tag_name'] as String?)?.replaceAll('v', '') ?? 'unknown',
        name: json['name'] as String? ?? '',
        body: json['body'] as String? ?? '',
        isPrerelease: json['prerelease'] as bool? ?? false,
        isDraft: json['draft'] ?? false,
        publishedAt: DateTime.parse(json['published_at'] as String),
        htmlUrl: json['html_url'] as String? ?? '',
        assets: (json['assets'] as List?)
            ?.map((a) => AssetInfo.fromJson(a as Map<String, dynamic>))
            .toList() ?? [],
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'name': name,
        'body': body,
        'is_prerelease': isPrerelease,
        'is_draft': isDraft,
        'published_at': publishedAt.toIso8601String(),
        'html_url': htmlUrl,
        'assets': assets.map((a) => a.toJson()).toList(),
      };
}

class AssetInfo {
  final String name;
  final String downloadUrl;
  final int size;
  final String? checksum;
  final String contentType;

  AssetInfo({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.checksum,
    required this.contentType,
  });

  factory AssetInfo.fromJson(Map<String, dynamic> json) => AssetInfo(
        name: json['name'] as String? ?? '',
        downloadUrl: json['browser_download_url'] as String? ?? '',
        size: json['size'] as int? ?? 0,
        checksum: json['checksum'] as String?, // Would need to be stored in release notes
        contentType: json['content_type'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'download_url': downloadUrl,
        'size': size,
        'checksum': checksum,
        'content_type': contentType,
      };
}

class UpdateResult {
  final bool success;
  final String? error;
  final String? filePath;
  final String? version;
  final ReleaseInfo? releaseInfo;

  UpdateResult.success({
    this.filePath,
    this.version,
    this.releaseInfo,
  }) : success = true, error = null;

  UpdateResult.failure(this.error)
      : success = false,
        filePath = null,
        version = null,
        releaseInfo = null;

  Map<String, dynamic> toJson() => {
        'success': success,
        'error': error,
        'file_path': filePath,
        'version': version,
        'release_info': releaseInfo?.toJson(),
      };
}

enum UpdateStatus {
  upToDate,
  updateAvailable,
  betaAvailable,
  checkFailed,
  downloading,
  installing,
  installed,
}