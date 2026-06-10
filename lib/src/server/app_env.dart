/// Minimal `.env` loader + merged env map.
///
/// Reads `.env` from the current working directory once at first use,
/// then layers `Platform.environment` on top so anything passed by
/// the parent process (e.g. the Laravel integration test runner which
/// spawns this server with explicit env vars via Symfony Process)
/// always wins over the file.
///
/// We rolled our own instead of pulling in a package because the
/// format we actually need is trivial:
///   - lines of the form `KEY=value`
///   - blank lines and `# ...` comments ignored
///   - optional surrounding single or double quotes stripped
///   - no variable expansion, no multiline values
library;

import 'dart:io';

class AppEnv {
  AppEnv._();

  static Map<String, String>? _cached;

  /// Path of the `.env` file actually used (for diagnostics). Empty
  /// when no file was found.
  static String envFilePath = '';

  /// Merged env map: file values first, then [Platform.environment]
  /// merged on top (so parent-process env wins).
  static Map<String, String> get environment {
    return _cached ??= _build();
  }

  /// Convenience accessor.
  static String? get(String key) => environment[key];

  /// Forces a reload on next access. Used by tests.
  static void reset() {
    _cached = null;
    envFilePath = '';
  }

  static Map<String, String> _build() {
    final merged = <String, String>{};

    final candidates = <String>[
      // Project root when invoked as `dart run bin/server.dart`.
      '.env',
      // Walk up one level just in case the user runs the binary from
      // a subdirectory.
      '..${Platform.pathSeparator}.env',
    ];
    for (final path in candidates) {
      final file = File(path);
      if (!file.existsSync()) continue;
      envFilePath = file.absolute.path;
      _parseInto(merged, file.readAsLinesSync());
      break;
    }

    // Platform.environment wins so explicit `PORT=18787 dart run …`
    // and the integration-test spawn (which sets every key
    // explicitly) override any stale file value.
    merged.addAll(Platform.environment);
    return merged;
  }

  static void _parseInto(Map<String, String> out, List<String> lines) {
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      // Strip surrounding quotes if both ends match.
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      out[key] = value;
    }
  }
}
