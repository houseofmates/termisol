import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DatabaseClient {
  static const String _profilesFile = '/home/house/.termisol_db_profiles.json';
  static const String _historyFile = '/home/house/.termisol_db_history.json';
  static const int _maxHistory = 500;
  static const int _queryTimeout = 30000;

  final Map<String, DbProfile> _profiles = {};
  final List<DbHistoryEntry> _history = [];
  final Map<String, Process> _activeProcesses = {};

  String? _activeProfileId;
  bool _isInitialized = false;

  final StreamController<DbEvent> _eventController =
      StreamController<DbEvent>.broadcast();

  Stream<DbEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  DbProfile? get activeProfile =>
      _activeProfileId != null ? _profiles[_activeProfileId] : null;
  List<DbProfile> get profiles => _profiles.values.toList();
  List<DbHistoryEntry> get history => List.unmodifiable(_history);

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _loadProfiles();
    await _loadHistory();
    _isInitialized = true;
  }

  Future<void> _loadProfiles() async {
    try {
      final file = File(_profilesFile);
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as List;
      for (final item in data) {
        final profile = DbProfile.fromJson(item);
        _profiles[profile.id] = profile;
      }
    } catch (e) {
      debugLog('Failed to load DB profiles: $e');
    }
  }

  Future<void> _saveProfiles() async {
    final data = _profiles.values.map((p) => p.toJson()).toList();
    await File(_profilesFile).writeAsString(jsonEncode(data));
  }

  Future<void> _loadHistory() async {
    try {
      final file = File(_historyFile);
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as List;
      for (final item in data) {
        _history.add(DbHistoryEntry.fromJson(item));
      }
    } catch (e) {
      debugLog('Failed to load DB history: $e');
    }
  }

  Future<void> _saveHistory() async {
    final data = _history.map((h) => h.toJson()).toList();
    await File(_historyFile).writeAsString(jsonEncode(data));
  }

  Future<DbProfile> addProfile({
    required String name,
    required DbType type,
    String? host,
    int? port,
    String? database,
    String? username,
    String? password,
    String? filePath,
  }) async {
    final id = 'db_${DateTime.now().millisecondsSinceEpoch}';
    final profile = DbProfile(
      id: id,
      name: name,
      type: type,
      host: host ?? 'localhost',
      port: port ?? (type == DbType.postgresql ? 5432 : 0),
      database: database ?? name,
      username: username ?? 'postgres',
      password: password ?? '',
      filePath: filePath ?? '',
      createdAt: DateTime.now(),
    );
    _profiles[id] = profile;
    await _saveProfiles();

    _eventController.add(DbEvent(
      type: DbEventType.profileAdded,
      message: 'Profile "$name" added',
      profileId: id,
    ));
    return profile;
  }

  Future<void> removeProfile(String id) async {
    final removed = _profiles.remove(id);
    if (removed == null) return;
    if (_activeProfileId == id) _activeProfileId = null;
    await _saveProfiles();

    _eventController.add(DbEvent(
      type: DbEventType.profileRemoved,
      message: 'Profile "${removed.name}" removed',
      profileId: id,
    ));
  }

  Future<void> connect(String profileId) async {
    final profile = _profiles[profileId];
    if (profile == null) throw Exception('Profile not found: $profileId');

    if (profile.type == DbType.postgresql) {
      await _testPostgresConnection(profile);
    } else if (profile.type == DbType.sqlite) {
      await _testSqliteConnection(profile);
    }

    _activeProfileId = profileId;

    _eventController.add(DbEvent(
      type: DbEventType.connected,
      message: 'Connected to "${profile.name}"',
      profileId: profileId,
    ));
  }

  Future<void> disconnect() async {
    _activeProfileId = null;
    for (final process in _activeProcesses.values) {
      process.kill();
    }
    _activeProcesses.clear();

    _eventController.add(DbEvent(
      type: DbEventType.disconnected,
      message: 'Disconnected from database',
    ));
  }

  Future<DbQueryResult> executeQuery(String sql) async {
    final profile = activeProfile;
    if (profile == null) throw Exception('Not connected to any database');

    final startTime = DateTime.now();
    final entry = DbHistoryEntry(
      id: 'q_${startTime.millisecondsSinceEpoch}',
      sql: sql,
      profileId: profile.id,
      profileName: profile.name,
      executedAt: startTime,
    );

    try {
      final result = profile.type == DbType.postgresql
          ? await _executePostgresQuery(profile, sql)
          : await _executeSqliteQuery(profile, sql);

      final duration = DateTime.now().difference(startTime);
      entry.durationMs = duration.inMilliseconds;
      entry.success = true;
      entry.rowCount = result.rows.length;

      _history.insert(0, entry);
      if (_history.length > _maxHistory) _history.removeLast();
      await _saveHistory();

      _eventController.add(DbEvent(
        type: DbEventType.queryExecuted,
        message: 'Query returned ${result.rows.length} rows in ${duration.inMilliseconds}ms',
        profileId: profile.id,
      ));

      return result;
    } catch (e) {
      entry.success = false;
      entry.error = e.toString();
      entry.durationMs = DateTime.now().difference(startTime).inMilliseconds;

      _history.insert(0, entry);
      if (_history.length > _maxHistory) _history.removeLast();
      await _saveHistory();

      _eventController.add(DbEvent(
        type: DbEventType.queryError,
        message: 'Query failed: $e',
        profileId: profile.id,
      ));

      rethrow;
    }
  }

  Future<void> _testPostgresConnection(DbProfile profile) async {
    final env = <String, String>{};
    if (profile.password.isNotEmpty) {
      env['PGPASSWORD'] = profile.password;
    }

    final result = await Process.run(
      'psql',
      [
        '-h', profile.host,
        '-p', profile.port.toString(),
        '-U', profile.username,
        '-d', profile.database,
        '-c', 'SELECT 1;',
      ],
      environment: env,
      runInShell: true,
    );

    if (result.exitCode != 0) {
      throw Exception('PostgreSQL connection failed:\n${result.stderr}');
    }
  }

  Future<void> _testSqliteConnection(DbProfile profile) async {
    final file = File(profile.filePath);
    if (!await file.exists()) {
      throw Exception('SQLite file not found: ${profile.filePath}');
    }
  }

  Future<DbQueryResult> _executePostgresQuery(DbProfile profile, String sql) async {
    final env = <String, String>{};
    if (profile.password.isNotEmpty) {
      env['PGPASSWORD'] = profile.password;
    }

    final result = await Process.run(
      'psql',
      [
        '-h', profile.host,
        '-p', profile.port.toString(),
        '-U', profile.username,
        '-d', profile.database,
        '-A',           // unaligned output
        '-F', '\t',     // tab-separated
        '--no-align',
        '-t',           // tuples only
        '-c', sql,
      ],
      environment: env,
      runInShell: true,
    ).timeout(const Duration(milliseconds: _queryTimeout));

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString().trim());
    }

    return _parseTabSeparatedOutput(result.stdout.toString());
  }

  Future<DbQueryResult> _executeSqliteQuery(DbProfile profile, String sql) async {
    final isSelect = sql.trim().toUpperCase().startsWith('SELECT') ||
        sql.trim().toUpperCase().startsWith('PRAGMA');

    final args = <String>[
      profile.filePath,
      if (isSelect) ...['-header', '-separator', '\t'],
      sql,
    ];

    final result = await Process.run(
      'sqlite3',
      args,
      runInShell: true,
    ).timeout(const Duration(milliseconds: _queryTimeout));

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString().trim());
    }

    if (isSelect) {
      return _parseTabSeparatedOutput(result.stdout.toString(), hasHeader: true);
    } else {
      return DbQueryResult(
        columns: ['affected_rows'],
        rows: [['${result.stdout.toString().trim() != '' ? 'OK' : '0'}']],
        rawOutput: result.stdout.toString(),
      );
    }
  }

  DbQueryResult _parseTabSeparatedOutput(String output, {bool hasHeader = false}) {
    final lines = output.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      return DbQueryResult(columns: [], rows: []);
    }

    List<String> columns;
    List<List<String>> rows;

    if (hasHeader) {
      columns = lines.first.split('\t');
      rows = lines.skip(1).map((l) => l.split('\t')).toList();
    } else {
      rows = lines.map((l) => l.split('\t')).toList();
      columns = List.generate(
        rows.isNotEmpty ? rows.first.length : 0,
        (i) => 'column_${i + 1}',
      );
    }

    return DbQueryResult(columns: columns, rows: rows, rawOutput: output);
  }

  Future<String> exportResults(DbQueryResult result, String format) async {
    switch (format) {
      case 'csv':
        final buffer = StringBuffer();
        buffer.writeln(result.columns.join(','));
        for (final row in result.rows) {
          buffer.writeln(row.map((v) => '"${v.replaceAll('"', '""')}"').join(','));
        }
        return buffer.toString();
      case 'json':
        final data = result.rows.map((row) {
          final map = <String, String>{};
          for (var i = 0; i < result.columns.length && i < row.length; i++) {
            map[result.columns[i]] = row[i];
          }
          return map;
        }).toList();
        return const JsonEncoder.withIndent('  ').convert(data);
      case 'tsv':
        return '${result.columns.join('\t')}\n${result.rows.map((r) => r.join('\t')).join('\n')}';
      default:
        throw Exception('Unsupported export format: $format');
    }
  }

  Future<List<String>> listPostgresTables(DbProfile profile) async {
    final result = await executeQuery(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;",
    );
    return result.rows.map((r) => r.first).toList();
  }

  Future<List<String>> listSqliteTables(DbProfile profile) async {
    final result = await executeQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;",
    );
    return result.rows.map((r) => r.first).toList();
  }

  Future<List<DbColumnInfo>> describeTable(String table) async {
    final profile = activeProfile;
    if (profile == null) throw Exception('Not connected');

    if (profile.type == DbType.postgresql) {
      final result = await executeQuery(
        "SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name = '$table' ORDER BY ordinal_position;",
      );
      return result.rows.map((r) => DbColumnInfo(
        name: r[0],
        type: r[1],
        nullable: r[2] == 'YES',
        defaultValue: r.length > 3 ? r[3] : null,
      )).toList();
    } else {
      final result = await executeQuery("PRAGMA table_info($table);");
      return result.rows.map((r) => DbColumnInfo(
        name: r[1],
        type: r[2],
        nullable: r[3] != '0',
        defaultValue: r.length > 4 && r[4] != 'null' ? r[4] : null,
      )).toList();
    }
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _isInitialized = false;
  }
}

class DbProfile {
  final String id;
  final String name;
  final DbType type;
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final String filePath;
  final DateTime createdAt;

  DbProfile({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    required this.filePath,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'host': host,
    'port': port,
    'database': database,
    'username': username,
    'password': password,
    'filePath': filePath,
    'createdAt': createdAt.toIso8601String(),
  };

  factory DbProfile.fromJson(Map<String, dynamic> json) => DbProfile(
    id: json['id'],
    name: json['name'],
    type: DbType.values.firstWhere((t) => t.name == json['type']),
    host: json['host'] ?? 'localhost',
    port: json['port'] ?? 5432,
    database: json['database'] ?? '',
    username: json['username'] ?? '',
    password: json['password'] ?? '',
    filePath: json['filePath'] ?? '',
    createdAt: DateTime.parse(json['createdAt']),
  );
}

enum DbType { postgresql, sqlite }

class DbHistoryEntry {
  final String id;
  final String sql;
  final String profileId;
  final String profileName;
  final DateTime executedAt;
  int? durationMs;
  bool success = false;
  String? error;
  int? rowCount;

  DbHistoryEntry({
    required this.id,
    required this.sql,
    required this.profileId,
    required this.profileName,
    required this.executedAt,
    this.durationMs,
    this.success = false,
    this.error,
    this.rowCount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'sql': sql,
    'profileId': profileId,
    'profileName': profileName,
    'executedAt': executedAt.toIso8601String(),
    'durationMs': durationMs,
    'success': success,
    'error': error,
    'rowCount': rowCount,
  };

  factory DbHistoryEntry.fromJson(Map<String, dynamic> json) => DbHistoryEntry(
    id: json['id'],
    sql: json['sql'],
    profileId: json['profileId'],
    profileName: json['profileName'],
    executedAt: DateTime.parse(json['executedAt']),
    durationMs: json['durationMs'],
    success: json['success'] ?? false,
    error: json['error'],
    rowCount: json['rowCount'],
  );
}

class DbQueryResult {
  final List<String> columns;
  final List<List<String>> rows;
  final String? rawOutput;

  DbQueryResult({
    required this.columns,
    required this.rows,
    this.rawOutput,
  });
}

class DbColumnInfo {
  final String name;
  final String type;
  final bool nullable;
  final String? defaultValue;

  DbColumnInfo({
    required this.name,
    required this.type,
    required this.nullable,
    this.defaultValue,
  });
}

enum DbEventType {
  profileAdded,
  profileRemoved,
  connected,
  disconnected,
  queryExecuted,
  queryError,
}

class DbEvent {
  final DbEventType type;
  final String message;
  final String? profileId;
  final DateTime timestamp;

  DbEvent({
    required this.type,
    required this.message,
    this.profileId,
  }) : timestamp = DateTime.now();
}

void debugLog(String message) {
  final ts = DateTime.now().toIso8601String();
  stderr.writeln('[$ts] [DB] $message');
}