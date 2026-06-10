/// Server-boundary abstraction over "something that turns a
/// flat-Map token request into an issued [Token]".
///
/// Two implementations:
///
///   - [VirtualHsmIssuer] — wraps a [VirtualHsm]. Key derivation
///     (DKGA-02/04) and token encryption both run in this Dart
///     process. Vending key lives in plain memory.
///   - [PrismIssuer] — talks to a remote Prism HSM over Apache
///     Thrift (binary protocol + framed transport over TLS),
///     mirroring the upstream Java `PrismClientFacade`. Today only
///     class 0 / subclass 0 (`TransferElectricityCreditToken`) is
///     wired through to a Prism `issueCreditToken` call; everything
///     else throws [NotImplementedException].
library;

import 'dart:async';

import '../base/bit_string.dart';
import '../domain/amount.dart';
import '../domain/base_date.dart';
import '../domain/token_identifier.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../hsm/hsm.dart';
import '../hsm/virtual_hsm_dispatch.dart';
import '../prism/thrift_framed_transport.dart';
import '../prism/token_api_client.dart' as prism;
import '../token/class0_tokens.dart';
import '../token/token.dart';

/// Anything that can mint and decode tokens for the HTTP API.
///
/// Both methods take the same flat `Map<String, dynamic>` param
/// shape that the upstream NectarAPI uses — see [VirtualHsmParams]
/// for the canonical key names.
abstract class TokenIssuer {
  /// Short identifier for log / health output (e.g. "VirtualHsm").
  String get name;

  /// Issue a token from a flat param map. Returns the issued
  /// [Token] with `tokenNo` populated.
  FutureOr<Token> generateToken(String requestId, Map<String, dynamic> params);

  /// Decode a previously-issued 20-digit token using the same
  /// params that were used to mint it.
  FutureOr<Token> decodeToken(
    String requestId,
    String tokenNo,
    Map<String, dynamic> params,
  );

  /// Liveness probe for the underlying backend. The HTTP layer
  /// surfaces this on `GET /v1/health/backend` — a healthy result
  /// returns 200, an unhealthy one returns 503. Default impl just
  /// reports the issuer name; remote-backed issuers should override.
  FutureOr<Map<String, Object?>> checkBackend() =>
      {'ok': true, 'backend': name};
}

/// In-process issuer: derives the decoder key and runs the cipher
/// here in Dart via [VirtualHsm] + the [VirtualHsmDispatch]
/// extension methods.
class VirtualHsmIssuer implements TokenIssuer {
  final VirtualHsm hsm;

  VirtualHsmIssuer(this.hsm);

  @override
  String get name => hsm.name;

  @override
  Token generateToken(String requestId, Map<String, dynamic> params) =>
      hsm.generateToken(requestId, params);

  @override
  Token decodeToken(
    String requestId,
    String tokenNo,
    Map<String, dynamic> params,
  ) =>
      hsm.decodeToken(requestId, tokenNo, params);

  @override
  Future<Map<String, Object?>> checkBackend() async => {
        'ok': true,
        'backend': name,
      };
}

/// Connection parameters for a remote Prism HSM. Mirrors the
/// upstream Java `PrismClientFacade(host, port, realm, username,
/// password, connector)` ctor.
class PrismConfig {
  final String host;
  final int port;
  final String realm;
  final String username;
  final String password;

  /// When `true`, the Thrift TLS socket should skip server-cert
  /// validation. The Java reference (`PrismHSMConnector.getClient`)
  /// installs a trust-all `X509TrustManager`, i.e. this defaults to
  /// `true` for parity — flip it off in production once a proper
  /// trust store is wired.
  final bool insecureTls;

  /// Per-call timeout for the TLS connect. `null` means "use OS
  /// default" (effectively unbounded, matching the Java reference
  /// which sets `socket.setSoTimeout(0)`).
  final Duration? connectTimeout;

  const PrismConfig({
    required this.host,
    required this.port,
    required this.realm,
    required this.username,
    required this.password,
    this.insecureTls = true,
    this.connectTimeout,
  });
}

/// Prism-HSM-backed issuer.
///
/// One TLS connection per request — matches the Java reference which
/// re-authenticates per call. If profiling shows that hurts, we can
/// move to a connection pool later.
class PrismIssuer implements TokenIssuer {
  final PrismConfig config;

  final SocketFactory? _socketFactoryOverride;

  PrismIssuer(this.config) : _socketFactoryOverride = null;

  /// Test-only ctor: inject an in-process plain-TCP factory so the
  /// fake Thrift server in `test/prism/` doesn't need certificates.
  PrismIssuer.forTesting(this.config, SocketFactory socketFactory)
      : _socketFactoryOverride = socketFactory;

  @override
  String get name => 'PrismIssuer(${config.host}:${config.port})';

  SocketFactory get _factory =>
      _socketFactoryOverride ??
      tlsSocketFactory(
        host: config.host,
        port: config.port,
        insecureTls: config.insecureTls,
        timeout: config.connectTimeout,
      );

  @override
  Future<Token> generateToken(
    String requestId,
    Map<String, dynamic> params,
  ) async {
    final tokenClass = params[VirtualHsmParams.tokenClass]?.toString();
    final subclass = params[VirtualHsmParams.tokenSubclass]?.toString() ?? '0';
    if (tokenClass != '0' || subclass != '0') {
      throw NotImplementedException(
        'PrismIssuer.generateToken: only class 0 / subclass 0 '
        '(electricity credit) is wired through to Prism today. '
        'Got class=$tokenClass subclass=$subclass.',
      );
    }

    final meterConfig = _meterConfigFromParams(params);
    final amountKwh = _requiredDouble(params, VirtualHsmParams.amount);
    final tokenTime = _tokenTimeSeconds(params);

    final client = await prism.TokenApiClient.connect(_factory);
    try {
      final accessToken = await client.signInWithPassword(
        messageId: requestId,
        realm: config.realm,
        username: config.username,
        password: config.password,
      );

      // Prism expects scaled units: ×10 for kWh credit subclass 0.
      // Currency-credit variants (subclasses 4–7) would use ×100000
      // but they're not wired here.
      final scaled = amountKwh * 10;
      final tokens = await client.issueCreditToken(
        messageId: requestId,
        accessToken: accessToken,
        meterConfig: meterConfig,
        subclass: 0,
        transferAmount: scaled,
        tokenTime: tokenTime,
        flags: prism.TokenIssueFlags.externalClock,
      );

      final picked = _pickElectricityCredit(tokens);
      return _toDartToken(requestId, picked, params);
    } finally {
      await client.close();
    }
  }

  @override
  Future<Token> decodeToken(
    String requestId,
    String tokenNo,
    Map<String, dynamic> params,
  ) async {
    final tokenClass = params[VirtualHsmParams.tokenClass]?.toString();
    final subclass = params[VirtualHsmParams.tokenSubclass]?.toString() ?? '0';
    if (tokenClass != '0' || subclass != '0') {
      throw NotImplementedException(
        'PrismIssuer.decodeToken: only class 0 / subclass 0 '
        '(electricity credit) is wired through to Prism today. '
        'Got class=$tokenClass subclass=$subclass.',
      );
    }

    final meterConfig = _meterConfigFromParams(params);
    final client = await prism.TokenApiClient.connect(_factory);
    try {
      final accessToken = await client.signInWithPassword(
        messageId: requestId,
        realm: config.realm,
        username: config.username,
        password: config.password,
      );
      final result = await client.verifyToken(
        messageId: requestId,
        accessToken: accessToken,
        meterConfig: meterConfig,
        tokenDec: tokenNo,
      );
      if (!result.isValid) {
        throw NotImplementedException(
          'PrismIssuer.decodeToken: Prism rejected the token '
          '(validationResult="${result.validationResult}").',
        );
      }
      final pt = result.token;
      if (pt == null) {
        throw const NotImplementedException(
          'PrismIssuer.decodeToken: Prism returned isValid but no '
          'decoded Token struct.',
        );
      }
      return _toDartToken(requestId, pt, params);
    } finally {
      await client.close();
    }
  }

  @override
  Future<Map<String, Object?>> checkBackend() async {
    final stopwatch = Stopwatch()..start();
    try {
      final client = await prism.TokenApiClient.connect(_factory);
      try {
        final echo = await client.ping(sleepMs: 0, echo: 'nectar-sts');
        stopwatch.stop();
        return {
          'ok': true,
          'backend': name,
          'echo': echo,
          'roundTripMs': stopwatch.elapsedMilliseconds,
        };
      } finally {
        await client.close();
      }
    } catch (e) {
      stopwatch.stop();
      return {
        'ok': false,
        'backend': name,
        'error': e.toString(),
        'roundTripMs': stopwatch.elapsedMilliseconds,
      };
    }
  }

  // ---- helpers ----------------------------------------------------

  prism.MeterConfigIn _meterConfigFromParams(Map<String, dynamic> params) {
    final drn = _requiredString(
      params,
      VirtualHsmParams.decoderReferenceNumber,
    );
    final eaCode = _eaCode(params);
    final sgc = int.parse(
      _requiredString(params, VirtualHsmParams.supplyGroupCode),
    );
    final krn = int.parse(
      _requiredString(params, VirtualHsmParams.keyRevisionNo),
    );
    final ti = int.parse(_requiredString(params, VirtualHsmParams.tariffIndex));
    final ken = int.tryParse(
          (params[VirtualHsmParams.keyExpiryNumberHighOrder] ?? '0').toString(),
        ) ??
        0;
    return prism.MeterConfigIn(
      drn: drn,
      ea: eaCode,
      tct: 1, // NumericKeypad — same default as the Java facade.
      sgc: sgc,
      krn: krn,
      ti: ti,
      ken: ken,
    );
  }

  int _eaCode(Map<String, dynamic> params) {
    final raw = (params[VirtualHsmParams.encryptionAlgorithm] ?? 'sta')
        .toString()
        .toLowerCase();
    switch (raw) {
      case 'sta':
        return int.parse(EncryptionAlgorithmCode.sta.name);
      case 'dea':
        return int.parse(EncryptionAlgorithmCode.dea.name);
      case 'misty1':
        return int.parse(EncryptionAlgorithmCode.misty1.name);
      default:
        throw NotImplementedException(
          'PrismIssuer: unknown encryption_algorithm "$raw"',
        );
    }
  }

  /// Resolve `tokenTime` (epoch seconds). Honor `token_id` if the
  /// request carries one; otherwise use now, matching the Java
  /// facade's `Instant.now().getEpochSecond()`.
  int _tokenTimeSeconds(Map<String, dynamic> params) {
    final raw = params[VirtualHsmParams.tokenId];
    DateTime when;
    if (raw is DateTime) {
      when = raw.toUtc();
    } else if (raw is String && raw.isNotEmpty) {
      when = DateTime.parse(raw).toUtc();
    } else {
      when = DateTime.now().toUtc();
    }
    return when.millisecondsSinceEpoch ~/ 1000;
  }

  prism.PrismToken _pickElectricityCredit(List<prism.PrismToken> tokens) {
    for (final t in tokens) {
      if (t.description == 'Credit:Electricity') return t;
    }
    if (tokens.isNotEmpty) return tokens.first;
    throw const NotImplementedException(
      'PrismIssuer: Prism returned no tokens for issueCreditToken',
    );
  }

  Token _toDartToken(
    String requestId,
    prism.PrismToken pt,
    Map<String, dynamic> params,
  ) {
    final out = TransferElectricityCreditToken(requestId);
    out.encryptedTokenBitString = TokenTransposition.tokenNoToBinary66(
      pt.tokenDec,
    );
    final scaled = double.tryParse(pt.scaledAmount);
    if (scaled != null) {
      out.amountPurchased = Amount(scaled);
    }
    final baseDate = _baseDate(params);
    out.tokenIdentifier = TokenIdentifier.fromBitString(
      BitString.fromValue(pt.tid & 0xFFFFFF, 24),
      baseDate: baseDate,
    );
    return out;
  }

  BaseDate _baseDate(Map<String, dynamic> params) {
    switch ((params[VirtualHsmParams.baseDate] ?? '1993').toString()) {
      case '2014':
      case '14':
        return BaseDate.date2014;
      case '2035':
      case '35':
        return BaseDate.date2035;
      default:
        return BaseDate.date1993;
    }
  }

  static String _requiredString(Map<String, dynamic> params, String key) {
    final v = params[key];
    if (v == null) {
      throw NotImplementedException('PrismIssuer: missing param "$key"');
    }
    return v.toString();
  }

  static double _requiredDouble(Map<String, dynamic> params, String key) {
    final v = params[key];
    if (v is num) return v.toDouble();
    if (v is String) {
      final parsed = double.tryParse(v);
      if (parsed != null) return parsed;
    }
    throw NotImplementedException(
      'PrismIssuer: param "$key" must be numeric, got: $v',
    );
  }
}
