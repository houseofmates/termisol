import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:postgres/postgres.dart';

/// Database operations integration for Termisol
/// 
/// Features:
/// - PostgreSQL client connections
/// - NocoBase database on .233
/// - Memster database on .250
/// - Query execution and results
/// - Database schema exploration
/// - Connection management
/// - Query history and favorites
class DatabaseOperations {
  static String get _nocobaseHost => Platform.environment['NOCOBASE_HOST'] ?? '192.168.1.233';
  static int get _nocobasePort => int.tryParse(Platform.environment['NOCOBASE_PORT'] ?? '') ?? 5432;
  static String get _nocobaseDatabase => Platform.environment['NOCOBASE_DATABASE'] ?? 'nocobase';
  
  static String get _memsterHost => Platform.environment['MEMSTER_HOST'] ?? '192.168.1.250';
  static int get _memsterPort => int.tryParse(Platform.environment['MEMSTER_PORT'] ?? '') ?? 5432;
  static String get _memsterDatabase => Platform.environment['MEMSTER_DATABASE'] ?? 'memster';
  
  PostgreSQLConnection? _nocobaseConnection;
  PostgreSQLConnection? _memsterConnection;
  
  final StreamController<DatabaseEvent> _eventController = StreamController<DatabaseEvent>.broadcast();
  final List<DatabaseQuery> _queryHistory = [];
  final List<DatabaseQuery> _favoriteQueries = [];
  
  Stream<DatabaseEvent> get events => _eventController.stream;
  List<DatabaseQuery> get queryHistory => List.unmodifiable(_queryHistory);
  List<DatabaseQuery> get favoriteQueries => List.unmodifiable(_favoriteQueries);
  
  /// Connect to NocoBase database
  Future<bool> connectToNocoBase({
    required String username,
    required String password,
  }) async {
    try {
      _nocobaseConnection = PostgreSQLConnection(
        _nocobaseHost,
        _nocobasePort,
        _nocobaseDatabase,
        username: username,
        password: password,
      );
      
      await _nocobaseConnection!.open();
      
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.connected,
        message: 'Connected to NocoBase database',
        data: {'database': _nocobaseDatabase, 'host': _nocobaseHost},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.error,
        message: 'Failed to connect to NocoBase: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Connect to Memster database
  Future<bool> connectToMemster({
    required String username,
    required String password,
  }) async {
    try {
      _memsterConnection = PostgreSQLConnection(
        _memsterHost,
        _memsterPort,
        _memsterDatabase,
        username: username,
        password: password,
      );
      
      await _memsterConnection!.open();
      
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.connected,
        message: 'Connected to Memster database',
        data: {'database': _memsterDatabase, 'host': _memsterHost},
      ));
      
      return true;
    } catch (e) {
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.error,
        message: 'Failed to connect to Memster: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Execute query on specified database
  Future<DatabaseQueryResult> executeQuery({
    required DatabaseType database,
    required String query,
    Map<String, dynamic>? parameters,
  }) async {
    final connection = _getConnection(database);
    if (connection == null) {
      throw Exception('Not connected to database: $database');
    }
    
    final startTime = DateTime.now();
    
    try {
      PostgreSQLResult result;
      
      if (parameters != null && parameters.isNotEmpty) {
        result = await connection.query(query, substitutionValues: parameters);
      } else {
        result = await connection.query(query);
      }
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      final queryResult = DatabaseQueryResult(
        query: query,
        database: database,
        rows: _convertResultToRows(result),
        rowCount: result.length,
        executionTime: duration,
        success: true,
      );
      
      // Add to history
      _addToHistory(DatabaseQuery(
        query: query,
        database: database,
        timestamp: DateTime.now(),
        success: true,
      ));
      
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.query_executed,
        message: 'Query executed successfully',
        data: {
          'database': database.toString(),
          'query': query,
          'rows': result.length,
          'duration': duration.inMilliseconds,
        },
      ));
      
      return queryResult;
    } catch (e) {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      // Add to history
      _addToHistory(DatabaseQuery(
        query: query,
        database: database,
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
      ));
      
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.error,
        message: 'Query execution failed: $e',
        data: {
          'database': database.toString(),
          'query': query,
          'error': e.toString(),
        },
      ));
      
      return DatabaseQueryResult(
        query: query,
        database: database,
        rows: [],
        rowCount: 0,
        executionTime: duration,
        success: false,
        error: e.toString(),
      );
    }
  }
  
  /// Get database schema
  Future<DatabaseSchema?> getSchema(DatabaseType database) async {
    final connection = _getConnection(database);
    if (connection == null) return null;
    
    try {
      // Get tables
      final tablesResult = await connection.query('''
        SELECT table_name, table_type 
        FROM information_schema.tables 
        WHERE table_schema = 'public'
        ORDER BY table_name
      ''');
      
      final tables = <DatabaseTable>[];
      
      for (final row in tablesResult) {
        final tableName = row[0] as String;
        final tableType = row[1] as String;
        
        // Get columns for this table
        final columnsResult = await connection.query('''
          SELECT column_name, data_type, is_nullable, column_default
          FROM information_schema.columns
          WHERE table_name = '$tableName'
          ORDER BY ordinal_position
        ''');
        
        final columns = <DatabaseColumn>[];
        for (final columnRow in columnsResult) {
          columns.add(DatabaseColumn(
            name: columnRow[0] as String,
            dataType: columnRow[1] as String,
            nullable: columnRow[2] == 'YES',
            defaultValue: columnRow[3] as String?,
          ));
        }
        
        tables.add(DatabaseTable(
          name: tableName,
          type: tableType,
          columns: columns,
        ));
      }
      
      return DatabaseSchema(tables: tables);
    } catch (e) {
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.error,
        message: 'Failed to get schema: $e',
        data: {'database': database.toString(), 'error': e.toString()},
      ));
      return null;
    }
  }
  
  /// Get table data
  Future<DatabaseQueryResult> getTableData({
    required DatabaseType database,
    required String tableName,
    int limit = 100,
    int offset = 0,
  }) async {
    final query = '''
      SELECT * FROM $tableName
      ORDER BY id
      LIMIT $limit OFFSET $offset
    ''';
    
    return executeQuery(database: database, query: query);
  }
  
  /// Add query to favorites
  void addToFavorites(DatabaseQuery query) {
    _favoriteQueries.add(query);
    _eventController.add(DatabaseEvent(
      type: DatabaseEventType.query_favorited,
      message: 'Query added to favorites',
      data: {'query': query.query},
    ));
  }
  
  /// Remove query from favorites
  void removeFromFavorites(DatabaseQuery query) {
    _favoriteQueries.remove(query);
    _eventController.add(DatabaseEvent(
      type: DatabaseEventType.query_unfavorited,
      message: 'Query removed from favorites',
      data: {'query': query.query},
    ));
  }
  
  /// Clear query history
  void clearHistory() {
    _queryHistory.clear();
    _eventController.add(DatabaseEvent(
      type: DatabaseEventType.history_cleared,
      message: 'Query history cleared',
      data: {},
    ));
  }
  
  /// Get connection for database type
  PostgreSQLConnection? _getConnection(DatabaseType database) {
    switch (database) {
      case DatabaseType.nocobase:
        return _nocobaseConnection;
      case DatabaseType.memster:
        return _memsterConnection;
    }
  }
  
  /// Convert PostgreSQL result to rows
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
  
  /// Add query to history
  void _addToHistory(DatabaseQuery query) {
    _queryHistory.insert(0, query);
    if (_queryHistory.length > 100) {
      _queryHistory.removeLast();
    }
  }
  
  /// Disconnect from all databases
  Future<void> disconnectAll() async {
    try {
      await _nocobaseConnection?.close();
      await _memsterConnection?.close();
      
      _nocobaseConnection = null;
      _memsterConnection = null;
      
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.disconnected,
        message: 'Disconnected from all databases',
        data: {},
      ));
    } catch (e) {
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.error,
        message: 'Failed to disconnect: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Get connection status
  Map<DatabaseType, bool> getConnectionStatus() {
    return {
      DatabaseType.nocobase: _nocobaseConnection?.isOpened ?? false,
      DatabaseType.memster: _memsterConnection?.isOpened ?? false,
    };
  }
  
  /// Dispose
  void dispose() {
    disconnectAll();
    _eventController.close();
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
}

/// Database table information
class DatabaseTable {
  final String name;
  final String type;
  final List<DatabaseColumn> columns;
  
  DatabaseTable({
    required this.name,
    required this.type,
    required this.columns,
  });
  
  bool get isView => type.toLowerCase() == 'view';
}

/// Database column information
class DatabaseColumn {
  final String name;
  final String dataType;
  final bool nullable;
  final String? defaultValue;
  
  DatabaseColumn({
    required this.name,
    required this.dataType,
    required this.nullable,
    this.defaultValue,
  });
}

/// Database query result
class DatabaseQueryResult {
  final String query;
  final DatabaseType database;
  final List<Map<String, dynamic>> rows;
  final int rowCount;
  final Duration executionTime;
  final bool success;
  final String? error;
  
  DatabaseQueryResult({
    required this.query,
    required this.database,
    required this.rows,
    required this.rowCount,
    required this.executionTime,
    required this.success,
    this.error,
  });
  
  List<String> get columns {
    if (rows.isEmpty) return [];
    return rows.first.keys.toList();
  }
  
  String get formattedExecutionTime {
    if (executionTime.inMilliseconds < 1000) {
      return '${executionTime.inMilliseconds}ms';
    } else {
      return '${executionTime.inMilliseconds / 1000}s';
    }
  }
}

/// Database query history entry
class DatabaseQuery {
  final String query;
  final DatabaseType database;
  final DateTime timestamp;
  final bool success;
  final String? error;
  
  DatabaseQuery({
    required this.query,
    required this.database,
    required this.timestamp,
    required this.success,
    this.error,
  });
  
  String get formattedTimestamp {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
           '${timestamp.minute.toString().padLeft(2, '0')}:'
           '${timestamp.second.toString().padLeft(2, '0')}';
  }
}

/// Database event types
enum DatabaseEventType {
  connected,
  disconnected,
  query_executed,
  query_favorited,
  query_unfavorited,
  history_cleared,
  error,
}

/// Database event
class DatabaseEvent {
  final DatabaseEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  DatabaseEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}
