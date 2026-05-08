import 'dart:io';
import 'package:flutter/foundation.dart';

/// Centralized API endpoint configuration
/// 
/// This class provides a centralized way to manage all API endpoints
/// and configuration values throughout the application.
class ApiEndpoints {
  // Singleton pattern
  static final ApiEndpoints _instance = ApiEndpoints._internal();
  factory ApiEndpoints() => _instance;
  ApiEndpoints._internal();

  // OpenAI Configuration
  String get openaiBaseUrl {
    return Platform.environment['OPENAI_BASE_URL'] ?? 
           (kDebugMode ? 'https://api.openai.com/v1' : 'https://api.openai.com/v1');
  }

  String get openaiChatCompletions => '$openaiBaseUrl/chat/completions';

  // NVIDIA AI Configuration
  String get nvidiaApiBaseUrl {
    return Platform.environment['NVIDIA_API_URL'] ?? 
           'https://api.nvidia.com/v1';
  }

  String get nvidiaNimEndpoint {
    return Platform.environment['NVIDIA_NIM_URL'] ?? 
           'https://integrate.nvidia.com/v1/chat/completions';
  }

  // Docker Configuration
  String get dockerHost {
    return Platform.environment['DOCKER_HOST'] ?? 
           (Platform.isWindows ? 'npipe:////./pipe/docker_engine' : 'unix:///var/run/docker.sock');
  }

  String get dockerTcpHost {
    return Platform.environment['DOCKER_TCP_HOST'] ?? 
           'localhost:2375';
  }

  // Cache Configuration
  String get cacheBaseUrl {
    return Platform.environment['CACHE_BASE_URL'] ?? 
           'https://cache.termisol.com/api';
  }

  // Git Service Configuration
  Map<String, String> get gitServiceUrls => {
    'github': Platform.environment['GITHUB_API_URL'] ?? 'https://api.github.com',
    'gitlab': Platform.environment['GITLAB_API_URL'] ?? 'https://gitlab.com/api/v4',
    'bitbucket': Platform.environment['BITBUCKET_API_URL'] ?? 'https://api.bitbucket.org/2.0',
  };

  // SSH Configuration
  String get defaultSshHost {
    return Platform.environment['DEFAULT_SSH_HOST'] ?? 'localhost';
  }

  // Network Configuration
  String get defaultLocalhost {
    return Platform.environment['LOCALHOST'] ?? '127.0.0.1';
  }

  // Database Configuration
  Map<String, String> get databaseHosts => {
    'memster': Platform.environment['MEMSTER_HOST'] ?? '192.168.4.250',
    'nocobase': Platform.environment['NOCOBASE_HOST'] ?? '192.168.4.233',
  };

  // Performance Configuration
  int get maxCacheSize {
    final envValue = Platform.environment['MAX_CACHE_SIZE'];
    return envValue != null ? int.tryParse(envValue) ?? 1000 : 1000;
  }

  int get maxLogFiles {
    final envValue = Platform.environment['MAX_LOG_FILES'];
    return envValue != null ? int.tryParse(envValue) ?? 5 : 5;
  }

  int get maxLogFileSize {
    final envValue = Platform.environment['MAX_LOG_FILE_SIZE'];
    return envValue != null ? int.tryParse(envValue) ?? 10485760 : 10485760; // 10MB
  }

  // AI Configuration
  int get maxContextLength {
    final envValue = Platform.environment['MAX_CONTEXT_LENGTH'];
    return envValue != null ? int.tryParse(envValue) ?? 4096 : 4096;
  }

  int get maxRetries {
    final envValue = Platform.environment['MAX_RETRIES'];
    return envValue != null ? int.tryParse(envValue) ?? 3 : 3;
  }

  Duration get requestTimeout {
    final envValue = Platform.environment['REQUEST_TIMEOUT_SECONDS'];
    final seconds = envValue != null ? int.tryParse(envValue) ?? 30 : 30;
    return Duration(seconds: seconds);
  }

  // Validation methods
  bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  bool isValidHost(String host) {
    try {
      final address = InternetAddress.tryParse(host);
      if (address != null) {
        return true;
      }
      // Check if it's a valid hostname
      return host.isNotEmpty && !host.contains(' ') && host != 'localhost';
    } catch (e) {
      return false;
    }
  }

  // Configuration validation
  Map<String, String> validateConfiguration() {
    final issues = <String, String>{};

    if (!isValidUrl(openaiBaseUrl)) {
      issues['openai_base_url'] = 'Invalid OpenAI base URL: $openaiBaseUrl';
    }

    if (!isValidUrl(nvidiaApiBaseUrl)) {
      issues['nvidia_api_url'] = 'Invalid NVIDIA API URL: $nvidiaApiBaseUrl';
    }

    if (!isValidUrl(nvidiaNimEndpoint)) {
      issues['nvidia_nim_url'] = 'Invalid NVIDIA NIM URL: $nvidiaNimEndpoint';
    }

    if (!isValidUrl(cacheBaseUrl)) {
      issues['cache_base_url'] = 'Invalid cache base URL: $cacheBaseUrl';
    }

    // Validate git service URLs
    gitServiceUrls.forEach((service, url) {
      if (!isValidUrl(url)) {
        issues['git_$service'] = 'Invalid $service API URL: $url';
      }
    });

    // Validate database hosts
    databaseHosts.forEach((db, host) {
      if (!isValidHost(host)) {
        issues['db_$db'] = 'Invalid $db host: $host';
      }
    });

    return issues;
  }

  // Export configuration for debugging
  Map<String, dynamic> exportConfiguration() {
    return {
      'openai': {
        'base_url': openaiBaseUrl,
        'chat_completions': openaiChatCompletions,
      },
      'nvidia': {
        'api_url': nvidiaApiBaseUrl,
        'nim_endpoint': nvidiaNimEndpoint,
      },
      'docker': {
        'host': dockerHost,
        'tcp_host': dockerTcpHost,
      },
      'cache': {
        'base_url': cacheBaseUrl,
        'max_size': maxCacheSize,
      },
      'git_services': gitServiceUrls,
      'ssh': {
        'default_host': defaultSshHost,
      },
      'network': {
        'localhost': defaultLocalhost,
      },
      'databases': databaseHosts,
      'performance': {
        'max_log_files': maxLogFiles,
        'max_log_file_size': maxLogFileSize,
        'max_context_length': maxContextLength,
        'max_retries': maxRetries,
        'request_timeout': requestTimeout.inSeconds,
      },
    };
  }
}

/// Configuration exception for invalid settings
class ConfigurationException implements Exception {
  final String message;
  final String field;
  
  ConfigurationException(this.message, this.field);
  
  @override
  String toString() => 'ConfigurationException: $message (field: $field)';
}
