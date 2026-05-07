import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:postgresql2/postgresql.dart' as pg;

/// Database client connections for Postgres instances
/// Supports nocobase postgres (.233) and memster postgres (.250)
class DatabaseClient {
  static const String _nocobaseHost = '.233';
  static const String _memsterHost = '.250';
  
  final Map<String, DatabaseConnection> _connections = {};
  final StreamController<DatabaseEvent> _eventController = StreamController<DatabaseEvent>.broadcast();
  
  Stream<DatabaseEvent> get events => _eventController.stream;

  Future<bool> connectToNocobase({
    required String database,
    required String username,
    required String password,
    int port = 5432,
  }) async {
    return await _connect(
      connectionId: 'nocobase',
      host: _nocobaseHost,
      port: port,
      database: database,
      username: username,
      password: password,
    );
  }

  Future<bool> connectToMemster({
    required String database,
    required String username,
    required String password,
    int port = 5432,
  }) async {
    return await _connect(
      connectionId: 'memster',
      host: _memsterHost,
      port: port,
      database: database,
      username: username,
      password: password,
    );
  }

  Future<bool> connectToCustom({
    required String connectionId,
    required String host,
    required int port,
    required String database,
    required String username,
    required String password,
  }) async {
    return await _connect(
      connectionId: connectionId,
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    );
  }

  Future<bool> _connect({
    required String connectionId,
    required String host,
    required int port,
    required String database,
    required String username,
    required String password,
  }) async {
    try {
      final connection = pg.PostgreSQLConnection(
        host,
        port,
        database,
        username: username,
        password: password,
      );

      await connection.open();
      
      final dbConnection = DatabaseConnection(
        id: connectionId,
        host: host,
        port: port,
        database: database,
        username: username,
        connection: connection,
        connectedAt: DateTime.now(),
      );

      _connections[connectionId] = dbConnection;
      
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.connected,
        message: 'Connected to database $connectionId',
        data: {
          'connectionId': connectionId,
          'host': host,
          'database': database,
        },
      ));

      debugPrint('🗄️ Connected to database $connectionId ($host:$port/$database)');
      return true;
    } catch (e) {
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.error,
        message: 'Failed to connect to database $connectionId: $e',
        data: {
          'connectionId': connectionId,
          'error': e.toString(),
        },
      ));
      
      debugPrint('❌ Failed to connect to database $connectionId: $e');
      return false;
    }
  }

  Future<QueryResult> executeQuery(
    String connectionId,
    String query, {
    Map<String, dynamic>? parameters,
  }) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      return QueryResult(
        success: false,
        error: 'Connection $connectionId not found',
      );
    }

    try {
      final results = await connection.connection.query(
        query,
        substitutionValues: parameters,
      );

      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.query_executed,
        message: 'Query executed on $connectionId',
        data: {
          'connectionId': connectionId,
          'query': query,
          'rowCount': results.length,
        },
      ));

      return QueryResult(
        success: true,
        rows: results,
        rowCount: results.length,
      );
    } catch (e) {
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.error,
        message: 'Query failed on $connectionId: $e',
        data: {
          'connectionId': connectionId,
          'query': query,
          'error': e.toString(),
        },
      ));

      return QueryResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<QueryResult> getTableSchema(String connectionId, String tableName) async {
    final query = '''
      SELECT 
        column_name,
        data_type,
        is_nullable,
        column_default,
        character_maximum_length
      FROM information_schema.columns
      WHERE table_name = @tableName
      ORDER BY ordinal_position
    ''';

    return await executeQuery(
      connectionId,
      query,
      parameters: {'tableName': tableName},
    );
  }

  Future<QueryResult> getTableList(String connectionId) async {
    final query = '''
      SELECT 
        table_name,
        table_type
      FROM information_schema.tables
      WHERE table_schema = 'public'
      ORDER BY table_name
    ''';

    return await executeQuery(connectionId, query);
  }

  Future<QueryResult> getDatabaseInfo(String connectionId) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      return QueryResult(
        success: false,
        error: 'Connection $connectionId not found',
      );
    }

    try {
      final versionResult = await connection.connection.query('SELECT version()');
      final sizeResult = await connection.connection.query('''
        SELECT pg_size_pretty(pg_database_size(@database)) as size
      ''', substitutionValues: {'database': connection.database});

      return QueryResult(
        success: true,
        rows: [
          {
            'version': versionResult.first[0],
            'size': sizeResult.first[0],
            'host': connection.host,
            'database': connection.database,
            'connected_at': connection.connectedAt.toIso8601String(),
          }
        ],
        rowCount: 1,
      );
    } catch (e) {
      return QueryResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<bool> disconnect(String connectionId) async {
    final connection = _connections[connectionId];
    if (connection == null) return false;

    try {
      await connection.connection.close();
      _connections.remove(connectionId);
      
      _eventController.add(DatabaseEvent(
        type: DatabaseEventType.disconnected,
        message: 'Disconnected from database $connectionId',
        data: {'connectionId': connectionId},
      ));

      debugPrint('🗄️ Disconnected from database $connectionId');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to disconnect from database $connectionId: $e');
      return false;
    }
  }

  Future<void> disconnectAll() async {
    for (final connectionId in _connections.keys.toList()) {
      await disconnect(connectionId);
    }
  }

  List<DatabaseConnection> getConnections() {
    return _connections.values.toList();
  }

  DatabaseConnection? getConnection(String connectionId) {
    return _connections[connectionId];
  }

  bool isConnected(String connectionId) {
    return _connections.containsKey(connectionId);
  }

  DatabaseStatistics getStatistics() {
    return DatabaseStatistics(
      totalConnections: _connections.length,
      nocobaseConnected: _connections.containsKey('nocobase'),
      memsterConnected: _connections.containsKey('memster'),
      customConnections: _connections.keys
          .where((id) => id != 'nocobase' && id != 'memster')
          .length,
    );
  }

  Future<void> dispose() async {
    await disconnectAll();
    _eventController.close();
    debugPrint('🗄️ Database Client disposed');
  }
}

class DatabaseConnection {
  final String id;
  final String host;
  final int port;
  final String database;
  final String username;
  final pg.PostgreSQLConnection connection;
  final DateTime connectedAt;

  DatabaseConnection({
    required this.id,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.connection,
    required this.connectedAt,
  });

  String get displayName => '$id ($host:$port/$database)';
}

class QueryResult {
  final bool success;
  final List<Map<String, dynamic>>? rows;
  final int? rowCount;
  final String? error;

  QueryResult({
    required this.success,
    this.rows,
    this.rowCount,
    this.error,
  });
}

class DatabaseStatistics {
  final int totalConnections;
  final bool nocobaseConnected;
  final bool memsterConnected;
  final int customConnections;

  DatabaseStatistics({
    required this.totalConnections,
    required this.nocobaseConnected,
    required this.memsterConnected,
    required this.customConnections,
  });
}

enum DatabaseEventType {
  connected,
  disconnected,
  query_executed,
  error,
}

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
}

// Database client widget
class DatabaseClientWidget extends StatefulWidget {
  final Function(QueryResult)? onQueryComplete;

  const DatabaseClientWidget({
    super.key,
    this.onQueryComplete,
  });

  @override
  State<DatabaseClientWidget> createState() => _DatabaseClientWidgetState();
}

class _DatabaseClientWidgetState extends State<DatabaseClientWidget> {
  final DatabaseClient _dbClient = DatabaseClient();
  String? _selectedConnection;
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _nocobaseController = TextEditingController();
  final TextEditingController _memsterController = TextEditingController();
  
  List<Map<String, dynamic>> _queryResults = [];
  bool _isExecuting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dbClient.events.listen((event) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _nocobaseController.dispose();
    _memsterController.dispose();
    super.dispose();
  }

  Future<void> _connectToNocobase() async {
    final parts = _nocobaseController.text.split(':');
    if (parts.length != 3) {
      setState(() {
        _error = 'Format: username:password:database';
      });
      return;
    }

    final success = await _dbClient.connectToNocobase(
      database: parts[2],
      username: parts[0],
      password: parts[1],
    );

    if (success) {
      setState(() {
        _selectedConnection = 'nocobase';
        _nocobaseController.clear();
        _error = null;
      });
    }
  }

  Future<void> _connectToMemster() async {
    final parts = _memsterController.text.split(':');
    if (parts.length != 3) {
      setState(() {
        _error = 'Format: username:password:database';
      });
      return;
    }

    final success = await _dbClient.connectToMemster(
      database: parts[2],
      username: parts[0],
      password: parts[1],
    );

    if (success) {
      setState(() {
        _selectedConnection = 'memster';
        _memsterController.clear();
        _error = null;
      });
    }
  }

  Future<void> _executeQuery() async {
    if (_selectedConnection == null || _queryController.text.trim().isEmpty) {
      return;
    }

    setState(() {
      _isExecuting = true;
      _error = null;
    });

    final result = await _dbClient.executeQuery(
      _selectedConnection!,
      _queryController.text,
    );

    setState(() {
      _isExecuting = false;
      _queryResults = result.rows ?? [];
      if (!result.success) {
        _error = result.error;
      }
    });

    if (widget.onQueryComplete != null) {
      widget.onQueryComplete!(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connections = _dbClient.getConnections();

    return Column(
      children: [
        // Connection bar
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[900],
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.storage, color: Colors.blue[400]),
                  const SizedBox(width: 12),
                  const Text(
                    'Database Connections',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedConnection != null)
                    IconButton(
                      onPressed: () async {
                        await _dbClient.disconnect(_selectedConnection!);
                        setState(() {
                          _selectedConnection = null;
                          _queryResults.clear();
                        });
                      },
                      icon: const Icon(Icons.disconnect, color: Colors.red),
                      tooltip: 'Disconnect',
                    ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Quick connect buttons
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _dbClient.isConnected('nocobase')
                              ? Colors.green
                              : Colors.grey[600]!,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'NocoBase (.233)',
                            style: TextStyle(
                              color: _dbClient.isConnected('nocobase')
                                  ? Colors.green
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (!_dbClient.isConnected('nocobase')) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nocobaseController,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              decoration: const InputDecoration(
                                hintText: 'user:pass:db',
                                hintStyle: TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _connectToNocobase,
                              child: const Text('Connect'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _dbClient.isConnected('memster')
                              ? Colors.green
                              : Colors.grey[600]!,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Memster (.250)',
                            style: TextStyle(
                              color: _dbClient.isConnected('memster')
                                  ? Colors.green
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (!_dbClient.isConnected('memster')) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _memsterController,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              decoration: const InputDecoration(
                                hintText: 'user:pass:db',
                                hintStyle: TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _connectToMemster,
                              child: const Text('Connect'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Query area
        if (_selectedConnection != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[850],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Query ($_selectedConnection)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _isExecuting ? null : _executeQuery,
                      icon: _isExecuting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow, size: 16),
                      label: Text(_isExecuting ? 'Executing...' : 'Execute'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                TextField(
                  controller: _queryController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Enter SQL query...',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
                
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      border: Border.all(color: Colors.red),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        
        // Results area
        Expanded(
          child: _queryResults.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      _selectedConnection == null
                          ? 'Connect to a database to start querying'
                          : 'Execute a query to see results',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ),
                )
              : Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Results (${_queryResults.length} rows)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              columns: _queryResults.first.keys
                                  .map((key) => DataColumn(
                                        label: Text(
                                          key,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ))
                                  .toList(),
                              rows: _queryResults
                                  .map((row) => DataRow(
                                        cells: row.values
                                            .map((value) => DataCell(
                                                  Text(
                                                    value?.toString() ?? 'NULL',
                                                    style: const TextStyle(color: Colors.white),
                                                  ),
                                                ))
                                            .toList(),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
