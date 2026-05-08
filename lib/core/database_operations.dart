import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';

/// Database operations integration for Termisol
///
/// Features:
/// - PostgreSQL client connections with connection pooling
/// - Multiple database support (NocoBase, Memster)
/// - Query execution with proper error handling
/// - Schema exploration and introspection
/// - Connection health monitoring
/// - Query history and performance metrics
/// - Secure parameterized queries
class DatabaseOperations {
  static String get _nocobaseHost => Platform.environment['NOCOBASE_HOST'] ?? '192.168.1.233';
  static int get _nocobasePort => int.tryParse(Platform.environment['NOCOBASE_PORT'] ?? '') ?? 5432;
  static String get _nocobaseDatabase => Platform.environment['NOCOBASE_DATABASE'] ?? 'nocobase';

  static String get _memsterHost => Platform.environment['MEMSTER_HOST'] ?? '192.168.1.250';
  static int get _memsterPort => int.tryParse(Platform.environment['MEMSTER_PORT'] ?? '') ?? 5432;
  static String get _memsterDatabase => Platform.environment['MEMSTER_DATABASE'] ?? 'memster';

  // Connection pools
  PostgreSQLConnection? _nocobaseConnection;
  PostgreSQLConnection? _memsterConnection;

  // Connection monitoring
  Timer? _healthCheckTimer;
  final Map<DatabaseType, DateTime> _lastActivity = {};
  final Map<DatabaseType, bool> _connectionHealth = {};

  // Query management
  final StreamController<DatabaseEvent> _eventController = StreamController<DatabaseEvent>.broadcast();
  final List<DatabaseQuery> _queryHistory = [];
  final List<DatabaseQuery> _favoriteQueries = [];
  static const int _maxHistorySize = 100;

  Stream<DatabaseEvent> get events => _eventController.stream;
  List<DatabaseQuery> get queryHistory => List.unmodifiable(_queryHistory);
  List<DatabaseQuery> get favoriteQueries => List.unmodifiable(_favoriteQueries);

  /// Initialize database operations system
  Future<void> initialize() async {
    _startHealthMonitoring();
    _eventController.add(DatabaseEvent(
      type: DatabaseEventType.systemInitialized,
      message: 'Database operations system initialized',
    ));
  }

  /// Connect to NocoBase database
  Future<bool> connectToNocoBase({
    required String username,
    required String password,
    int? timeoutSeconds,
  }) async {
    try {
      _nocobaseConnection?.close();

      _nocobaseConnection = PostgreSQLConnection(
        _nocobaseHost,
        _nocobasePort,
        _nocobaseDatabase,
        username: username,
        password: password,
        timeoutInSeconds: timeoutSeconds ?? 30,
        useSSL: false, // Internal network
      );

      await _nocobaseConnection!.open();
      await _validateConnection(DatabaseType.nocobase);

      _connectionHealth[DatabaseType.nocobase] = true;
      _lastActivity[DatabaseType.nocobase] = DateTime.now();

      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.connected,
        message: 'Connected to NocoBase database',
        data: {
          'database': _nocobaseDatabase,
          'host': _nocobaseHost,
          'port': _nocobasePort,
        },
      ));

      return true;
    } catch (e, stack) {
      _connectionHealth[DatabaseType.nocobase] = false;
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.connectionFailed,
        message: 'Failed to connect to NocoBase: $e',
        data: {
          'error': e.toString(),
          'stack': stack.toString(),
        },
      ));
      return false;
    }
  }

  /// Connect to Memster database
  Future<bool> connectToMemster({
    required String username,
    required String password,
    int? timeoutSeconds,
  }) async {
    try {
      _memsterConnection?.close();

      _memsterConnection = PostgreSQLConnection(
        _memsterHost,
        _memsterPort,
        _memsterDatabase,
        username: username,
        password: password,
        timeoutInSeconds: timeoutSeconds ?? 30,
        useSSL: false, // Internal network
      );

      await _memsterConnection!.open();
      await _validateConnection(DatabaseType.memster);

      _connectionHealth[DatabaseType.memster] = true;
      _lastActivity[DatabaseType.memster] = DateTime.now();

      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.connected,
        message: 'Connected to Memster database',
        data: {
          'database': _memsterDatabase,
          'host': _memsterHost,
          'port': _memsterPort,
        },
      ));

      return true;
    } catch (e, stack) {
      _connectionHealth[DatabaseType.memster] = false;
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.connectionFailed,
        message: 'Failed to connect to Memster: $e',
        data: {
          'error': e.toString(),
          'stack': stack.toString(),
        },
      ));
      return false;
    }
  }

  /// Execute query on specified database
  Future<DatabaseQueryResult> executeQuery({
    required DatabaseType database,
    required String query,
    Map<String, dynamic>? parameters,
    int? timeoutSeconds,
  }) async {
    final startTime = DateTime.now();
    final connection = _getConnection(database);

    if (connection == null) {
      throw DatabaseException('Not connected to database: $database');
    }

    try {
      PostgreSQLResult result;

      if (parameters != null && parameters.isNotEmpty) {
        // Use parameterized queries for security
        result = await connection.query(
          query,
          substitutionValues: parameters,
        ).timeout(Duration(seconds: timeoutSeconds ?? 30));
      } else {
        result = await connection.query(query).timeout(Duration(seconds: timeoutSeconds ?? 30));
      }

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      final queryResult = DatabaseQueryResult(
        query: query,
        database: database,
        rows: _convertResultToRows(result),
        rowCount: result.length,
        columnCount: result.firstOrNull?.keys.length ?? 0,
        executionTime: duration,
        success: true,
        parameters: parameters,
      );

      // Update activity tracking
      _lastActivity[database] = DateTime.now();

      // Add to history
      _addToHistory(DatabaseQuery(
        query: query,
        database: database,
        timestamp: DateTime.now(),
        success: true,
        executionTime: duration,
        rowCount: result.length,
        parameters: parameters,
      ));

      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.queryExecuted,
        message: 'Query executed successfully',
        data: {
          'database': database.toString(),
          'query': query.substring(0, min(100, query.length)),
          'rows': result.length,
          'duration': duration.inMilliseconds,
        },
      ));

      return queryResult;
    } catch (e, stack) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      // Add failed query to history
      _addToHistory(DatabaseQuery(
        query: query,
        database: database,
        timestamp: DateTime.now(),
        success: false,
        executionTime: duration,
        error: e.toString(),
        parameters: parameters,
      ));

      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.queryFailed,
        message: 'Query execution failed: $e',
        data: {
          'database': database.toString(),
          'query': query.substring(0, min(100, query.length)),
          'error': e.toString(),
          'duration': duration.inMilliseconds,
        },
      ));

      rethrow;
    }
  }

  /// Execute multiple queries in a transaction
  Future<List<DatabaseQueryResult>> executeTransaction({
    required DatabaseType database,
    required List<String> queries,
    List<Map<String, dynamic>>? parameters,
  }) async {
    final connection = _getConnection(database);
    if (connection == null) {
      throw DatabaseException('Not connected to database: $database');
    }

    final results = <DatabaseQueryResult>[];

    try {
      await connection.transaction((ctx) async {
        for (int i = 0; i < queries.length; i++) {
          final query = queries[i];
          final params = parameters != null && i < parameters.length ? parameters[i] : null;

          final result = await executeQuery(
            database: database,
            query: query,
            parameters: params,
          );

          results.add(result);
        }
      });

      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.transactionCompleted,
        message: 'Transaction completed successfully',
        data: {
          'database': database.toString(),
          'queryCount': queries.length,
        },
      ));

      return results;
    } catch (e) {
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.transactionFailed,
        message: 'Transaction failed: $e',
        data: {
          'database': database.toString(),
          'error': e.toString(),
        },
      ));
      rethrow;
    }
  }

  /// Get database schema information
  Future<DatabaseSchema> getSchema(DatabaseType database) async {
    final connection = _getConnection(database);
    if (connection == null) {
      throw DatabaseException('Not connected to database: $database');
    }

    try {
      // Get tables
      final tablesResult = await connection.query('''
        SELECT
          table_name,
          table_type,
          table_schema
        FROM information_schema.tables
        WHERE table_schema = 'public'
        ORDER BY table_name
      ''');

      final tables = <DatabaseTable>[];

      for (final row in tablesResult) {
        final tableName = row[0] as String;
        final tableType = row[1] as String;
        final schema = row[2] as String;

        // Get columns for this table
        final columnsResult = await connection.query('''
          SELECT
            column_name,
            data_type,
            is_nullable,
            column_default,
            character_maximum_length,
            numeric_precision,
            numeric_scale
          FROM information_schema.columns
          WHERE table_name = '$tableName' AND table_schema = '$schema'
          ORDER BY ordinal_position
        ''');

        final columns = <DatabaseColumn>[];
        for (final columnRow in columnsResult) {
          columns.add(DatabaseColumn(
            name: columnRow[0] as String,
            dataType: columnRow[1] as String,
            nullable: columnRow[2] == 'YES',
            defaultValue: columnRow[3]?.toString(),
            maxLength: columnRow[4] as int?,
            precision: columnRow[5] as int?,
            scale: columnRow[6] as int?,
          ));
        }

        // Get indexes
        final indexesResult = await connection.query('''
          SELECT
            indexname,
            indexdef
          FROM pg_indexes
          WHERE tablename = '$tableName' AND schemaname = '$schema'
        ''');

        final indexes = <DatabaseIndex>[];
        for (final indexRow in indexesResult) {
          indexes.add(DatabaseIndex(
            name: indexRow[0] as String,
            definition: indexRow[1] as String,
          ));
        }

        tables.add(DatabaseTable(
          name: tableName,
          schema: schema,
          type: tableType,
          columns: columns,
          indexes: indexes,
        ));
      }

      return DatabaseSchema(tables: tables);
    } catch (e, stack) {
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.schemaError,
        message: 'Failed to get schema: $e',
        data: {'database': database.toString(), 'error': e.toString()},
      ));
      rethrow;
    }
  }

  /// Get table data with pagination
  Future<DatabaseQueryResult> getTableData({
    required DatabaseType database,
    required String tableName,
    int limit = 100,
    int offset = 0,
    String? orderBy,
    bool descending = false,
  }) async {
    final orderClause = orderBy != null
        ? 'ORDER BY $orderBy ${descending ? 'DESC' : 'ASC'}'
        : '';

    final query = '''
      SELECT * FROM $tableName
      $orderClause
      LIMIT $limit OFFSET $offset
    ''';

    return executeQuery(database: database, query: query);
  }

  /// Get table statistics
  Future<Map<String, dynamic>> getTableStats(DatabaseType database, String tableName) async {
    final query = '''
      SELECT
        schemaname,
        tablename,
        attname,
        n_distinct,
        correlation
      FROM pg_stats
      WHERE tablename = '$tableName'
      ORDER BY attname
    ''';

    final result = await executeQuery(database: database, query: query);

    final stats = <String, dynamic>{
      'table': tableName,
      'columns': <Map<String, dynamic>>[],
    };

    for (final row in result.rows) {
      stats['columns'].add({
        'name': row['attname'],
        'distinct_values': row['n_distinct'],
        'correlation': row['correlation'],
      });
    }

    return stats;
  }

  /// Add query to favorites
  void addToFavorites(DatabaseQuery query) {
    if (!_favoriteQueries.contains(query)) {
      _favoriteQueries.add(query);
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.queryFavorited,
        message: 'Query added to favorites',
        data: {'query': query.query.substring(0, min(50, query.query.length))},
      ));
    }
  }

  /// Remove query from favorites
  void removeFromFavorites(DatabaseQuery query) {
    _favoriteQueries.remove(query);
    _eventController.add(DatabaseEvent(
      type: DatabaseEventType.queryUnfavorited,
      message: 'Query removed from favorites',
      data: {'query': query.query.substring(0, min(50, query.query.length))},
    ));
  }

  /// Clear query history
  void clearHistory() {
    _queryHistory.clear();
    _eventController.add(DatabaseEvent(
      type: DatabaseEventType.historyCleared,
      message: 'Query history cleared',
    ));
  }

  /// Get connection status
  Map<DatabaseType, ConnectionStatus> getConnectionStatus() {
    return {
      DatabaseType.nocobase: ConnectionStatus(
        connected: _nocobaseConnection?.isOpen ?? false,
        healthy: _connectionHealth[DatabaseType.nocobase] ?? false,
        lastActivity: _lastActivity[DatabaseType.nocobase],
      ),
      DatabaseType.memster: ConnectionStatus(
        connected: _memsterConnection?.isOpen ?? false,
        healthy: _connectionHealth[DatabaseType.memster] ?? false,
        lastActivity: _lastActivity[DatabaseType.memster],
      ),
    };
  }

  /// Disconnect from all databases
  Future<void> disconnectAll() async {
    try {
      await _nocobaseConnection?.close();
      await _memsterConnection?.close();

      _nocobaseConnection = null;
      _memsterConnection = null;

      _connectionHealth.clear();
      _lastActivity.clear();

      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.disconnected,
        message: 'Disconnected from all databases',
      ));
    } catch (e) {
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.error,
        message: 'Error during disconnect: $e',
        data: {'error': e.toString()},
      ));
    }
  }

  /// Dispose all resources
  void dispose() {
    _healthCheckTimer?.cancel();
    disconnectAll();
    _eventController.close();
  }

  // Private methods

  PostgreSQLConnection? _getConnection(DatabaseType database) {
    switch (database) {
      case DatabaseType.nocobase:
        return _nocobaseConnection;
      case DatabaseType.memster:
        return _memsterConnection;
    }
  }

  List<Map<String, dynamic>> _convertResultToRows(PostgreSQLResult result) {
    if (result.isEmpty) return [];

    final columnNames = result.first.keys.toList();
    final rows = <Map<String, dynamic>>[];

    for (final row in result) {
      final rowData = <String, dynamic>{};
      for (int i = 0; i < columnNames.length; i++) {
        rowData[columnNames[i]] = row[i];
      }
      rows.add(rowData);
    }

    return rows;
  }

  void _addToHistory(DatabaseQuery query) {
    _queryHistory.insert(0, query);
    if (_queryHistory.length > _maxHistorySize) {
      _queryHistory.removeLast();
    }
  }

  Future<void> _validateConnection(DatabaseType database) async {
    final connection = _getConnection(database);
    if (connection == null) return;

    // Simple validation query
    await connection.query('SELECT 1');
  }

  void _startHealthMonitoring() {
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      for (final database in DatabaseType.values) {
        try {
          await _validateConnection(database);
          _connectionHealth[database] = true;
        } catch (e) {
          _connectionHealth[database] = false;
          _eventController.add(DatabaseEvent(
            type: DatabaseEventType.connectionHealthChanged,
            message: 'Connection health check failed for $database',
            data: {'database': database.toString(), 'error': e.toString()},
          ));
        }
      }
    });
  }
}

/// Database types
enum DatabaseType {
  nocobase,
  memster;

  @override
  String toString() {
    switch (this) {
      case DatabaseType.nocobase:
        return 'NocoBase';
      case DatabaseType.memster:
        return 'Memster';
    }
  }
}

/// Connection status
class ConnectionStatus {
  final bool connected;
  final bool healthy;
  final DateTime? lastActivity;

  ConnectionStatus({
    required this.connected,
    required this.healthy,
    this.lastActivity,
  });

  bool get isActive => connected && healthy;
}

/// Database schema information
class DatabaseSchema {
  final List<DatabaseTable> tables;

  DatabaseSchema({required this.tables});

  DatabaseTable? getTable(String name) {
    try {
      return tables.firstWhere((table) => table.name == name);
    } catch (e) {
      return null;
    }
  }

  List<String> get tableNames => tables.map((t) => t.name).toList();

  int get tableCount => tables.length;

  @override
  String toString() => 'DatabaseSchema(tables: $tableCount)';
}

/// Database table information
class DatabaseTable {
  final String name;
  final String schema;
  final String type;
  final List<DatabaseColumn> columns;
  final List<DatabaseIndex> indexes;

  DatabaseTable({
    required this.name,
    required this.schema,
    required this.type,
    required this.columns,
    required this.indexes,
  });

  bool get isView => type.toLowerCase() == 'view';

  int get columnCount => columns.length;

  List<String> get columnNames => columns.map((c) => c.name).toList();

  @override
  String toString() => '$type $schema.$name ($columnCount columns)';
}

/// Database column information
class DatabaseColumn {
  final String name;
  final String dataType;
  final bool nullable;
  final String? defaultValue;
  final int? maxLength;
  final int? precision;
  final int? scale;

  DatabaseColumn({
    required this.name,
    required this.dataType,
    required this.nullable,
    this.defaultValue,
    this.maxLength,
    this.precision,
    this.scale,
  });

  bool get isNumeric => ['integer', 'bigint', 'smallint', 'decimal', 'numeric', 'real', 'double precision'].contains(dataType.toLowerCase());
  bool get isText => ['character varying', 'varchar', 'text', 'character'].contains(dataType.toLowerCase());

  @override
  String toString() => '$name $dataType${nullable ? '' : ' NOT NULL'}';
}

/// Database index information
class DatabaseIndex {
  final String name;
  final String definition;

  DatabaseIndex({
    required this.name,
    required this.definition,
  });

  @override
  String toString() => '$name: $definition';
}

/// Database query result
class DatabaseQueryResult {
  final String query;
  final DatabaseType database;
  final List<Map<String, dynamic>> rows;
  final int rowCount;
  final int columnCount;
  final Duration executionTime;
  final bool success;
  final String? error;
  final Map<String, dynamic>? parameters;

  DatabaseQueryResult({
    required this.query,
    required this.database,
    required this.rows,
    required this.rowCount,
    required this.columnCount,
    required this.executionTime,
    required this.success,
    this.error,
    this.parameters,
  });

  List<String> get columns => rows.isNotEmpty ? rows.first.keys.toList() : [];

  String get formattedExecutionTime {
    if (executionTime.inMilliseconds < 1000) {
      return '${executionTime.inMilliseconds}ms';
    } else {
      return '${executionTime.inMilliseconds / 1000}s';
    }
  }

  bool get hasResults => rows.isNotEmpty;

  @override
  String toString() => 'DatabaseQueryResult(rows: $rowCount, time: $formattedExecutionTime, success: $success)';
}

/// Database query history entry
class DatabaseQuery {
  final String query;
  final DatabaseType database;
  final DateTime timestamp;
  final bool success;
  final Duration? executionTime;
  final int? rowCount;
  final String? error;
  final Map<String, dynamic>? parameters;

  DatabaseQuery({
    required this.query,
    required this.database,
    required this.timestamp,
    required this.success,
    this.executionTime,
    this.rowCount,
    this.error,
    this.parameters,
  });

  String get formattedTimestamp {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
           '${timestamp.minute.toString().padLeft(2, '0')}:'
           '${timestamp.second.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => '[$formattedTimestamp] ${database.toString()} - ${success ? 'SUCCESS' : 'FAILED'}';
}

/// Database event types
enum DatabaseEventType {
  systemInitialized,
  connected,
  disconnected,
  connectionFailed,
  connectionHealthChanged,
  queryExecuted,
  queryFailed,
  transactionCompleted,
  transactionFailed,
  schemaError,
  queryFavorited,
  queryUnfavorited,
  historyCleared,
  error,
}

/// Database event
class DatabaseEvent {
  final DatabaseEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  DatabaseEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();

  @override
  String toString() => '[$timestamp] $type: $message';
}

/// Database exception
class DatabaseException implements Exception {
  final String message;

  DatabaseException(this.message);

  @override
  String toString() => 'DatabaseException: $message';
}