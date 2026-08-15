import sys

def replace_function(content, start_marker, end_marker, new_middle):
    # Find the start and end markers
    start_idx = content.find(start_marker)
    if start_idx == -1:
        return content
    # We want to replace from the start_marker to the end_marker (exclusive of end_marker? Actually we want to keep the end_marker as the start of the next part)
    # We'll replace from start_idx to the index of end_marker (which is the start of the end marker) with start_marker + new_middle + end_marker
    end_idx = content.find(end_marker, start_idx + len(start_marker))
    if end_idx == -1:
        return content
    return content[:start_idx] + start_marker + new_middle + end_marker + content[end_idx + len(end_marker):]

with open('lib/core/robust_error_handler.dart.backup', 'r') as f:
    backup = f.read()

# Define the new middle for _persistError
new_persist_middle = '''
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
'''

# Define the new middle for _loadErrorHistory
new_load_middle = '''
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
'''

# Replace the _persistError function
# The start marker is the line with the function signature and the opening brace.
# We'll use: "Future<void> _persistError(ErrorReport report) async {" as the start marker and the next "}" that is at the same indentation level? 
# Instead, we'll use the entire function block from the comment to the end of the function, but we don't know the exact end.
# We'll use a different approach: replace between the two comments that are unique.

# We know the function is between the comment "/// persist error to disk" and the comment "/// load error history from disk"
# But note: there is a blank line and the function signature.

# Let's do: from the line "/// persist error to disk" to the line "/// load error history from disk" (exclusive of the latter) and replace the entire block.

# We'll split by lines and then find the lines.

lines = backup.splitlines(keepends=True)

# Find the index of the line that is exactly "/// persist error to disk"
start_persist = None
for i, line in enumerate(lines):
    if line.strip() == '/// persist error to disk':
        start_persist = i
        break

# Find the index of the line that is exactly "/// load error history from disk" after start_persist
end_persist = None
for i in range(start_persist + 1, len(lines)):
    if line.strip() == '/// load error history from disk':
        end_persist = i
        break

# If we found both, replace from start_persist to end_persist-1 with the new function lines for persist.
if start_persist is not None and end_persist is not None:
    new_persist_lines = [
        '/// persist error to disk\n',
        '  Future<void> _persistError(ErrorReport report) async {',
        new_persist_middle,
        '  }\n'
    ]
    lines[start_persist:end_persist] = new_persist_lines

# Now find the _loadErrorHistory function: from "/// load error history from disk" to the next function comment or class or end of file.
start_load = None
for i, line in enumerate(lines):
    if line.strip() == '/// load error history from disk':
        start_load = i
        break

# Find the end: the next line that starts with '/// ' (and is not the same as the start) or 'class ' or end of file.
end_load = None
for i in range(start_load + 1, len(lines)):
    stripped = lines[i].strip()
    if stripped.startswith('/// ') or stripped.startswith('class '):
        end_load = i
        break
else:
    end_load = len(lines)

if start_load is not None and end_load is not None:
    new_load_lines = [
        '/// load error history from disk\n',
        '  Future<void> _loadErrorHistory() async {',
        new_load_middle,
        '  }\n'
    ]
    lines[start_load:end_load] = new_load_lines

# Join the lines back
new_backup = ''.join(lines)

# Write to the main file
with open('lib/core/robust_error_handler.dart', 'w') as f:
    f.write(new_backup)

print("File updated successfully")
