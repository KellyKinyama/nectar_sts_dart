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
///   LOG_HTTP_REQUESTS   — `stdout` (default) emits one JSON line per
///                         HTTP request to stdout. `stderr` emits to
///                         stderr. `off` / `false` / `0` / `none`
///                         disables per-request logging.
///
/// Example:
///   PORT=2000 VENDING_KEY_HEX=0123456789ABCDEF dart run bin/server.dart
library;

import 'dart:convert';
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
  final registryPath =
      (env['METER_REGISTRY_FILE'] ?? _defaultRegistryPath).trim();

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
  final TokenIssuer issuer = _buildIssuer(env, hsm);
  stdout.writeln('[info] hsm backend: ${issuer.name}');

  final tariffs = TariffBook.fromEnv(env);
  if (tariffs.isEmpty) {
    stdout.writeln(
      '[info] no tariff configured — requests must send "amount" '
      '(kWh). Set TARIFF_PRICE_PER_KWH+TARIFF_CURRENCY (or '
      'TARIFF_TABLE) to enable cash-amount requests.',
    );
  } else {
    final fb = tariffs.fallback;
    if (fb != null) {
      stdout.writeln(
        '[info] tariff fallback: ${fb.pricePerKwh} ${fb.currency}/kWh'
        '${fb.adminFee == 0 ? '' : ' (+${fb.adminFee} ${fb.currency} admin fee)'}',
      );
    }
    if (tariffs.byTariffIndex.isNotEmpty) {
      stdout.writeln(
        '[info] tariff table entries: ${tariffs.byTariffIndex.keys.join(", ")}',
      );
    }
  }

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
    issuer,
    bearerToken: bearer,
    log: log,
    registry: registry,
    tariffs: tariffs.isEmpty ? null : tariffs,
    logSink: _resolveLogSink(env),
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
    await issuer.close();
    if (useDb) await Database.close();
    exit(0);
  });
}

/// Pick a [TokenIssuer] based on `HSM_KIND` env (default `virtual`).
///
///   HSM_KIND=virtual  — in-process VirtualHsm (default).
///   HSM_KIND=prism    — remote Prism HSM via Thrift. Requires
///                       PRISM_HOST, PRISM_PORT, PRISM_REALM,
///                       PRISM_USERNAME, PRISM_PASSWORD. Currently a
///                       stub — every request will fail with
///                       NotImplementedException until the Dart
///                       Thrift client is in place.
TokenIssuer _buildIssuer(Map<String, String> env, VirtualHsm fallback) {
  final kind = (env['HSM_KIND'] ?? 'virtual').trim().toLowerCase();
  switch (kind) {
    case '':
    case 'virtual':
      return VirtualHsmIssuer(fallback);
    case 'prism':
      final host = env['PRISM_HOST']?.trim();
      final portStr = env['PRISM_PORT']?.trim();
      final realm = env['PRISM_REALM']?.trim();
      final username = env['PRISM_USERNAME']?.trim();
      final password = env['PRISM_PASSWORD'];
      if (host == null ||
          host.isEmpty ||
          portStr == null ||
          portStr.isEmpty ||
          realm == null ||
          realm.isEmpty ||
          username == null ||
          username.isEmpty ||
          password == null ||
          password.isEmpty) {
        throw StateError(
          'HSM_KIND=prism requires PRISM_HOST, PRISM_PORT, PRISM_REALM, '
          'PRISM_USERNAME, PRISM_PASSWORD.',
        );
      }
      final port = int.tryParse(portStr);
      if (port == null) {
        throw StateError('PRISM_PORT must be an integer, got: $portStr');
      }
      stderr.writeln(
        '[info] HSM_KIND=prism — connecting to $host:$port (realm=$realm, '
        'insecureTls=${(env['PRISM_INSECURE_TLS'] ?? 'true')}). '
        'Only class 0 / subclass 0 (electricity credit) is wired today.',
      );
      return PrismIssuer(
        PrismConfig(
          host: host,
          port: port,
          realm: realm,
          username: username,
          password: password,
          insecureTls:
              (env['PRISM_INSECURE_TLS'] ?? 'true').trim().toLowerCase() !=
                  'false',
        ),
      );
    default:
      throw StateError(
        'Unknown HSM_KIND="$kind" — expected "virtual" or "prism".',
      );
  }
}

/// Pick the HTTP-request log sink based on `LOG_HTTP_REQUESTS`:
///
///   stdout (default)  — one JSON line per request to stdout
///   stderr            — one JSON line per request to stderr
///   off / false / 0   — disabled (no-op sink, current pre-flag behavior)
LogSink? _resolveLogSink(Map<String, String> env) {
  final mode = (env['LOG_HTTP_REQUESTS'] ?? 'stdout').trim().toLowerCase();
  switch (mode) {
    case '':
    case 'off':
    case 'false':
    case '0':
    case 'none':
      return null;
    case 'stderr':
      return (entry) => stderr.writeln(jsonEncode(entry));
    case 'stdout':
    default:
      return (entry) => stdout.writeln(jsonEncode(entry));
  }
}
