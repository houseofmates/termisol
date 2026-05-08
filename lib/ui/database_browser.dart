import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/database_operations.dart';
import '../config/pkm_theme.dart';

/// Database browser widget for querying databases
class DatabaseBrowser extends StatefulWidget {
  final ServiceRegistry registry;
  final VoidCallback onClose;

  const DatabaseBrowser({
    super.key,
    required this.registry,
    required this.onClose,
  });

  @override
  State<DatabaseBrowser> createState() => _DatabaseBrowserState();
}

class _DatabaseBrowserState extends State<DatabaseBrowser> {
  late final DatabaseOperations _dbOps;
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _resultsScrollController = ScrollController();

  DatabaseType _selectedDatabase = DatabaseType.nocobase;
  String _nocobaseUsername = '';
  String _nocobasePassword = '';
  String _memsterUsername = '';
  String _memsterPassword = '';

  List<Map<String, dynamic>> _currentResults = [];
  List<String> _currentColumns = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Schema information
  DatabaseSchema? _currentSchema;
  String? _selectedTable;

  @override
  void initState() {
    super.initState();
    _dbOps = DatabaseOperations();
    _checkConnectionStatus();

    // Listen to database events
    _dbOps.events.listen((event) {
      if (mounted) {
        setState(() {
          // Update UI based on events
        });
      }
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _resultsScrollController.dispose();
    _dbOps.dispose();
    super.dispose();
  }

  Future<void> _checkConnectionStatus() async {
    final status = _dbOps.getConnectionStatus();
    if (mounted) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  Future<void> _connectToDatabase(DatabaseType database) async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final success = database == DatabaseType.nocobase
          ? await _dbOps.connectToNocoBase(
              username: _nocobaseUsername,
              password: _nocobasePassword,
            )
          : await _dbOps.connectToMemster(
              username: _memsterUsername,
              password: _memsterPassword,
            );

      if (success && mounted) {
        await _checkConnectionStatus();
        await _loadSchema(database);
        setState(() => _errorMessage = null);
      } else if (mounted) {
        setState(() => _errorMessage = 'Failed to connect to ${database.toString()}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Connection error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadSchema(DatabaseType database) async {
    try {
      final schema = await _dbOps.getSchema(database);
      if (mounted) {
        setState(() => _currentSchema = schema);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to load schema: $e');
      }
    }
  }

  Future<void> _executeQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final result = await _dbOps.executeQuery(
        database: _selectedDatabase,
        query: query,
      );

      if (mounted) {
        setState(() {
          _currentResults = result.rows;
          _currentColumns = result.columns;
          _errorMessage = result.success ? null : result.error;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Query error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadTableData(String tableName) async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final result = await _dbOps.getTableData(
        database: _selectedDatabase,
        tableName: tableName,
        limit: 100,
      );

      if (mounted) {
        setState(() {
          _currentResults = result.rows;
          _currentColumns = result.columns;
          _errorMessage = result.success ? null : result.error;
          _queryController.text = 'SELECT * FROM $tableName LIMIT 100;';
          _selectedTable = tableName;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Error loading table data: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildConnectionPanel() {
    final status = _dbOps.getConnectionStatus();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PkmTheme.popup,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Database Connections',
            style: TextStyle(
              color: PkmTheme.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: PkmTheme.fontUi,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'NocoBase: ${status[DatabaseType.nocobase]!.isActive ? 'Connected' : 'Disconnected'}\n'
            'Memster: ${status[DatabaseType.memster]!.isActive ? 'Connected' : 'Disconnected'}',
            style: TextStyle(
              color: PkmTheme.text,
              fontFamily: PkmTheme.fontUi,
            ),
          ),
          const SizedBox(height: 16),

          // NocoBase connection
          Text(
            'NocoBase',
            style: TextStyle(
              color: PkmTheme.text,
              fontWeight: FontWeight.bold,
              fontFamily: PkmTheme.fontUi,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Username',
                    hintStyle: TextStyle(color: PkmTheme.text.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: PkmTheme.background,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: PkmTheme.primary),
                    ),
                  ),
                  style: TextStyle(color: PkmTheme.text),
                  onChanged: (value) => _nocobaseUsername = value,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: TextStyle(color: PkmTheme.text.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: PkmTheme.background,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: PkmTheme.primary),
                    ),
                  ),
                  style: TextStyle(color: PkmTheme.text),
                  obscureText: true,
                  onChanged: (value) => _nocobasePassword = value,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isLoading ? null : () => _connectToDatabase(DatabaseType.nocobase),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PkmTheme.primary,
                  foregroundColor: PkmTheme.background,
                ),
                child: const Text('Connect'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Memster connection
          Text(
            'Memster',
            style: TextStyle(
              color: PkmTheme.text,
              fontWeight: FontWeight.bold,
              fontFamily: PkmTheme.fontUi,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Username',
                    hintStyle: TextStyle(color: PkmTheme.text.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: PkmTheme.background,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: PkmTheme.primary),
                    ),
                  ),
                  style: TextStyle(color: PkmTheme.text),
                  onChanged: (value) => _memsterUsername = value,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: TextStyle(color: PkmTheme.text.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: PkmTheme.background,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: PkmTheme.primary),
                    ),
                  ),
                  style: TextStyle(color: PkmTheme.text),
                  obscureText: true,
                  onChanged: (value) => _memsterPassword = value,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isLoading ? null : () => _connectToDatabase(DatabaseType.memster),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PkmTheme.primary,
                  foregroundColor: PkmTheme.background,
                ),
                child: const Text('Connect'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSchemaPanel() {
    if (_currentSchema == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: PkmTheme.popup,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Connect to a database to view schema',
          style: TextStyle(
            color: PkmTheme.text.withValues(alpha: 0.7),
            fontFamily: PkmTheme.fontUi,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PkmTheme.popup,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Schema - ${_selectedDatabase.toString()}',
            style: TextStyle(
              color: PkmTheme.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: PkmTheme.fontUi,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _currentSchema!.tables.length,
              itemBuilder: (context, index) {
                final table = _currentSchema!.tables[index];
                return ListTile(
                  title: Text(
                    table.name,
                    style: TextStyle(
                      color: PkmTheme.text,
                      fontFamily: PkmTheme.fontUi,
                    ),
                  ),
                  subtitle: Text(
                    '${table.columns.length} columns',
                    style: TextStyle(
                      color: PkmTheme.text.withValues(alpha: 0.7),
                      fontFamily: PkmTheme.fontUi,
                    ),
                  ),
                  onTap: () => _loadTableData(table.name),
                  selected: _selectedTable == table.name,
                  selectedTileColor: PkmTheme.primary.withValues(alpha: 0.1),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PkmTheme.popup,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SQL Query',
                style: TextStyle(
                  color: PkmTheme.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: PkmTheme.fontUi,
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<DatabaseType>(
                value: _selectedDatabase,
                dropdownColor: PkmTheme.popup,
                style: TextStyle(color: PkmTheme.text, fontFamily: PkmTheme.fontUi),
                items: DatabaseType.values.map((db) {
                  return DropdownMenuItem(
                    value: db,
                    child: Text(db.toString()),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null && mounted) {
                    setState(() => _selectedDatabase = value);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _queryController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter SQL query...',
              hintStyle: TextStyle(color: PkmTheme.text.withValues(alpha: 0.5)),
              filled: true,
              fillColor: PkmTheme.background,
              border: OutlineInputBorder(
                borderSide: BorderSide(color: PkmTheme.primary),
              ),
            ),
            style: TextStyle(color: PkmTheme.text, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton(
                onPressed: _isLoading ? null : _executeQuery,
                style: ElevatedButton.styleFrom(
                  backgroundColor: PkmTheme.primary,
                  foregroundColor: PkmTheme.background,
                ),
                child: const Text('Execute'),
              ),
              const SizedBox(width: 8),
              if (_isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PkmTheme.popup,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Results',
            style: TextStyle(
              color: PkmTheme.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: PkmTheme.fontUi,
            ),
          ),
          const SizedBox(height: 8),
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.withValues(alpha: 0.1),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: Colors.red,
                  fontFamily: PkmTheme.fontUi,
                ),
              ),
            ),
          if (_currentResults.isEmpty && _errorMessage == null)
            Text(
              'No results to display',
              style: TextStyle(
                color: PkmTheme.text.withValues(alpha: 0.7),
                fontFamily: PkmTheme.fontUi,
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                controller: _resultsScrollController,
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: DataTable(
                    columns: _currentColumns.map((col) => DataColumn(
                      label: Text(
                        col,
                        style: TextStyle(
                          color: PkmTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontFamily: PkmTheme.fontUi,
                        ),
                      ),
                    )).toList(),
                    rows: _currentResults.map((row) => DataRow(
                      cells: _currentColumns.map((col) => DataCell(
                        Text(
                          row[col]?.toString() ?? '',
                          style: TextStyle(
                            color: PkmTheme.text,
                            fontFamily: PkmTheme.fontUi,
                          ),
                        ),
                      )).toList(),
                    )).toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent closing when tapping the dialog
            child: Container(
              width: MediaQuery.of(context).size.width * 0.95,
              height: MediaQuery.of(context).size.height * 0.95,
              decoration: BoxDecoration(
                color: PkmTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PkmTheme.primary),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: PkmTheme.tabActiveBg,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Database Browser',
                          style: TextStyle(
                            color: PkmTheme.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: PkmTheme.fontUi,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: widget.onClose,
                          icon: Icon(Icons.close, color: PkmTheme.text),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          // Left panel - Connections and Schema
                          SizedBox(
                            width: 300,
                            child: Column(
                              children: [
                                Expanded(child: _buildConnectionPanel()),
                                const SizedBox(height: 16),
                                Expanded(child: _buildSchemaPanel()),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Right panel - Query and Results
                          Expanded(
                            child: Column(
                              children: [
                                _buildQueryPanel(),
                                const SizedBox(height: 16),
                                Expanded(child: _buildResultsPanel()),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}