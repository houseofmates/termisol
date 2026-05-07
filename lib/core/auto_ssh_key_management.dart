import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

class AutoSSHKeyManagement {
  static const String _defaultKeyPath = '/home/house/.ssh/hermes_key';
  static const String _publicKeyPath = '/home/house/.ssh/hermes_key.pub';
  static const String _configPath = '/home/house/.ssh/config';
  static const String _knownHostsPath = '/home/house/.ssh/known_hosts';
  static const String _keyDataFile = '/home/house/.termisol_ssh_keys.json';
  
  final Map<String, SSHKey> _keys = {};
  final Map<String, KeyUsage> _keyUsage = {};
  final List<KeyRotation> _rotations = [];
  final Map<String, HostKey> _hostKeys = {};
  
  Timer? _keyCheckTimer;
  Timer? _rotationTimer;
  Timer? _cleanupTimer;
  
  int _totalKeys = 0;
  int _totalRotations = 0;
  int _totalAuthentications = 0;
  
  final StreamController<KeyEvent> _keyController = 
      StreamController<KeyEvent>.broadcast();

  void initialize() {
    _ensureSSHDirectory();
    _loadKeys();
    _loadKeyUsage();
    _loadHostKeys();
    _startTimers();
    developer.log('🔑 Auto SSH Key Management initialized');
  }

  void _ensureSSHDirectory() {
    final sshDir = Directory('/home/house/.ssh');
    if (!sshDir.existsSync()) {
      sshDir.createSync(recursive: true);
      sshDir.setPermissionsSync(0o700);
    }
  }

  void _loadKeys() {
    try {
      final file = File(_keyDataFile);
      if (!file.existsSync()) {
        // Try to load default key
        _loadDefaultKey();
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['keys']) {
        final key = SSHKey.fromJson(entry);
        _keys[key.id] = key;
        _totalKeys++;
      }
      
      // Load rotations
      for (final entry in data['rotations'] ?? []) {
        final rotation = KeyRotation.fromJson(entry);
        _rotations.add(rotation);
        _totalRotations++;
      }
      
      developer.log('🔑 Loaded ${_keys.length} SSH keys');
      
    } catch (e) {
      developer.log('🔑 Failed to load keys: $e');
      _loadDefaultKey();
    }
  }

  void _loadDefaultKey() {
    final keyFile = File(_defaultKeyPath);
    final publicKeyFile = File(_publicKeyPath);
    
    if (keyFile.existsSync() && publicKeyFile.existsSync()) {
      try {
        final privateKey = keyFile.readAsStringSync();
        final publicKey = publicKeyFile.readAsStringSync();
        
        final key = SSHKey(
          id: 'hermes_default',
          name: 'Hermes Default Key',
          privateKeyPath: _defaultKeyPath,
          publicKeyPath: _publicKeyPath,
          privateKey: privateKey,
          publicKey: publicKey,
          keyType: _detectKeyType(publicKey),
          keySize: _detectKeySize(publicKey),
          fingerprint: _generateFingerprint(publicKey),
          createdAt: keyFile.statSync().modified,
          lastUsed: null,
          usageCount: 0,
          isActive: true,
          autoRotate: false,
          rotationInterval: Duration(days: 90),
          permissions: ['ssh', 'git', 'scp', 'rsync'],
        );
        
        _keys[key.id] = key;
        _totalKeys++;
        
        developer.log('🔑 Loaded default SSH key');
        
        _emitEvent(KeyEvent(
          type: KeyEventType.keyLoaded,
          keyId: key.id,
          keyName: key.name,
        ));
        
      } catch (e) {
        developer.log('🔑 Failed to load default key: $e');
      }
    }
  }

  void _loadKeyUsage() {
    try {
      final usageFile = File('${_keyDataFile}.usage');
      if (!usageFile.existsSync()) return;
      
      final content = usageFile.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['usage']) {
        final usage = KeyUsage.fromJson(entry);
        _keyUsage[usage.keyId] = usage;
      }
      
      developer.log('🔑 Loaded key usage data');
      
    } catch (e) {
      developer.log('🔑 Failed to load key usage: $e');
    }
  }

  void _loadHostKeys() {
    try {
      final knownHostsFile = File(_knownHostsPath);
      if (!knownHostsFile.existsSync()) return;
      
      final lines = knownHostsFile.readAsLinesSync();
      
      for (final line in lines) {
        if (line.startsWith('#') || line.trim().isEmpty) continue;
        
        final parts = line.split(' ');
        if (parts.length >= 3) {
          final hostKey = HostKey(
            host: parts[0],
            keyType: parts[1],
            keyData: parts.sublist(2).join(' '),
            addedAt: knownHostsFile.statSync().modified,
            lastUsed: null,
          );
          
          _hostKeys[hostKey.host] = hostKey;
        }
      }
      
      developer.log('🔑 Loaded ${_hostKeys.length} host keys');
      
    } catch (e) {
      developer.log('🔑 Failed to load host keys: $e');
    }
  }

  void _startTimers() {
    _keyCheckTimer = Timer.periodic(
      Duration(minutes: 10),
      (_) => _checkKeyHealth(),
    );
    
    _rotationTimer = Timer.periodic(
      Duration(hours: 6),
      (_) => _checkRotations(),
    );
    
    _cleanupTimer = Timer.periodic(
      Duration(hours: 24),
      (_) => _cleanupOldKeys(),
    );
  }

  Future<String> generateKey({
    required String name,
    String? keyType,
    int? keySize,
    String? comment,
    bool? autoRotate,
    Duration? rotationInterval,
    List<String>? permissions,
  }) async {
    final keyId = _generateKeyId();
    
    final privateKeyPath = '/home/house/.ssh/${name.toLowerCase().replaceAll(' ', '_')}_key';
    final publicKeyPath = '$privateKeyPath.pub';
    
    try {
      // Generate SSH key
      final type = keyType ?? 'ed25519';
      final size = keySize ?? (type == 'rsa' ? 4096 : null);
      
      final args = ['ssh-keygen', '-t', type];
      if (size != null) args.addAll(['-b', size.toString()]);
      args.addAll(['-f', privateKeyPath, '-N', '']);
      
      if (comment != null) args.addAll(['-C', comment]);
      
      final process = await Process.start('ssh-keygen', args);
      final exitCode = await process.exitCode;
      
      if (exitCode != 0) {
        throw Exception('SSH key generation failed with exit code $exitCode');
      }
      
      // Read generated keys
      final privateKey = await File(privateKeyPath).readAsString();
      final publicKey = await File(publicKeyPath).readAsString();
      
      final key = SSHKey(
        id: keyId,
        name: name,
        privateKeyPath: privateKeyPath,
        publicKeyPath: publicKeyPath,
        privateKey: privateKey,
        publicKey: publicKey,
        keyType: type,
        keySize: size ?? 256,
        fingerprint: _generateFingerprint(publicKey),
        createdAt: DateTime.now(),
        lastUsed: null,
        usageCount: 0,
        isActive: true,
        autoRotate: autoRotate ?? false,
        rotationInterval: rotationInterval ?? Duration(days: 90),
        permissions: permissions ?? ['ssh', 'git', 'scp', 'rsync'],
        comment: comment,
      );
      
      _keys[keyId] = key;
      _totalKeys++;
      
      // Set proper permissions
      await File(privateKeyPath).setPermissions(0o600);
      await File(publicKeyPath).setPermissions(0o644);
      
      developer.log('🔑 Generated SSH key: $name ($type)');
      
      _emitEvent(KeyEvent(
        type: KeyEventType.keyGenerated,
        keyId: keyId,
        keyName: name,
        keyType: type,
        keySize: size,
      ));
      
      // Save keys
      await _saveKeys();
      
      return keyId;
      
    } catch (e) {
      developer.log('🔑 Failed to generate SSH key: $e');
      
      _emitEvent(KeyEvent(
        type: KeyEventType.keyGenerationFailed,
        keyId: keyId,
        keyName: name,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> deployKey({
    required String keyId,
    required String host,
    String? username,
    int? port,
  }) async {
    final key = _keys[keyId];
    if (key == null) {
      throw Exception('SSH key not found: $keyId');
    }
    
    final user = username ?? 'house';
    final sshPort = port ?? 22;
    
    try {
      developer.log('🔑 Deploying SSH key to $user@$host:$sshPort');
      
      // Copy public key to remote host
      final args = [
        'ssh-copy-id',
        '-i', key.publicKeyPath,
        '-p', sshPort.toString(),
        '$user@$host',
      ];
      
      final process = await Process.start('ssh-copy-id', args);
      final exitCode = await process.exitCode;
      
      if (exitCode != 0) {
        throw Exception('SSH key deployment failed with exit code $exitCode');
      }
      
      // Record deployment
      final deployment = KeyDeployment(
        keyId: keyId,
        host: host,
        username: user,
        port: sshPort,
        deployedAt: DateTime.now(),
        lastUsed: DateTime.now(),
        success: true,
      );
      
      // Update key usage
      final usage = _keyUsage[keyId] ?? KeyUsage(
        keyId: keyId,
        deployments: [],
        totalUsage: 0,
        lastUsed: null,
      );
      
      usage.deployments.add(deployment);
      usage.totalUsage++;
      usage.lastUsed = DateTime.now();
      
      _keyUsage[keyId] = usage;
      
      // Update key
      key.lastUsed = DateTime.now();
      key.usageCount++;
      
      developer.log('🔑 SSH key deployed successfully: $keyId -> $host');
      
      _emitEvent(KeyEvent(
        type: KeyEventType.keyDeployed,
        keyId: keyId,
        host: host,
        username: user,
        port: sshPort,
      ));
      
      // Save usage data
      await _saveKeyUsage();
      
    } catch (e) {
      developer.log('🔑 Failed to deploy SSH key: $e');
      
      _emitEvent(KeyEvent(
        type: KeyEventType.keyDeploymentFailed,
        keyId: keyId,
        host: host,
        username: user,
        port: sshPort,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> rotateKey(String keyId) async {
    final oldKey = _keys[keyId];
    if (oldKey == null) {
      throw Exception('SSH key not found: $keyId');
    }
    
    try {
      developer.log('🔑 Rotating SSH key: $keyId');
      
      // Generate new key
      final newKeyId = await generateKey(
        name: '${oldKey.name} (Rotated)',
        keyType: oldKey.keyType,
        keySize: oldKey.keySize,
        comment: 'Rotated from ${oldKey.name}',
        autoRotate: oldKey.autoRotate,
        rotationInterval: oldKey.rotationInterval,
        permissions: oldKey.permissions,
      );
      
      final newKey = _keys[newKeyId]!;
      
      // Deploy new key to all hosts where old key was deployed
      final usage = _keyUsage[keyId];
      if (usage != null) {
        for (final deployment in usage.deployments) {
          if (deployment.success) {
            await deployKey(
              keyId: newKeyId,
              host: deployment.host,
              username: deployment.username,
              port: deployment.port,
            );
          }
        }
      }
      
      // Deactivate old key
      oldKey.isActive = false;
      oldKey.deactivatedAt = DateTime.now();
      
      // Create rotation record
      final rotation = KeyRotation(
        id: _generateRotationId(),
        oldKeyId: keyId,
        newKeyId: newKeyId,
        rotatedAt: DateTime.now(),
        reason: 'Scheduled rotation',
        deploymentsMigrated: usage?.deployments.length ?? 0,
      );
      
      _rotations.add(rotation);
      _totalRotations++;
      
      developer.log('🔑 SSH key rotated successfully: $keyId -> $newKeyId');
      
      _emitEvent(KeyEvent(
        type: KeyEventType.keyRotated,
        keyId: keyId,
        newKeyId: newKeyId,
        deploymentsMigrated: usage?.deployments.length ?? 0,
      ));
      
      // Save data
      await _saveKeys();
      await _saveKeyUsage();
      
    } catch (e) {
      developer.log('🔑 Failed to rotate SSH key: $e');
      
      _emitEvent(KeyEvent(
        type: KeyEventType.keyRotationFailed,
        keyId: keyId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> revokeKey(String keyId) async {
    final key = _keys[keyId];
    if (key == null) {
      throw Exception('SSH key not found: $keyId');
    }
    
    try {
      developer.log('🔑 Revoking SSH key: $keyId');
      
      // Remove key from all hosts
      final usage = _keyUsage[keyId];
      if (usage != null) {
        for (final deployment in usage.deployments) {
          await _removeKeyFromHost(deployment);
        }
      }
      
      // Delete key files
      await File(key.privateKeyPath).delete();
      await File(key.publicKeyPath).delete();
      
      // Mark key as revoked
      key.isActive = false;
      key.revokedAt = DateTime.now();
      
      developer.log('🔑 SSH key revoked successfully: $keyId');
      
      _emitEvent(KeyEvent(
        type: KeyEventType.keyRevoked,
        keyId: keyId,
        deploymentsRemoved: usage?.deployments.length ?? 0,
      ));
      
      // Save data
      await _saveKeys();
      
    } catch (e) {
      developer.log('🔑 Failed to revoke SSH key: $e');
      
      _emitEvent(KeyEvent(
        type: KeyEventType.keyRevocationFailed,
        keyId: keyId,
        error: e.toString(),
      ));
      
      rethrow;
    }
  }

  Future<void> _removeKeyFromHost(KeyDeployment deployment) async {
    try {
      // Remove authorized_keys entry
      final args = [
        'ssh',
        '-p', deployment.port.toString(),
        '${deployment.username}@${deployment.host}',
        'sed -i "/$(ssh-keygen -lf ${deployment.keyId})/d" ~/.ssh/authorized_keys',
      ];
      
      final process = await Process.start('ssh', args);
      final exitCode = await process.exitCode;
      
      if (exitCode != 0) {
        developer.log('🔑 Failed to remove key from host ${deployment.host}: exit code $exitCode');
      }
      
    } catch (e) {
      developer.log('🔑 Failed to remove key from host ${deployment.host}: $e');
    }
  }

  Future<bool> testKey({
    required String keyId,
    required String host,
    String? username,
    int? port,
  }) async {
    final key = _keys[keyId];
    if (key == null) {
      throw Exception('SSH key not found: $keyId');
    }
    
    final user = username ?? 'house';
    final sshPort = port ?? 22;
    
    try {
      developer.log('🔑 Testing SSH key: $keyId -> $user@$host:$sshPort');
      
      final args = [
        'ssh',
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=10',
        '-i', key.privateKeyPath,
        '-p', sshPort.toString(),
        '$user@$host',
        'echo "key_test_success"',
      ];
      
      final process = await Process.start('ssh', args);
      final exitCode = await process.exitCode;
      
      final success = exitCode == 0;
      
      if (success) {
        // Update usage
        final usage = _keyUsage[keyId] ?? KeyUsage(
          keyId: keyId,
          deployments: [],
          totalUsage: 0,
          lastUsed: null,
        );
        
        usage.totalUsage++;
        usage.lastUsed = DateTime.now();
        
        _keyUsage[keyId] = usage;
        _totalAuthentications++;
        
        developer.log('🔑 SSH key test successful: $keyId');
      } else {
        developer.log('🔑 SSH key test failed: $keyId');
      }
      
      _emitEvent(KeyEvent(
        type: KeyEventType.keyTested,
        keyId: keyId,
        host: host,
        username: user,
        port: sshPort,
        success: success,
      ));
      
      return success;
      
    } catch (e) {
      developer.log('🔑 SSH key test error: $e');
      
      _emitEvent(KeyEvent(
        type: KeyEventType.keyTestFailed,
        keyId: keyId,
        host: host,
        error: e.toString(),
      ));
      
      return false;
    }
  }

  void _checkKeyHealth() {
    for (final key in _keys.values) {
      if (!key.isActive) continue;
      
      // Check key file permissions
      try {
        final privateKeyFile = File(key.privateKeyPath);
        final stat = privateKeyFile.statSync();
        final permissions = stat.mode;
        
        if ((permissions & 0o777) != 0o600) {
          developer.log('🔑 Key permissions incorrect for ${key.id}: ${permissions.toRadixString(8)}');
          
          _emitEvent(KeyEvent(
            type: KeyEventType.keyHealthIssue,
            keyId: key.id,
            issue: 'Incorrect file permissions',
            severity: 'warning',
          ));
        }
      } catch (e) {
        developer.log('🔑 Failed to check key permissions for ${key.id}: $e');
        
        _emitEvent(KeyEvent(
          type: KeyEventType.keyHealthIssue,
          keyId: key.id,
          issue: 'Cannot access key file',
          severity: 'error',
        ));
      }
      
      // Check key age
      final keyAge = DateTime.now().difference(key.createdAt);
      if (keyAge.inDays > 365) {
        developer.log('🔑 Key is old: ${key.id} (${keyAge.inDays} days)');
        
        _emitEvent(KeyEvent(
          type: KeyEventType.keyHealthIssue,
          keyId: key.id,
          issue: 'Key is very old',
          severity: 'warning',
        ));
      }
    }
  }

  void _checkRotations() {
    for (final key in _keys.values) {
      if (!key.isActive || !key.autoRotate) continue;
      
      final timeSinceRotation = DateTime.now().difference(key.createdAt);
      if (timeSinceRotation >= key.rotationInterval) {
        developer.log('🔑 Scheduling rotation for key: ${key.id}');
        
        _emitEvent(KeyEvent(
          type: KeyEventType.rotationScheduled,
          keyId: key.id,
          rotationDate: DateTime.now().add(key.rotationInterval),
        ));
        
        // Schedule rotation
        Timer(Duration.zero, () => rotateKey(key.id));
      }
    }
  }

  void _cleanupOldKeys() {
    final now = DateTime.now();
    final keysToRemove = <String>[];
    
    for (final entry in _keys.entries) {
      final key = entry.value;
      
      bool shouldRemove = false;
      String reason = '';
      
      // Remove revoked keys older than 30 days
      if (!key.isActive && 
          key.revokedAt != null &&
          now.difference(key.revokedAt!).inDays > 30) {
        shouldRemove = true;
        reason = 'Revoked for > 30 days';
      }
      
      // Remove inactive keys never used
      if (key.isActive && 
          key.usageCount == 0 &&
          now.difference(key.createdAt).inDays > 90) {
        shouldRemove = true;
        reason = 'Never used and > 90 days old';
      }
      
      if (shouldRemove) {
        keysToRemove.add(entry.key);
        developer.log('🔑 Cleaning up key ${key.id}: $reason');
      }
    }
    
    // Remove old keys
    for (final keyId in keysToRemove) {
      final key = _keys.remove(keyId);
      if (key != null) {
        // Delete key files
        try {
          File(key.privateKeyPath).delete();
          File(key.publicKeyPath).delete();
        } catch (e) {
          developer.log('🔑 Failed to delete key files for $keyId: $e');
        }
        
        _keyUsage.remove(keyId);
      }
    }
    
    if (keysToRemove.isNotEmpty) {
      _saveKeys();
      _saveKeyUsage();
      
      _emitEvent(KeyEvent(
        type: KeyEventType.keysCleaned,
        keyIds: keysToRemove,
      ));
    }
  }

  Future<void> _saveKeys() async {
    try {
      final file = File(_keyDataFile);
      
      final keysData = _keys.values.map((key) => key.toJson()).toList();
      final rotationsData = _rotations.map((rotation) => rotation.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'keys': keysData,
        'rotations': rotationsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
      developer.log('🔑 Saved ${_keys.length} SSH keys');
      
    } catch (e) {
      developer.log('🔑 Failed to save keys: $e');
    }
  }

  Future<void> _saveKeyUsage() async {
    try {
      final file = File('${_keyDataFile}.usage');
      
      final usageData = _keyUsage.values.map((usage) => usage.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'usage': usageData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
      developer.log('🔑 Saved key usage data');
      
    } catch (e) {
      developer.log('🔑 Failed to save key usage: $e');
    }
  }

  SSHKey? getKey(String keyId) {
    return _keys[keyId];
  }

  List<SSHKey> getKeys() {
    return _keys.values.toList();
  }

  List<SSHKey> getActiveKeys() {
    return _keys.values
        .where((key) => key.isActive)
        .toList();
  }

  KeyUsage? getKeyUsage(String keyId) {
    return _keyUsage[keyId];
  }

  List<KeyRotation> getRotations() {
    return _rotations.toList();
  }

  HostKey? getHostKey(String host) {
    return _hostKeys[host];
  }

  Future<String> getPublicKey(String keyId) async {
    final key = _keys[keyId];
    if (key == null) {
      throw Exception('SSH key not found: $keyId');
    }
    
    return key.publicKey;
  }

  Future<String> getFingerprint(String keyId) async {
    final key = _keys[keyId];
    if (key == null) {
      throw Exception('SSH key not found: $keyId');
    }
    
    return key.fingerprint;
  }

  String _detectKeyType(String publicKey) {
    if (publicKey.startsWith('ssh-ed25519')) {
      return 'ed25519';
    } else if (publicKey.startsWith('ssh-rsa')) {
      return 'rsa';
    } else if (publicKey.startsWith('ssh-dss')) {
      return 'dss';
    } else if (publicKey.startsWith('ecdsa-sha2-')) {
      return 'ecdsa';
    } else {
      return 'unknown';
    }
  }

  int _detectKeySize(String publicKey) {
    if (publicKey.startsWith('ssh-ed25519')) {
      return 256;
    } else if (publicKey.startsWith('ssh-rsa')) {
      // Extract key size from RSA key
      final match = RegExp(r'ssh-rsa\s+(\w+)').firstMatch(publicKey);
      if (match != null) {
        return (match.group(1)!.length * 6); // Approximate
      }
      return 2048;
    } else if (publicKey.startsWith('ssh-dss')) {
      return 1024;
    } else if (publicKey.startsWith('ecdsa-sha2-')) {
      return 256;
    } else {
      return 0;
    }
  }

  String _generateFingerprint(String publicKey) {
    // Simple fingerprint generation
    // In practice, this would use ssh-keygen -lf
    final bytes = utf8.encode(publicKey);
    final digest = md5.convert(bytes);
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }

  String _generateKeyId() {
    return 'key_${DateTime.now().millisecondsSinceEpoch}_$_totalKeys';
  }

  String _generateRotationId() {
    return 'rotation_${DateTime.now().millisecondsSinceEpoch}_$_totalRotations';
  }

  void _emitEvent(KeyEvent event) {
    _keyController.add(event);
  }

  Stream<KeyEvent> get keyEventStream => _keyController.stream;

  KeyManagementStats getStats() {
    return KeyManagementStats(
      totalKeys: _totalKeys,
      activeKeys: _keys.values
          .where((key) => key.isActive)
          .length,
      totalRotations: _totalRotations,
      totalAuthentications: _totalAuthentications,
      totalDeployments: _keyUsage.values
          .fold(0, (sum, usage) => sum + usage.deployments.length),
      averageKeyAge: _calculateAverageKeyAge(),
    );
  }

  double _calculateAverageKeyAge() {
    if (_keys.isEmpty) return 0.0;
    
    final totalAge = _keys.values
        .map((key) => DateTime.now().difference(key.createdAt).inDays)
        .fold(0, (sum, age) => sum + age);
    
    return totalAge / _keys.length;
  }

  void dispose() {
    _keyCheckTimer?.cancel();
    _rotationTimer?.cancel();
    _cleanupTimer?.cancel();
    
    _keys.clear();
    _keyUsage.clear();
    _rotations.clear();
    _hostKeys.clear();
    _keyController.close();
    
    developer.log('🔑 Auto SSH Key Management disposed');
  }
}

// MD5 hash implementation for fingerprint generation
import 'dart:typed_data';

class MD5 {
  static Hash convert(List<int> input) {
    // Simple MD5 implementation
    // In practice, this would use crypto package
    final digest = _simpleHash(input);
    return Hash(digest);
  }
  
  static List<int> _simpleHash(List<int> input) {
    // Very simple hash for demonstration
    int hash = 0;
    for (final byte in input) {
      hash = ((hash << 5) - hash + byte) & 0xFFFFFFFF;
    }
    
    final result = <int>[];
    for (int i = 0; i < 16; i++) {
      result.add((hash >> (i * 8)) & 0xFF);
    }
    
    return result;
  }
}

class Hash {
  final List<int> bytes;
  
  Hash(this.bytes);
}

class SSHKey {
  final String id;
  final String name;
  final String privateKeyPath;
  final String publicKeyPath;
  final String privateKey;
  final String publicKey;
  final String keyType;
  final int keySize;
  final String fingerprint;
  final DateTime createdAt;
  DateTime? lastUsed;
  int usageCount;
  bool isActive;
  bool autoRotate;
  Duration rotationInterval;
  final List<String> permissions;
  final String? comment;
  DateTime? deactivatedAt;
  DateTime? revokedAt;

  SSHKey({
    required this.id,
    required this.name,
    required this.privateKeyPath,
    required this.publicKeyPath,
    required this.privateKey,
    required this.publicKey,
    required this.keyType,
    required this.keySize,
    required this.fingerprint,
    required this.createdAt,
    this.lastUsed,
    required this.usageCount,
    required this.isActive,
    required this.autoRotate,
    required this.rotationInterval,
    required this.permissions,
    this.comment,
    this.deactivatedAt,
    this.revokedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'private_key_path': privateKeyPath,
      'public_key_path': publicKeyPath,
      'key_type': keyType,
      'key_size': keySize,
      'fingerprint': fingerprint,
      'created_at': createdAt.toIso8601String(),
      'last_used': lastUsed?.toIso8601String(),
      'usage_count': usageCount,
      'is_active': isActive,
      'auto_rotate': autoRotate,
      'rotation_interval': rotationInterval.inMilliseconds,
      'permissions': permissions,
      'comment': comment,
      'deactivated_at': deactivatedAt?.toIso8601String(),
      'revoked_at': revokedAt?.toIso8601String(),
    };
  }

  factory SSHKey.fromJson(Map<String, dynamic> json) {
    return SSHKey(
      id: json['id'],
      name: json['name'],
      privateKeyPath: json['private_key_path'],
      publicKeyPath: json['public_key_path'],
      privateKey: '', // Not stored in JSON for security
      publicKey: '', // Not stored in JSON for security
      keyType: json['key_type'],
      keySize: json['key_size'],
      fingerprint: json['fingerprint'],
      createdAt: DateTime.parse(json['created_at']),
      lastUsed: json['last_used'] != null ? DateTime.parse(json['last_used']) : null,
      usageCount: json['usage_count'] ?? 0,
      isActive: json['is_active'] ?? true,
      autoRotate: json['auto_rotate'] ?? false,
      rotationInterval: Duration(milliseconds: json['rotation_interval'] ?? Duration(days: 90).inMilliseconds),
      permissions: List<String>.from(json['permissions'] ?? ['ssh', 'git', 'scp', 'rsync']),
      comment: json['comment'],
      deactivatedAt: json['deactivated_at'] != null ? DateTime.parse(json['deactivated_at']) : null,
      revokedAt: json['revoked_at'] != null ? DateTime.parse(json['revoked_at']) : null,
    );
  }
}

class KeyUsage {
  final String keyId;
  final List<KeyDeployment> deployments;
  final int totalUsage;
  DateTime? lastUsed;

  KeyUsage({
    required this.keyId,
    required this.deployments,
    required this.totalUsage,
    required this.lastUsed,
  });

  Map<String, dynamic> toJson() {
    return {
      'key_id': keyId,
      'deployments': deployments.map((d) => d.toJson()).toList(),
      'total_usage': totalUsage,
      'last_used': lastUsed?.toIso8601String(),
    };
  }

  factory KeyUsage.fromJson(Map<String, dynamic> json) {
    return KeyUsage(
      keyId: json['key_id'],
      deployments: (json['deployments'] as List).map((d) => KeyDeployment.fromJson(d)).toList(),
      totalUsage: json['total_usage'] ?? 0,
      lastUsed: json['last_used'] != null ? DateTime.parse(json['last_used']) : null,
    );
  }
}

class KeyDeployment {
  final String keyId;
  final String host;
  final String username;
  final int port;
  final DateTime deployedAt;
  DateTime? lastUsed;
  final bool success;

  KeyDeployment({
    required this.keyId,
    required this.host,
    required this.username,
    required this.port,
    required this.deployedAt,
    this.lastUsed,
    required this.success,
  });

  Map<String, dynamic> toJson() {
    return {
      'key_id': keyId,
      'host': host,
      'username': username,
      'port': port,
      'deployed_at': deployedAt.toIso8601String(),
      'last_used': lastUsed?.toIso8601String(),
      'success': success,
    };
  }

  factory KeyDeployment.fromJson(Map<String, dynamic> json) {
    return KeyDeployment(
      keyId: json['key_id'],
      host: json['host'],
      username: json['username'],
      port: json['port'],
      deployedAt: DateTime.parse(json['deployed_at']),
      lastUsed: json['last_used'] != null ? DateTime.parse(json['last_used']) : null,
      success: json['success'] ?? true,
    );
  }
}

class KeyRotation {
  final String id;
  final String oldKeyId;
  final String newKeyId;
  final DateTime rotatedAt;
  final String reason;
  final int deploymentsMigrated;

  KeyRotation({
    required this.id,
    required this.oldKeyId,
    required this.newKeyId,
    required this.rotatedAt,
    required this.reason,
    required this.deploymentsMigrated,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'old_key_id': oldKeyId,
      'new_key_id': newKeyId,
      'rotated_at': rotatedAt.toIso8601String(),
      'reason': reason,
      'deployments_migrated': deploymentsMigrated,
    };
  }

  factory KeyRotation.fromJson(Map<String, dynamic> json) {
    return KeyRotation(
      id: json['id'],
      oldKeyId: json['old_key_id'],
      newKeyId: json['new_key_id'],
      rotatedAt: DateTime.parse(json['rotated_at']),
      reason: json['reason'],
      deploymentsMigrated: json['deployments_migrated'] ?? 0,
    );
  }
}

class HostKey {
  final String host;
  final String keyType;
  final String keyData;
  final DateTime addedAt;
  DateTime? lastUsed;

  HostKey({
    required this.host,
    required this.keyType,
    required this.keyData,
    required this.addedAt,
    this.lastUsed,
  });
}

enum KeyEventType {
  keyLoaded,
  keyGenerated,
  keyGenerationFailed,
  keyDeployed,
  keyDeploymentFailed,
  keyRotated,
  keyRotationFailed,
  keyRevoked,
  keyRevocationFailed,
  keyTested,
  keyTestFailed,
  keyHealthIssue,
  rotationScheduled,
  keysCleaned,
}

class KeyEvent {
  final KeyEventType type;
  final String? keyId;
  final String? keyName;
  final String? newKeyId;
  final String? host;
  final String? username;
  final int? port;
  final String? keyType;
  final int? keySize;
  final String? error;
  final bool? success;
  final int? deploymentsMigrated;
  final DateTime? rotationDate;
  final String? issue;
  final String? severity;
  final List<String>? keyIds;

  KeyEvent({
    required this.type,
    this.keyId,
    this.keyName,
    this.newKeyId,
    this.host,
    this.username,
    this.port,
    this.keyType,
    this.keySize,
    this.error,
    this.success,
    this.deploymentsMigrated,
    this.rotationDate,
    this.issue,
    this.severity,
    this.keyIds,
  });
}

class KeyManagementStats {
  final int totalKeys;
  final int activeKeys;
  final int totalRotations;
  final int totalAuthentications;
  final int totalDeployments;
  final double averageKeyAge;

  KeyManagementStats({
    required this.totalKeys,
    required this.activeKeys,
    required this.totalRotations,
    required this.totalAuthentications,
    required this.totalDeployments,
    required this.averageKeyAge,
  });
}
