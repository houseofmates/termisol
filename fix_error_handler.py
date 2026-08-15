import sys
import re

def replace_function(content, start_comment, new_func):
    # Pattern to find the function: from the line with the start_comment to the line before the next function (which starts with '/// ' or 'class ' or end of file)
    # We'll split by lines and iterate.
    lines = content.splitlines(keepends=True)
    in_func = False
    func_start = None
    for i, line in enumerate(lines):
        if line.strip() == start_comment:
            in_func = True
            func_start = i
        if in_func and line.strip().startswith('/// ') and line.strip() != start_comment:
            func_end = i
            break
        if in_func and line.strip().startswith('class '):
            func_end = i
            break
    else:
        func_end = len(lines)
    if func_start is None:
        return content
    # Replace the lines from func_start to func_end-1 with the new function
    new_lines = new_func.splitlines(keepends=True)
    lines[func_start:func_end] = new_lines
    return ''.join(lines)

# Read the backup file
with open('lib/core/robust_error_handler.dart.backup', 'r') as f:
    backup_content = f.read()

# Define the new _persistError function
new_persist = '''  /// persist error to disk
  Future<void> _persistError(ErrorReport report) async {
    try {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      final errorFile = File('${directory.path}/termisol_errors.jsonl');

      await errorFile.writeAsString(
        '${jsonEncode(report.toJson())}\\n',
        mode: FileMode.append,
      );
    } catch (e) {
      debugPrint('Failed to persist error: $e');
    }
  }'''

# Define the new _loadErrorHistory function
new_load = '''  /// load error history from disk
  Future<void> _loadErrorHistory() async {
    try {
      final directory = await getApplicationSupportDirectory();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final errorFile = File('${directory.path}/termisol_errors.jsonl');

      if (await errorFile.exists()) {
        final lines = await errorFile.readAsLines();
        for (final line in lines.take(100)) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            continue;
          }
          if (!trimmed.startsWith('{')) {
            debugPrint('Skipping non-JSON line: ${trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed}');
            continue;
          }
          // Load last 100 errors
          try {
            final json = jsonDecode(trimmed) as Map<String, dynamic>;
            final report = ErrorReport.fromJson(json);
            _errorHistory.add(report);
          } catch (e) {
            debugPrint('Failed to parse error history: $e');
            debugPrint('Invalid line: ${trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed}');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load error history: $e');
    }
  }'''

# Replace the functions
new_content = replace_function(backup_content, '/// persist error to disk', new_persist)
new_content = replace_function(new_content, '/// load error history from disk', new_load)

# Write the new content to the main file
with open('lib/core/robust_error_handler.dart', 'w') as f:
    f.write(new_content)

print("File updated successfully")
