/// Singleton, pooled MySQL access for the optional DB-backed meter
/// registry and vending audit log.
///
/// **Background.** When the Dart token server runs standalone it uses
/// JSON files (`meters.json`, `vending.json`) for persistence. When it
/// runs alongside the Laravel `sts-vending` dashboard it can be
/// pointed at the same MySQL database so both layers see the same
/// meters and tokens. This file is the shared connection layer for
/// the DB-backed mode.
///
/// **Why pooled.** The Laravel dashboard is on the same DB. A
/// connect/auth/disconnect storm from the Dart server would crowd it
/// out. We open one pool of up to [defaultPoolSize] connections and
/// hand them out via [Database.connection]. Per-query callers should
/// call [Database.release] (a no-op) to keep "I'm done with this
/// connection" visible in code while the pool stays alive.
///
/// **Configuration** (env vars; defaults match the Laravel `.env` from
/// `C:\www\web\laravel\sts-vending` when run on the same WAMP box):
///
///   STS_DB_HOST       127.0.0.1
///   STS_DB_PORT       3306
///   STS_DB_DATABASE   sts_vending
///   STS_DB_USERNAME   root
///   STS_DB_PASSWORD   (empty)
///   STS_DB_POOL_SIZE  5
///
/// Pattern lifted from `C:\www\dart\dart-ari\lib\ari\api\database.dart`.
library;

import 'dart:io' show Platform;

import 'package:eloquent/eloquent.dart';

class Database {
  /// Pool size used when [STS_DB_POOL_SIZE] is not provided in the env.
  /// Tuned conservatively so we don't crowd out the Laravel dashboard.
  static const int defaultPoolSize = 5;

  static Manager? _manager;
  static Connection? _connection;
  static Future<Connection>? _initFuture;

  /// Returns the process-wide pooled [Connection]. The first call
  /// lazily builds the [Manager] with `pool: true` and a small
  /// `poolsize`. All subsequent calls reuse it.
  static Future<Connection> connection() async {
    if (_connection != null) return _connection!;
    return _initFuture ??= _initialize();
  }

  /// Returns the singleton [Manager] (after [connection] has been
  /// called at least once). Useful for callers that need additional
  /// query builders or schema operations through the same pool.
  static Manager? get manager => _manager;

  /// `true` when the server has any DB config in its environment. The
  /// `bin/server.dart` entry point uses this to decide between
  /// JSON-file and DB-backed registry / vending log.
  static bool get isConfigured =>
      (Platform.environment['STS_DB_HOST'] ?? '').trim().isNotEmpty;

  static Future<Connection> _initialize() async {
    final env = Platform.environment;
    final host = (env['STS_DB_HOST'] ?? '127.0.0.1').trim();
    final port = (env['STS_DB_PORT'] ?? '3306').trim();
    final db = (env['STS_DB_DATABASE'] ?? 'sts_vending').trim();
    final user = (env['STS_DB_USERNAME'] ?? 'root').trim();
    final pass = env['STS_DB_PASSWORD'] ?? '';
    final poolSize = _resolvePoolSize(env);
    final sslmode = (env['STS_DB_SSLMODE'] ?? '').trim();

    final manager = Manager();
    final config = <String, dynamic>{
      'driver': 'mysql',
      'host': host,
      'port': port,
      'database': db,
      'username': user,
      'password': pass,
      // Eloquent forwards these into the underlying MySQL DSN, which
      // switches mysql_client to MySQLConnectionPool. Connections
      // inside the pool are kept alive and reused across queries.
      'pool': true,
      'poolsize': poolSize,
      'allowreconnect': true,
      'application_name': 'nectar_sts_dart',
    };
    // mysql_dart refuses caching_sha2_password over a plaintext
    // socket. Setting STS_DB_SSLMODE=require flips the underlying
    // client into TLS mode (which MySQL 8/9 enables by default
    // with auto-generated server certs).
    if (sslmode.isNotEmpty) {
      config['sslmode'] = sslmode;
    }
    manager.addConnection(config);
    manager.setAsGlobal();

    final conn = await manager.connection();
    _manager = manager;
    _connection = conn;
    return conn;
  }

  static int _resolvePoolSize(Map<String, String> env) {
    final raw = env['STS_DB_POOL_SIZE'];
    if (raw == null) return defaultPoolSize;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) return defaultPoolSize;
    return parsed;
  }

  /// Per-query callers used to call `db.disconnect()` after every
  /// statement. With pooling that would close the pool — exactly what
  /// we don't want. Use this no-op everywhere instead so the intent
  /// ("I'm done with the connection") is preserved while the pool
  /// stays alive.
  static Future<void> release(Connection _) async {
    // Intentionally no-op. The connection lives inside the pool.
  }

  /// Graceful shutdown hook (call once on application exit). Tests
  /// and CLI tools can invoke this to free the underlying socket(s).
  static Future<void> close() async {
    final conn = _connection;
    _connection = null;
    _manager = null;
    _initFuture = null;
    if (conn != null) {
      try {
        await conn.disconnect();
      } catch (_) {
        // Best effort.
      }
    }
  }
}
