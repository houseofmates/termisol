import re

def replace_function_body(content, func_sig, new_body):
    """
    Replace the body of the function with the given signature.
    func_sig: the function signature line including the opening brace, e.g., "Future<void> _persistError(ErrorReport report) async {"
    new_body: the new body string (should include the indentation for the lines inside the function).
    We'll find the function signature, then find the matching closing brace by counting braces.
    """
    # Find the start of the function signature
    start_idx = content.find(func_sig)
    if start_idx == -1:
        return content
    # The start of the body is after the opening brace of the function signature.
    # We assume the signature ends with '{' (it does).
    body_start = start_idx + len(func_sig)  # points to the character after the '{'
    # Now we need to find the matching closing brace.
    brace_count = 1
    i = body_start
    while i < len(content) and brace_count > 0:
        if content[i] == '{':
            brace_count += 1
        elif content[i] == '}':
            brace_count -= 1
        i += 1
    if brace_count != 0:
        # Unbalanced braces
        return content
    body_end = i  # points to the character after the matching '}'
    # Replace the body
    new_content = content[:body_start] + new_body + content[body_end:]
    return new_content

with open('lib/core/robust_error_handler.dart.backup', 'r') as f:
    backup = f.read()

# Define the new body for _persistError
new_persist_body = '''
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

# Define the new body for _loadErrorHistory
new_load_body = '''
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

# Replace the _persistError function body
persist_sig = 'Future<void> _persistError(ErrorReport report) async {'
content = replace_function_body(backup, persist_sig, new_persist_body)

# Replace the _loadErrorHistory function body
load_sig = 'Future<void> _loadErrorHistory() async {'
content = replace_function_body(content, load_sig, new_load_body)

# Write to the main file
with open('lib/core/robust_error_handler.dart', 'w') as f:
    f.write(content)

print("File updated successfully")
