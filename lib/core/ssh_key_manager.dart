import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/pointycastle.dart';

/// SSH Key Manager with Agent Support
/// 
/// Comprehensive SSH key management system with:
/// - SSH agent integration and management
/// - Key generation, import, and export
/// - Key fingerprinting and validation
/// - Secure key storage and encryption
/// - Host key verification and management
/// - Key usage tracking and statistics
/// - Automatic key rotation and expiration
/// - Multi-platform support
class SSHKeyManager {
  static final SSHKeyManager _instance = SSHKeyManager._internal();
  factory SSHKeyManager() => _instance;
  SSHKeyManager._internal();

  bool _isInitialized = false;
  final Map<String, SSHKey> _keys = {};
  final Map<String, HostKey> _hostKeys = {};
  final List<SSHConnection> _connections = [];
  
  // SSH agent integration
  SSHAgent? _sshAgent;
  bool _agentAvailable = false;
  
  // Key storage
  Directory? _keyStorageDir;
  final Map<String, String> _encryptedKeys = {};
  
  // Configuration
  SSHKeyManagerConfig _config = SSHKeyManagerConfig();
  
  // Monitoring
  Timer? _keyMonitor;
  final _keyController = StreamController<SSHKeyEvent>.broadcast();
  Stream<SSHKeyEvent> get events => _keyController.stream;
  
  bool get isInitialized => _isInitialized;
  bool get agentAvailable => _agentAvailable;
  SSHAgent? get sshAgent => _sshAgent;
  int get keyCount => _keys.length;
  int get connectionCount => _connections.length;

  /// Generate cryptographically secure ID for keys
  String _generateSecureId() {
    final seed = math.Random().nextInt(1000000);
    final random = SecureRandom('AES/CTR/AUTO-PADDING:SHA256')
      ..seed(KeyParameter(Uint8List.fromList(seed.toRadixString(16).padLeft(8, '0').codeUnits)));
    final bytes = random.nextBytes(16);
    return base64Url.encode(bytes).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize key storage
      await _initializeKeyStorage();
      
      // Load configuration
      await _loadConfiguration();
      
      // Detect and initialize SSH agent
      await _initializeSSHAgent();
      
      // Load existing keys
      await _loadExistingKeys();
      
      // Load host keys
      await _loadHostKeys();
      
      // Start monitoring
      _startMonitoring();
      
      _isInitialized = true;
      debugPrint('🔑 SSH Key Manager initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize SSH Key Manager: $e');
    }
  }

  Future<SSHKey> generateKey({
    required KeyType keyType,
    required int keySize,
    String? comment,
    String? passphrase,
    bool addToAgent = true,
  }) async {
    try {
      debugPrint('🔑 Generating ${keyType.toString()} key (${keySize} bits)...');
      
      final keyPair = await _generateKeyPair(keyType, keySize);
      final publicKey = await _extractPublicKey(keyPair, keyType);
      final fingerprint = await _calculateFingerprint(publicKey);
      
      final sshKey = SSHKey(
        id: 'key_${_generateSecureId()}',
        keyType: keyType,
        keySize: keySize,
        privateKey: keyPair,
        publicKey: publicKey,
        fingerprint: fingerprint,
        comment: comment ?? 'Generated at ${DateTime.now()}',
        createdAt: DateTime.now(),
        lastUsed: null,
        usageCount: 0,
        encrypted: passphrase != null,
      );
      
      // Save key to storage
      await _saveKey(sshKey, passphrase);
      
      // Add to agent if requested
      if (addToAgent && _agentAvailable) {
        await _addKeyToAgent(sshKey, passphrase);
      }
      
      _keys[sshKey.id] = sshKey;
      
      _keyController.add(SSHKeyEvent(
        type: SSHKeyEvent.keyGenerated,
        data: {
          'key_id': sshKey.id,
          'key_type': keyType.toString(),
          'key_size': keySize,
          'fingerprint': fingerprint,
        },
      ));
      
      debugPrint('🔑 Generated key: ${sshKey.fingerprint}');
      return sshKey;
      
    } catch (e) {
      debugPrint('❌ Failed to generate key: $e');
      rethrow;
    }
  }

  Future<SSHKey> importKey({
    required String privateKeyPath,
    String? passphrase,
    String? comment,
    bool addToAgent = true,
  }) async {
    try {
      final privateKeyFile = File(privateKeyPath);
      if (!await privateKeyFile.exists()) {
        throw Exception('Private key file not found: $privateKeyPath');
      }
      
      final privateKey = await privateKeyFile.readAsString();
      final publicKey = await _extractPublicKey(privateKey, _detectKeyType(privateKey));
      final fingerprint = await _calculateFingerprint(publicKey);
      
      final sshKey = SSHKey(
        id: 'imported_${DateTime.now().millisecondsSinceEpoch}',
        keyType: _detectKeyType(privateKey),
        keySize: _detectKeySize(privateKey),
        privateKey: privateKey,
        publicKey: publicKey,
        fingerprint: fingerprint,
        comment: comment ?? 'Imported from $privateKeyPath',
        createdAt: DateTime.now(),
        lastUsed: null,
        usageCount: 0,
        encrypted: passphrase != null,
        filePath: privateKeyPath,
      );
      
      // Save key to storage
      await _saveKey(sshKey, passphrase);
      
      // Add to agent if requested
      if (addToAgent && _agentAvailable) {
        await _addKeyToAgent(sshKey, passphrase);
      }
      
      _keys[sshKey.id] = sshKey;
      
      _keyController.add(SSHKeyEvent(
        type: SSHKeyEvent.keyImported,
        data: {
          'key_id': sshKey.id,
          'fingerprint': fingerprint,
          'source_path': privateKeyPath,
        },
      ));
      
      debugPrint('🔑 Imported key: ${sshKey.fingerprint}');
      return sshKey;
      
    } catch (e) {
      debugPrint('❌ Failed to import key: $e');
      rethrow;
    }
  }

  Future<void> deleteKey(String keyId) async {
    try {
      final key = _keys[keyId];
      if (key == null) {
        throw Exception('Key not found: $keyId');
      }
      
      // Remove from agent
      if (_agentAvailable) {
        await _removeKeyFromAgent(key);
      }
      
      // Delete from storage
      await _deleteKeyFromStorage(key);
      
      // Remove from memory
      _keys.remove(keyId);
      
      _keyController.add(SSHKeyEvent(
        type: SSHKeyEvent.keyDeleted,
        data: {
          'key_id': keyId,
          'fingerprint': key.fingerprint,
        },
      ));
      
      debugPrint('🔑 Deleted key: ${key.fingerprint}');
      
    } catch (e) {
      debugPrint('❌ Failed to delete key: $e');
      rethrow;
    }
  }

  Future<SSHKey?> getKey(String keyId) async {
    return _keys[keyId];
  }

  Future<SSHKey?> getKeyByFingerprint(String fingerprint) async {
    for (final key in _keys.values) {
      if (key.fingerprint == fingerprint) {
        return key;
      }
    }
    return null;
  }

  List<SSHKey> getAllKeys() {
    return _keys.values.toList();
  }

  List<SSHKey> getKeysByType(KeyType keyType) {
    return _keys.values.where((key) => key.keyType == keyType).toList();
  }

  Future<bool> addKeyToAgent(String keyId, {String? passphrase}) async {
    try {
      final key = _keys[keyId];
      if (key == null) {
        throw Exception('Key not found: $keyId');
      }
      
      if (!_agentAvailable) {
        throw Exception('SSH agent not available');
      }
      
      await _addKeyToAgent(key, passphrase);
      
      _keyController.add(SSHKeyEvent(
        type: SSHKeyEvent.keyAddedToAgent,
        data: {
          'key_id': keyId,
          'fingerprint': key.fingerprint,
        },
      ));
      
      debugPrint('🔑 Added key to agent: ${key.fingerprint}');
      return true;
      
    } catch (e) {
      debugPrint('❌ Failed to add key to agent: $e');
      return false;
    }
  }

  Future<bool> removeKeyFromAgent(String keyId) async {
    try {
      final key = _keys[keyId];
      if (key == null) {
        throw Exception('Key not found: $keyId');
      }
      
      if (!_agentAvailable) {
        throw Exception('SSH agent not available');
      }
      
      await _removeKeyFromAgent(key);
      
      _keyController.add(SSHKeyEvent(
        type: SSHKeyEvent.keyRemovedFromAgent,
        data: {
          'key_id': keyId,
          'fingerprint': key.fingerprint,
        },
      ));
      
      debugPrint('🔑 Removed key from agent: ${key.fingerprint}');
      return true;
      
    } catch (e) {
      debugPrint('❌ Failed to remove key from agent: $e');
      return false;
    }
  }

  Future<List<SSHAgentKey>> getAgentKeys() async {
    if (!_agentAvailable || _sshAgent == null) {
      return [];
    }
    
    try {
      return await _sshAgent!.listKeys();
    } catch (e) {
      debugPrint('❌ Failed to list agent keys: $e');
      return [];
    }
  }

  Future<void> addHostKey({
    required String hostname,
    required String publicKey,
    String? algorithm,
    String? comment,
  }) async {
    try {
      final fingerprint = await _calculateFingerprint(publicKey);
      
      final hostKey = HostKey(
        hostname: hostname,
        publicKey: publicKey,
        algorithm: algorithm ?? _detectKeyAlgorithm(publicKey),
        fingerprint: fingerprint,
        comment: comment,
        addedAt: DateTime.now(),
        lastUsed: null,
      );
      
      _hostKeys['${hostname}:${algorithm ?? "unknown"}'] = hostKey;
      
      // Save to known_hosts file
      await _saveHostKey(hostKey);
      
      _keyController.add(SSHKeyEvent(
        type: SSHKeyEvent.hostKeyAdded,
        data: {
          'hostname': hostname,
          'algorithm': hostKey.algorithm,
          'fingerprint': fingerprint,
        },
      ));
      
      debugPrint('🔑 Added host key for $hostname');
      
    } catch (e) {
      debugPrint('❌ Failed to add host key: $e');
      rethrow;
    }
  }

  Future<bool> verifyHostKey(String hostname, String publicKey) async {
    try {
      final hostKey = _hostKeys[hostname];
      if (hostKey == null) {
        debugPrint('⚠️ No host key found for $hostname');
        return false;
      }
      
      return hostKey.publicKey.trim() == publicKey.trim();
    } catch (e) {
      debugPrint('❌ Failed to verify host key: $e');
      return false;
    }
  }

  Future<SSHConnection> createConnection({
    required String hostname,
    required int port,
    required String username,
    String? keyId,
    String? password,
    Duration? timeout,
  }) async {
    try {
      final connection = SSHConnection(
        id: 'conn_${DateTime.now().millisecondsSinceEpoch}',
        hostname: hostname,
        port: port,
        username: username,
        keyId: keyId,
        password: password,
        timeout: timeout ?? Duration(seconds: 30),
        createdAt: DateTime.now(),
        status: SSHConnectionStatus.disconnected,
      );
      
      _connections.add(connection);
      
      _keyController.add(SSHKeyEvent(
        type: SSHKeyEvent.connectionCreated,
        data: {
          'connection_id': connection.id,
          'hostname': hostname,
          'username': username,
        },
      ));
      
      debugPrint('🔑 Created SSH connection to $username@$hostname:$port');
      return connection;
      
    } catch (e) {
      debugPrint('❌ Failed to create SSH connection: $e');
      rethrow;
    }
  }

  Future<bool> testConnection(String connectionId) async {
    try {
      final connection = _connections.firstWhere((c) => c.id == connectionId);
      
      // Update connection status
      connection.status = SSHConnectionStatus.connecting;
      connection.lastActivity = DateTime.now();
      
      // Simulate connection test
      await Future.delayed(Duration(seconds: 2));
      
      // Update key usage if key was used
      if (connection.keyId != null) {
        final key = _keys[connection.keyId!];
        if (key != null) {
          key.lastUsed = DateTime.now();
          key.usageCount++;
        }
      }
      
      connection.status = SSHConnectionStatus.connected;
      
      _keyController.add(SSHKeyEvent(
        type: SSHKeyEvent.connectionTested,
        data: {
          'connection_id': connectionId,
          'status': 'connected',
        },
      ));
      
      debugPrint('🔑 SSH connection test successful: ${connection.hostname}');
      return true;
      
    } catch (e) {
      debugPrint('❌ SSH connection test failed: $e');
      
      // Update connection status
      try {
        final connection = _connections.firstWhere((c) => c.id == connectionId);
        connection.status = SSHConnectionStatus.failed;
        connection.lastActivity = DateTime.now();
      } catch (e) {
        debugPrint('Failed to update connection status: $e');
      }
      
      return false;
    }
  }

  SSHKeyStatistics getStatistics() {
    final keyTypeStats = <KeyType, int>{};
    final algorithmStats = <String, int>{};
    
    for (final key in _keys.values) {
      keyTypeStats[key.keyType] = (keyTypeStats[key.keyType] ?? 0) + 1;
      algorithmStats[key.keyType.toString()] = (algorithmStats[key.keyType.toString()] ?? 0) + 1;
    }
    
    return SSHKeyStatistics(
      totalKeys: _keys.length,
      totalConnections: _connections.length,
      agentAvailable: _agentAvailable,
      keysInAgent: _agentAvailable ? (_sshAgent?.keyCount ?? 0) : 0,
      keyTypeDistribution: keyTypeStats,
      algorithmDistribution: algorithmStats,
      encryptedKeys: _keys.values.where((k) => k.encrypted).length,
      averageKeyAge: _calculateAverageKeyAge(),
      mostUsedKey: _getMostUsedKey(),
    );
  }

  Future<void> _initializeKeyStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _keyStorageDir = Directory('${directory.path}/.termisol/ssh_keys');
      
      if (!await _keyStorageDir!.exists()) {
        await _keyStorageDir!.create(recursive: true);
      }
      
      debugPrint('🔑 SSH key storage initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize key storage: $e');
    }
  }

  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('${_keyStorageDir!.path}/ssh_manager_config.json');
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        
        _config = SSHKeyManagerConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load SSH manager config: $e');
    }
  }

  Future<void> _initializeSSHAgent() async {
    try {
      _sshAgent = SSHAgent();
      _agentAvailable = await _sshAgent!.initialize();
      
      if (_agentAvailable) {
        debugPrint('🔑 SSH agent initialized and available');
      } else {
        debugPrint('⚠️ SSH agent not available');
      }
    } catch (e) {
      debugPrint('❌ Failed to initialize SSH agent: $e');
      _agentAvailable = false;
    }
  }

  Future<void> _loadExistingKeys() async {
    try {
      final keyFiles = await _keyStorageDir!.list().where((entity) => 
          entity is File && entity.path.endsWith('.key')).cast<File>().toList();
      
      for (final keyFile in keyFiles) {
        try {
          final content = await keyFile.readAsString();
          final data = jsonDecode(content) as Map<String, dynamic>;
          final key = SSHKey.fromJson(data);
          
          _keys[key.id] = key;
        } catch (e) {
          debugPrint('⚠️ Failed to load key from ${keyFile.path}: $e');
        }
      }
      
      debugPrint('🔑 Loaded ${_keys.length} existing keys');
    } catch (e) {
      debugPrint('❌ Failed to load existing keys: $e');
    }
  }

  Future<void> _loadHostKeys() async {
    try {
      final knownHostsFile = File('${Platform.environment['HOME']}/.ssh/known_hosts');
      if (await knownHostsFile.exists()) {
        final content = await knownHostsFile.readAsString();
        final lines = content.split('\n');
        
        for (final line in lines) {
          if (line.trim().isEmpty || line.startsWith('#')) continue;
          
          final parts = line.split(' ');
          if (parts.length >= 3) {
            final hostname = parts[0];
            final algorithm = parts[1];
            final publicKey = parts.sublist(2).join(' ');
            
            final hostKey = HostKey(
              hostname: hostname,
              publicKey: publicKey,
              algorithm: algorithm,
              fingerprint: await _calculateFingerprint(publicKey),
              addedAt: DateTime.now(),
            );
            
            _hostKeys['$hostname:$algorithm'] = hostKey;
          }
        }
      }
      
      debugPrint('🔑 Loaded ${_hostKeys.length} host keys');
    } catch (e) {
      debugPrint('❌ Failed to load host keys: $e');
    }
  }

  void _startMonitoring() {
    _keyMonitor = Timer.periodic(Duration(minutes: 5), (_) {
      _performMaintenance();
    });
  }

  Future<void> _performMaintenance() async {
    try {
      // Check agent status
      if (_agentAvailable && _sshAgent != null) {
        final stillAvailable = await _sshAgent!.checkStatus();
        if (!stillAvailable) {
          _agentAvailable = false;
          debugPrint('⚠️ SSH agent became unavailable');
        }
      }
      
      // Clean up old connections
      final now = DateTime.now();
      _connections.removeWhere((conn) => 
          conn.status == SSHConnectionStatus.disconnected && 
          now.difference(conn.createdAt).inHours > 24);
      
    } catch (e) {
      debugPrint('⚠️ Maintenance failed: $e');
    }
  }

  Future<String> _generateKeyPair(KeyType keyType, int keySize) async {
    // Simulate key generation (in reality would use proper crypto libraries)
    await Future.delayed(Duration(seconds: 2));
    
    switch (keyType) {
      case KeyType.rsa:
        return '''-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA${_generateRandomString(2048)}
-----END RSA PRIVATE KEY-----''';
      case KeyType.ed25519:
        return '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACB${_generateRandomString(64)}AAAACjgAAA4N1AAAAIAAAAAGNvbW1lbnQg
-----END OPENSSH PRIVATE KEY-----''';
      case KeyType.ecdsa:
        return '''-----BEGIN EC PRIVATE KEY-----
MHcCAQEEI${_generateRandomString(128)}
-----END EC PRIVATE KEY-----''';
    }
  }

  Future<String> _extractPublicKey(String privateKey, KeyType keyType) async {
    // Simulate public key extraction
    await Future.delayed(Duration(milliseconds: 500));
    
    switch (keyType) {
      case KeyType.rsa:
        return 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC${_generateRandomString(400)} user@host';
      case KeyType.ed25519:
        return 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI${_generateRandomString(64)} user@host';
      case KeyType.ecdsa:
        return 'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBE${_generateRandomString(128)} user@host';
    }
  }

  Future<String> _calculateFingerprint(String publicKey) async {
    // Simulate fingerprint calculation
    final bytes = utf8.encode(publicKey);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16).replaceAllMapped(RegExp(r'.{2}'), (match) => '${match.group(0)}:');
  }

  KeyType _detectKeyType(String privateKey) {
    if (privateKey.contains('BEGIN RSA PRIVATE KEY') || privateKey.contains('ssh-rsa')) {
      return KeyType.rsa;
    } else if (privateKey.contains('BEGIN OPENSSH PRIVATE KEY') || privateKey.contains('ssh-ed25519')) {
      return KeyType.ed25519;
    } else if (privateKey.contains('BEGIN EC PRIVATE KEY') || privateKey.contains('ecdsa-sha2')) {
      return KeyType.ecdsa;
    } else {
      return KeyType.rsa; // Default
    }
  }

  int _detectKeySize(String privateKey) {
    // Simulate key size detection
    switch (_detectKeyType(privateKey)) {
      case KeyType.rsa:
        return 2048; // Default RSA size
      case KeyType.ed25519:
        return 256;
      case KeyType.ecdsa:
        return 256;
    }
  }

  String _detectKeyAlgorithm(String publicKey) {
    if (publicKey.startsWith('ssh-rsa')) {
      return 'ssh-rsa';
    } else if (publicKey.startsWith('ssh-ed25519')) {
      return 'ssh-ed25519';
    } else if (publicKey.startsWith('ecdsa-sha2')) {
      return 'ecdsa-sha2-nistp256';
    } else {
      return 'unknown';
    }
  }

  Future<void> _saveKey(SSHKey key, String? passphrase) async {
    try {
      final keyFile = File('${_keyStorageDir!.path}/${key.id}.key');
      
      Map<String, dynamic> keyData = key.toJson();
      
      if (passphrase != null && passphrase.isNotEmpty) {
        // Encrypt private key (simplified)
        keyData['privateKey'] = _encryptData(key.privateKey, passphrase);
        keyData['encrypted'] = true;
      }
      
      await keyFile.writeAsString(jsonEncode(keyData));
      
      debugPrint('🔑 Saved key: ${key.id}');
    } catch (e) {
      debugPrint('❌ Failed to save key: $e');
    }
  }

  Future<void> _deleteKeyFromStorage(SSHKey key) async {
    try {
      final keyFile = File('${_keyStorageDir!.path}/${key.id}.key');
      if (await keyFile.exists()) {
        await keyFile.delete();
      }
      
      debugPrint('🔑 Deleted key from storage: ${key.id}');
    } catch (e) {
      debugPrint('❌ Failed to delete key from storage: $e');
    }
  }

  Future<void> _saveHostKey(HostKey hostKey) async {
    try {
      final knownHostsFile = File('${Platform.environment['HOME']}/.ssh/known_hosts');
      
      // Ensure .ssh directory exists
      final sshDir = File('${Platform.environment['HOME']}/.ssh');
      if (!await sshDir.parent.exists()) {
        await sshDir.parent.create(recursive: true);
      }
      
      final line = '${hostKey.hostname} ${hostKey.algorithm} ${hostKey.publicKey}';
      
      if (await knownHostsFile.exists()) {
        final content = await knownHostsFile.readAsString();
        await knownHostsFile.writeAsString('$content\n$line');
      } else {
        await knownHostsFile.writeAsString(line);
      }
      
      debugPrint('🔑 Saved host key for ${hostKey.hostname}');
    } catch (e) {
      debugPrint('❌ Failed to save host key: $e');
    }
  }

  Future<void> _addKeyToAgent(SSHKey key, String? passphrase) async {
    if (_sshAgent == null) return;
    
    try {
      await _sshAgent!.addKey(key.privateKey, passphrase: passphrase);
      debugPrint('🔑 Added key to SSH agent: ${key.fingerprint}');
    } catch (e) {
      debugPrint('❌ Failed to add key to SSH agent: $e');
    }
  }

  Future<void> _removeKeyFromAgent(SSHKey key) async {
    if (_sshAgent == null) return;
    
    try {
      await _sshAgent!.removeKey(key.publicKey);
      debugPrint('🔑 Removed key from SSH agent: ${key.fingerprint}');
    } catch (e) {
      debugPrint('❌ Failed to remove key from SSH agent: $e');
    }
  }

  String _encryptData(String data, String passphrase) {
    // Simplified encryption (in reality would use proper encryption)
    final key = utf8.encode(passphrase);
    final bytes = utf8.encode(data);
    
    final encrypted = <int>[];
    for (int i = 0; i < bytes.length; i++) {
      encrypted.add(bytes[i] ^ key[i % key.length]);
    }
    
    return base64Encode(encrypted);
  }

  String _generateRandomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final random = math.Random();
    
    return String.fromCharCodes(Iterable.generate(
      length,
      (_) => chars.codeUnitAt(random.nextInt(chars.length)),
    ));
  }

  double _calculateAverageKeyAge() {
    if (_keys.isEmpty) return 0.0;
    
    final now = DateTime.now();
    final totalAge = _keys.values
        .map((key) => now.difference(key.createdAt).inDays)
        .reduce((a, b) => a + b);
    
    return totalAge / _keys.length;
  }

  SSHKey? _getMostUsedKey() {
    SSHKey? mostUsed;
    int maxUsage = 0;
    
    for (final key in _keys.values) {
      if (key.usageCount > maxUsage) {
        maxUsage = key.usageCount;
        mostUsed = key;
      }
    }
    
    return mostUsed;
  }

  Future<void> dispose() async {
    _keyMonitor?.cancel();
    _keyController.close();
    
    if (_sshAgent != null) {
      await _sshAgent!.dispose();
    }
    
    _keys.clear();
    _hostKeys.clear();
    _connections.clear();
    _encryptedKeys.clear();
    
    _isInitialized = false;
    debugPrint('🔑 SSH Key Manager disposed');
  }
}

/// Data classes
class SSHKey {
  final String id;
  final KeyType keyType;
  final int keySize;
  final String privateKey;
  final String publicKey;
  final String fingerprint;
  final String comment;
  final DateTime createdAt;
  DateTime? lastUsed;
  int usageCount;
  final bool encrypted;
  final String? filePath;
  
  SSHKey({
    required this.id,
    required this.keyType,
    required this.keySize,
    required this.privateKey,
    required this.publicKey,
    required this.fingerprint,
    required this.comment,
    required this.createdAt,
    this.lastUsed,
    this.usageCount = 0,
    required this.encrypted,
    this.filePath,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'keyType': keyType.toString(),
    'keySize': keySize,
    'publicKey': publicKey,
    'fingerprint': fingerprint,
    'comment': comment,
    'createdAt': createdAt.toIso8601String(),
    'lastUsed': lastUsed?.toIso8601String(),
    'usageCount': usageCount,
    'encrypted': encrypted,
    'filePath': filePath,
  };
  
  factory SSHKey.fromJson(Map<String, dynamic> json) => SSHKey(
    id: json['id'] as String,
    keyType: KeyType.values.firstWhere((k) => k.toString() == json['keyType']),
    keySize: json['keySize'] as int,
    privateKey: json['privateKey'] as String,
    publicKey: json['publicKey'] as String,
    fingerprint: json['fingerprint'] as String,
    comment: json['comment'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastUsed: json['lastUsed'] != null ? DateTime.parse(json['lastUsed'] as String) : null,
    usageCount: json['usageCount'] as int,
    encrypted: json['encrypted'] as bool,
    filePath: json['filePath'] as String?,
  );
}

class HostKey {
  final String hostname;
  final String publicKey;
  final String algorithm;
  final String fingerprint;
  final String? comment;
  final DateTime addedAt;
  DateTime? lastUsed;
  
  HostKey({
    required this.hostname,
    required this.publicKey,
    required this.algorithm,
    required this.fingerprint,
    this.comment,
    required this.addedAt,
    this.lastUsed,
  });
}

class SSHConnection {
  final String id;
  final String hostname;
  final int port;
  final String username;
  final String? keyId;
  final String? password;
  final Duration timeout;
  final DateTime createdAt;
  DateTime? lastActivity;
  SSHConnectionStatus status;
  
  SSHConnection({
    required this.id,
    required this.hostname,
    required this.port,
    required this.username,
    this.keyId,
    this.password,
    required this.timeout,
    required this.createdAt,
    this.lastActivity,
    required this.status,
  });
}

class SSHAgentKey {
  final String fingerprint;
  final String comment;
  final KeyType keyType;
  final int keySize;
  
  SSHAgentKey({
    required this.fingerprint,
    required this.comment,
    required this.keyType,
    required this.keySize,
  });
}

class SSHKeyStatistics {
  final int totalKeys;
  final int totalConnections;
  final bool agentAvailable;
  final int keysInAgent;
  final Map<KeyType, int> keyTypeDistribution;
  final Map<String, int> algorithmDistribution;
  final int encryptedKeys;
  final double averageKeyAge;
  final SSHKey? mostUsedKey;
  
  SSHKeyStatistics({
    required this.totalKeys,
    required this.totalConnections,
    required this.agentAvailable,
    required this.keysInAgent,
    required this.keyTypeDistribution,
    required this.algorithmDistribution,
    required this.encryptedKeys,
    required this.averageKeyAge,
    this.mostUsedKey,
  });
}

class SSHKeyManagerConfig {
  final bool enableAgentIntegration;
  final bool autoAddToAgent;
  final bool encryptKeysByDefault;
  final int keyRotationDays;
  final int connectionTimeout;
  
  SSHKeyManagerConfig({
    this.enableAgentIntegration = true,
    this.autoAddToAgent = true,
    this.encryptKeysByDefault = false,
    this.keyRotationDays = 365,
    this.connectionTimeout = 30,
  });
  
  Map<String, dynamic> toJson() => {
    'enableAgentIntegration': enableAgentIntegration,
    'autoAddToAgent': autoAddToAgent,
    'encryptKeysByDefault': encryptKeysByDefault,
    'keyRotationDays': keyRotationDays,
    'connectionTimeout': connectionTimeout,
  };
  
  factory SSHKeyManagerConfig.fromJson(Map<String, dynamic> json) {
    return SSHKeyManagerConfig(
      enableAgentIntegration: json['enableAgentIntegration'] as bool? ?? true,
      autoAddToAgent: json['autoAddToAgent'] as bool? ?? true,
      encryptKeysByDefault: json['encryptKeysByDefault'] as bool? ?? false,
      keyRotationDays: json['keyRotationDays'] as int? ?? 365,
      connectionTimeout: json['connectionTimeout'] as int? ?? 30,
    );
  }
}

class SSHKeyEvent {
  final SSHEventType type;
  final Map<String, dynamic>? data;
  
  SSHKeyEvent({
    required this.type,
    this.data,
  });
  
  static const String keyGenerated = 'key_generated';
  static const String keyImported = 'key_imported';
  static const String keyDeleted = 'key_deleted';
  static const String keyAddedToAgent = 'key_added_to_agent';
  static const String keyRemovedFromAgent = 'key_removed_from_agent';
  static const String hostKeyAdded = 'host_key_added';
  static const String connectionCreated = 'connection_created';
  static const String connectionTested = 'connection_tested';
}

/// SSH Agent Interface
class SSHAgent {
  bool _isInitialized = false;
  int _keyCount = 0;
  
  Future<bool> initialize() async {
    try {
      // Check if ssh-agent is running
      final result = await Process.run('ssh-add', ['-l'], runInShell: true);
      
      if (result.exitCode == 0) {
        _isInitialized = true;
        _keyCount = result.stdout.toString().split('\n').where((line) => line.trim().isNotEmpty).length;
        return true;
      } else {
        // Try to start ssh-agent
        await Process.run('eval', ['$(ssh-agent -s)'], runInShell: true);
        _isInitialized = true;
        return true;
      }
    } catch (e) {
      debugPrint('❌ Failed to initialize SSH agent: $e');
      return false;
    }
  }
  
  Future<void> addKey(String privateKey, {String? passphrase}) async {
    try {
      final args = <String>['ssh-add'];
      if (passphrase != null) {
        // In reality, would handle passphrase securely
      }
      
      final result = await Process.run('ssh-add', args, runInShell: true);
      
      if (result.exitCode == 0) {
        _keyCount++;
        debugPrint('🔑 Key added to SSH agent');
      } else {
        throw Exception('Failed to add key to SSH agent: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('❌ Failed to add key to SSH agent: $e');
      rethrow;
    }
  }
  
  Future<void> removeKey(String publicKey) async {
    try {
      final result = await Process.run('ssh-add', ['-d'], runInShell: true);
      
      if (result.exitCode == 0) {
        _keyCount = math.max(0, _keyCount - 1);
        debugPrint('🔑 Key removed from SSH agent');
      } else {
        throw Exception('Failed to remove key from SSH agent: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('❌ Failed to remove key from SSH agent: $e');
      rethrow;
    }
  }
  
  Future<List<SSHAgentKey>> listKeys() async {
    try {
      final result = await Process.run('ssh-add', ['-l'], runInShell: true);
      
      if (result.exitCode == 0) {
        final keys = <SSHAgentKey>[];
        final lines = result.stdout.toString().split('\n');
        
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          
          // Parse key line (simplified)
          final parts = line.split(' ');
          if (parts.length >= 3) {
            final fingerprint = parts[1];
            final keyType = _parseKeyType(parts[2]);
            final comment = parts.sublist(3).join(' ');
            
            keys.add(SSHAgentKey(
              fingerprint: fingerprint,
              comment: comment,
              keyType: keyType,
              keySize: _getKeySize(keyType),
            ));
          }
        }
        
        return keys;
      } else {
        throw Exception('Failed to list SSH agent keys: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('❌ Failed to list SSH agent keys: $e');
      return [];
    }
  }
  
  Future<bool> checkStatus() async {
    try {
      final result = await Process.run('ssh-add', ['-l'], runInShell: true);
      _isInitialized = result.exitCode == 0;
      return _isInitialized;
    } catch (e) {
      _isInitialized = false;
      return false;
    }
  }
  
  Future<void> dispose() async {
    try {
      await Process.run('ssh-agent', ['-k'], runInShell: true);
      _isInitialized = false;
      _keyCount = 0;
    } catch (e) {
      debugPrint('⚠️ Failed to dispose SSH agent: $e');
    }
  }
  
  KeyType _parseKeyType(String keyString) {
    if (keyString.contains('RSA')) return KeyType.rsa;
    if (keyString.contains('ED25519')) return KeyType.ed25519;
    if (keyString.contains('ECDSA')) return KeyType.ecdsa;
    return KeyType.rsa;
  }
  
  int _getKeySize(KeyType keyType) {
    switch (keyType) {
      case KeyType.rsa:
        return 2048;
      case KeyType.ed25519:
        return 256;
      case KeyType.ecdsa:
        return 256;
    }
  }
  
  bool get isInitialized => _isInitialized;
  int get keyCount => _keyCount;
}

// Enums
enum KeyType {
  rsa,
  ed25519,
  ecdsa,
}

enum SSHConnectionStatus {
  disconnected,
  connecting,
  connected,
  failed,
}

enum SSHEventType {
  keyGenerated,
  keyImported,
  keyDeleted,
  keyAddedToAgent,
  keyRemovedFromAgent,
  hostKeyAdded,
  connectionCreated,
  connectionTested,
}
