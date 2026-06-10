/// HTTP server entry point — wraps [VirtualHsm] in a minimal
/// NectarAPI-compatible REST surface (electricity-credit tokens only).
///
/// Run with:
///   dart run nectar_sts_dart:server
/// or
///   dart run bin/server.dart
///
/// Configuration is loaded from `.env` in the current working directory
/// (see `lib/src/server/app_env.dart` and `.env.example`). Anything
/// set in the actual process environment overrides the file, so the
/// integration-test runner can still inject per-run values via
/// Symfony Process.
///
/// Environment variables:
///   PORT                — TCP port to bind (default 2000)
///   HOST                — bind address       (default 0.0.0.0)
///   VENDING_KEY_HEX     — 16-hex-char (8-byte) DES vending key.
///                         Defaults to the demo key used in `bin/demo.dart`.
///   NECTAR_API_TOKEN    — if set, every /v1/* request must carry
///                         `Authorization: Bearer <token>`.
///   VENDING_LOG_FILE    — path to a JSON audit log of every issued
///                         token. Defaults to `./vending.json`. Set
///                         to the literal string `:none:` to disable
///                         persistence (and the TID-collision check
///                         and the `GET /v1/tokens*` endpoints).
///   METER_REGISTRY_FILE — path to a JSON registry of provisioned
///                         meters keyed by serial. Defaults to
///                         `./meters.json`. Set to `:none:` to
///                         disable meter-registry endpoints and the
///                         `meter_serial` shortcut on POST /v1/tokens.
///   STS_DB_HOST         — if set, the audit log + meter registry
///                         are backed by the shared MySQL DB
///                         (`sts_vending`) the Laravel dashboard
///                         owns, overriding the JSON-file backends
///                         above. See `Database` for the full env
///                         list (HOST / PORT / DATABASE / USERNAME
///                         / PASSWORD / POOL_SIZE).
///
/// Example:
///   PORT=2000 VENDING_KEY_HEX=0123456789ABCDEF dart run bin/server.dart
library;

import 'dart:io';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:nectar_sts_dart/src/server/api_server.dart';
import 'package:nectar_sts_dart/src/server/app_env.dart';
import 'package:nectar_sts_dart/src/server/database.dart';
import 'package:nectar_sts_dart/src/server/db_meter_registry.dart';
import 'package:nectar_sts_dart/src/server/db_vending_log.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

const _defaultVendingKeyHex = '0123456789ABCDEF';
const _defaultLogPath = 'vending.json';
const _defaultRegistryPath = 'meters.json';

Future<void> main(List<String> args) async {
  final env = AppEnv.environment;
  if (AppEnv.envFilePath.isNotEmpty) {
    stdout.writeln('[info] loaded env file: ${AppEnv.envFilePath}');
  }
  final port = int.tryParse(env['PORT'] ?? '') ?? 2000;
  final host = env['HOST'] ?? '0.0.0.0';
  final keyHex = (env['VENDING_KEY_HEX'] ?? _defaultVendingKeyHex).trim();
  final bearer = env['NECTAR_API_TOKEN'];
  final logPath = (env['VENDING_LOG_FILE'] ?? _defaultLogPath).trim();
  final registryPath = (env['METER_REGISTRY_FILE'] ?? _defaultRegistryPath)
      .trim();

  if (keyHex == _defaultVendingKeyHex) {
    stderr.writeln(
      '[warn] VENDING_KEY_HEX not set — using built-in demo key. '
      'DO NOT USE IN PRODUCTION.',
    );
  }
  if (bearer == null || bearer.isEmpty) {
    stderr.writeln(
      '[warn] NECTAR_API_TOKEN not set — API is OPEN. '
      'Anyone who can reach $host:$port can mint tokens.',
    );
  }

  final hsm = VirtualHsm(VendingCommonDesKey(parseHexKey(keyHex)));

  final useDb = Database.isConfigured;
  final VendingLogStore? log;
  final MeterStore? registry;

  if (useDb) {
    stdout.writeln(
      '[info] STS_DB_HOST is set — using MySQL-backed registry + log '
      '(shared with the Laravel sts-vending dashboard). JSON file '
      'paths are IGNORED in DB mode.',
    );
    final dbRegistry = DbMeterRegistry();
    final dbLog = DbVendingLog();
    await dbRegistry.refreshCount();
    await dbLog.refreshCount();
    registry = dbRegistry;
    log = dbLog;
    stdout.writeln(
      '[info] db registry: ${dbRegistry.length} meter(s) currently in DB',
    );
    stdout.writeln(
      '[info] db vending log: ${dbLog.length} prior issue(s) in DB',
    );
  } else {
    if (logPath == ':none:') {
      log = null;
      stderr.writeln(
        '[warn] VENDING_LOG_FILE=:none: — audit log + TID-collision '
        'check are DISABLED.',
      );
    } else {
      final fileLog = VendingLog.loadOrCreate(logPath);
      log = fileLog;
      stdout.writeln(
        '[info] vending log: ${File(logPath).absolute.path} '
        '(${fileLog.length} prior issue(s) loaded)',
      );
    }

    if (registryPath == ':none:') {
      registry = null;
      stderr.writeln(
        '[warn] METER_REGISTRY_FILE=:none: — meter-registry endpoints '
        'and the meter_serial shortcut are DISABLED.',
      );
    } else {
      final fileRegistry = MeterRegistry.loadOrCreate(registryPath);
      registry = fileRegistry;
      stdout.writeln(
        '[info] meter registry: ${File(registryPath).absolute.path} '
        '(${fileRegistry.length} meter(s) loaded)',
      );
    }
  }

  final handler = buildApiHandler(
    hsm,
    bearerToken: bearer,
    log: log,
    registry: registry,
  );

  final server = await shelf_io.serve(handler, host, port);
  server.autoCompress = true;

  stdout.writeln('nectar_sts_dart HTTP server');
  stdout.writeln('  listening on http://${server.address.host}:${server.port}');
  stdout.writeln('  routes:');
  stdout.writeln('    GET    /healthz');
  stdout.writeln('    POST   /v1/tokens');
  stdout.writeln('    GET    /v1/tokens[?iin=&iain=]');
  stdout.writeln('    GET    /v1/tokens/{tokenNo}');
  stdout.writeln('    POST   /v1/tokens/{tokenNo}');
  stdout.writeln('    POST   /v1/meters');
  stdout.writeln('    GET    /v1/meters');
  stdout.writeln('    GET    /v1/meters/{serial}');
  stdout.writeln('    DELETE /v1/meters/{serial}');

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nshutting down...');
    await server.close(force: true);
    if (useDb) await Database.close();
    exit(0);
  });
}
