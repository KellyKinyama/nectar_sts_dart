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
import 'dart:collection';
import 'dart:io';

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
  FutureOr<Map<String, Object?>> checkBackend() => {
        'ok': true,
        'backend': name,
      };

  /// Per-node operational status. The HTTP layer surfaces this on
  /// `GET /v1/status/nodes`. Each entry carries an arbitrary `info`
  /// map (host, version, uptime, …) plus a list of active alerts
  /// (`{eCode, eMsg}`). Default impl returns a single synthetic
  /// entry for in-process backends; remote-backed issuers should
  /// override to enumerate their cluster.
  FutureOr<List<Map<String, Object?>>> getNodeStatus() async => [
        {
          'info': {'backend': name},
          'alerts': const <Map<String, Object?>>[],
        },
      ];

  /// Issue the full Key Change Token (KCT) bundle migrating a meter
  /// to a new SGC / KRN / TI. The HTTP layer surfaces this on
  /// `POST /v1/tokens/key-change`. Returns the raw per-token
  /// `{tokenNo, subclass, description}` records — STA/DEA returns
  /// 2 entries (1st + 2nd section), MISTY1 returns 4 (1st…4th).
  /// All entries are part of one atomic set and must be applied
  /// together.
  ///
  /// Default impl throws — only remote-backed issuers (Prism) are
  /// wired today; the in-process [VirtualHsmIssuer] would have to
  /// reproduce Prism's atomic bundling, which is out of MVP scope.
  FutureOr<List<Map<String, Object?>>> issueKeyChangeTokens(
    String requestId,
    Map<String, dynamic> params,
  ) =>
      throw NotImplementedException(
        '$name does not support atomic Key Change Token issuance.',
      );

  /// Issue a Class 2 Management/Secondary-Engineering (MSE) token.
  /// [subclass] picks the operation (`PrismHSMConnector.MseToken`):
  /// 0=SetMaximumPowerLimit, 1=ClearCredit, 2=SetTariffRate,
  /// 5=ClearTamper, 10=SetFlag, etc. [transferAmount] is the
  /// already-resolved numeric payload (kW for max-power, encoded
  /// flag-word for SetFlag, 0 for ClearCredit/ClearTamper).
  ///
  /// Returns the per-token `{tokenNo, subclass, description}`
  /// records Prism produced — typically one for STA/DEA and two
  /// for MISTY1.
  FutureOr<List<Map<String, Object?>>> issueMseToken(
    String requestId,
    int subclass,
    double transferAmount,
    Map<String, dynamic> params,
  ) =>
      throw NotImplementedException(
        '$name does not support MSE token issuance.',
      );

  /// Issue a Class 1 / 3 Non-Meter-Specific Engineering (NMSE) test
  /// token. The token is independent of any meter's keys; the
  /// [control] word picks the diagnostic routine
  /// (`PrismHSMConnector.NMseType`: 0=Primary, 1=TestLoadSwitch,
  /// 2=TestInformationDisplay, …, 32=InitiateMeterTest) and
  /// [manufacturerCode] gates it to a specific meter make.
  ///
  /// Returns one token record
  /// `{tokenNo, subclass, control, manufacturerCode, description,
  /// tokenHex}` — unlike MSE/KCT this is never a bundle.
  FutureOr<Map<String, Object?>> issueMeterTestToken(
    String requestId,
    int subclass,
    int control,
    int manufacturerCode,
  ) =>
      throw NotImplementedException(
        '$name does not support NMSE meter-test token issuance.',
      );

  /// Issue a Class 0 currency-credit token (subclasses 4–7:
  /// `ElectricityCurrency`, `WaterCurrency`, `GasCurrency`,
  /// `TimeCurrency` per `PrismHSMConnector.CreditTokenType`). Wire
  /// shape matches `issueCreditToken` but the `transferAmount` field
  /// is multiplied by 100000 instead of 10 — caller passes the
  /// human-readable currency amount; the implementer does the scale.
  ///
  /// Returns a flat `{tokenNo, subclass, description, scaledAmount}`
  /// list (Prism may return >1 entry for MISTY1).
  FutureOr<List<Map<String, Object?>>> issueCurrencyCreditToken(
    String requestId,
    int subclass,
    Map<String, dynamic> params,
  ) =>
      throw NotImplementedException(
        '$name does not support currency-credit token issuance.',
      );

  /// Idempotency replay: re-fetch the tokens previously issued for
  /// [originalRequestId]. Used when the original RPC timed out or
  /// the connection dropped before Prism's reply could be read —
  /// Prism keeps a short-lived cache keyed by the original request's
  /// `messageId`.
  ///
  /// Returns the same flat
  /// `{tokenNo, subclass, description, scaledAmount}` shape as the
  /// credit/KCT/MSE issue methods, since the underlying Thrift RPC
  /// returns `List<PrismToken>`.
  FutureOr<List<Map<String, Object?>>> fetchTokenResult(
    String requestId,
    String originalRequestId,
  ) =>
      throw NotImplementedException(
        '$name does not support token-result replay.',
      );

  /// Verify a 20-digit token against a meter configuration WITHOUT
  /// throwing on invalid. Returns the raw
  /// `{validationResult, isValid, token?}` payload the underlying
  /// backend produced so the caller can branch on the precise
  /// validation status (e.g. `"Valid"`, `"Expired"`, `"InvalidCRC"`)
  /// rather than just success / failure. The optional `token` entry
  /// is the decoded `{tokenNo, subclass, description, scaledAmount}`
  /// shape when the backend chose to return it.
  FutureOr<Map<String, Object?>> verifyToken(
    String requestId,
    String tokenNo,
    Map<String, dynamic> params,
  ) =>
      throw NotImplementedException(
        '$name does not support token verification.',
      );

  /// Release any backend resources (connection pools, cached auth
  /// state, file handles). Idempotent; safe to call from a SIGINT /
  /// shutdown handler. Default impl is a no-op for in-process
  /// backends.
  FutureOr<void> close() async {}
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

  @override
  Future<List<Map<String, Object?>>> getNodeStatus() async => [
        {
          'info': {'backend': name},
          'alerts': const <Map<String, Object?>>[],
        },
      ];

  @override
  Future<List<Map<String, Object?>>> issueKeyChangeTokens(
    String requestId,
    Map<String, dynamic> params,
  ) async {
    // Resolve the *new* meter configuration. Only sgc/krn/ti
    // ("new_*") are strictly required \u2014 everything else (IIN,
    // DRN, DKGA, EA, key_type) stays the same as the current
    // config and is read out of [params] verbatim.
    String req(String key) {
      final v = params[key];
      if (v == null) {
        throw InvalidTokenException('Missing required param: $key');
      }
      return v.toString();
    }

    final newSgc = req(VirtualHsmParams.newSupplyGroupCode);
    final newKrn = req(VirtualHsmParams.newKeyRevisionNumber);
    final newTi = req(VirtualHsmParams.newTariffIndex);
    final newKt =
        params[VirtualHsmParams.newKeyType] ?? params[VirtualHsmParams.keyType];
    if (newKt == null) {
      throw InvalidTokenException(
        'Missing required param: ${VirtualHsmParams.keyType} '
        '(or ${VirtualHsmParams.newKeyType})',
      );
    }

    // Build a synthetic param map representing the *target* meter
    // config and derive its decoder key from the same vending
    // master. That hex blob becomes the payload embedded in each
    // KCT section.
    final newConfigParams = Map<String, dynamic>.from(params)
      ..[VirtualHsmParams.supplyGroupCode] = newSgc
      ..[VirtualHsmParams.keyRevisionNo] = newKrn
      ..[VirtualHsmParams.tariffIndex] = newTi
      ..[VirtualHsmParams.keyType] = newKt;
    final newKey = hsm.deriveDecoderKeyFromParams(newConfigParams);
    final newKeyHex = hexEncodeKey(newKey.keyData);

    // Optional control fields. PrismClient's MeterConfigAmendment
    // only carries (sgc, krn, ti) too \u2014 KEN / rollover / new-KT
    // get sensible defaults there. Mirror that here.
    final kenHigh = params[VirtualHsmParams.keyExpiryNumberHighOrder] ?? 0xF;
    final kenLow = params[VirtualHsmParams.keyExpiryNumberLowOrder] ?? 0xF;
    final rollover = params[VirtualHsmParams.rollOverKeyChange] ?? 0;

    final ea = (params[VirtualHsmParams.encryptionAlgorithm] ?? 'sta')
        .toString()
        .toLowerCase();
    final isMisty1 = ea == 'misty1';

    Token sectionToken(String subclass, Map<String, dynamic> extra) {
      final sectionParams = <String, dynamic>{
        ...params,
        VirtualHsmParams.tokenClass: '2',
        VirtualHsmParams.tokenSubclass: subclass,
        VirtualHsmParams.newDecoderKey: newKeyHex,
        ...extra,
      };
      return hsm.generateToken(requestId, sectionParams);
    }

    // Generate the entire bundle before returning so a downstream
    // failure on (e.g.) the 4th MISTY1 section doesn't leave the
    // caller with a partial set.
    final tokens = <Token>[
      sectionToken('3', {
        VirtualHsmParams.keyExpiryNumberHighOrder: kenHigh,
        VirtualHsmParams.newKeyRevisionNumber: newKrn,
        VirtualHsmParams.newKeyType: newKt,
        VirtualHsmParams.rollOverKeyChange: rollover,
      }),
      sectionToken('4', {
        VirtualHsmParams.keyExpiryNumberLowOrder: kenLow,
        VirtualHsmParams.newTariffIndex: newTi,
      }),
    ];
    if (isMisty1) {
      tokens
        ..add(
          sectionToken('8', {VirtualHsmParams.newSupplyGroupCode: newSgc}),
        )
        ..add(
          sectionToken('9', {VirtualHsmParams.newSupplyGroupCode: newSgc}),
        );
    }

    return [
      for (final t in tokens)
        {
          'tokenNo': t.tokenNo,
          'subclass': t.tokenSubClass?.bitString.value ?? 0,
          'description': t.type,
        },
    ];
  }

  @override
  Future<List<Map<String, Object?>>> issueMseToken(
    String requestId,
    int subclass,
    double transferAmount,
    Map<String, dynamic> params,
  ) =>
      throw NotImplementedException(
        '$name does not support MSE token issuance.',
      );

  @override
  Future<Map<String, Object?>> issueMeterTestToken(
    String requestId,
    int subclass,
    int control,
    int manufacturerCode,
  ) =>
      throw NotImplementedException(
        '$name does not support NMSE meter-test token issuance.',
      );

  @override
  Future<List<Map<String, Object?>>> issueCurrencyCreditToken(
    String requestId,
    int subclass,
    Map<String, dynamic> params,
  ) =>
      throw NotImplementedException(
        '$name does not support currency-credit token issuance.',
      );

  @override
  Future<List<Map<String, Object?>>> fetchTokenResult(
    String requestId,
    String originalRequestId,
  ) =>
      throw NotImplementedException(
        '$name does not support token-result replay.',
      );

  @override
  Future<Map<String, Object?>> verifyToken(
    String requestId,
    String tokenNo,
    Map<String, dynamic> params,
  ) async {
    try {
      final token = hsm.decodeToken(requestId, tokenNo, params);
      return {
        'validationResult': 'Valid',
        'isValid': true,
        'token': _virtualHsmVerifyTokenShape(tokenNo, token),
      };
    } on CrcError catch (e) {
      return {
        'validationResult': 'InvalidCRC',
        'isValid': false,
        'reason': e.message,
      };
    } on KeyExpiredError catch (e) {
      return {
        'validationResult': 'KeyExpired',
        'isValid': false,
        'reason': e.message,
      };
    } on KeyTypeError catch (e) {
      return {
        'validationResult': 'KeyTypeMismatch',
        'isValid': false,
        'reason': e.message,
      };
    } on TokenError catch (e) {
      return {
        'validationResult': 'InvalidToken',
        'isValid': false,
        'reason': e.message,
      };
    } on OldTokenError catch (e) {
      return {
        'validationResult': 'OldToken',
        'isValid': false,
        'reason': e.message,
      };
    } on UsedTokenError catch (e) {
      return {
        'validationResult': 'UsedToken',
        'isValid': false,
        'reason': e.message,
      };
    } on RangeError_ catch (e) {
      return {
        'validationResult': 'OutOfRange',
        'isValid': false,
        'reason': e.message,
      };
    }
  }

  @override
  Future<void> close() async {}
}

Map<String, Object?> _virtualHsmVerifyTokenShape(String tokenNo, Token token) {
  final amount =
      token is TransferElectricityCreditToken && token.amountPurchased != null
          ? token.amountPurchased!.unitsPurchased.toString()
          : '';
  return {
    'tokenNo': tokenNo,
    'subclass': token.tokenSubClass?.bitString.value ?? 0,
    'description': token.type,
    'scaledAmount': amount,
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

  /// Maximum number of concurrent Prism Thrift connections kept open
  /// by the issuer's internal pool. Connections are reused across
  /// RPC calls (after the cached JWT is applied), cutting the TLS
  /// handshake out of the hot path. When the pool is saturated,
  /// callers wait FIFO for a connection to free.
  ///
  /// `0` disables pooling entirely — each RPC connects, runs, and
  /// closes (matches the Java reference + the pre-pool behavior).
  /// Default is `4`, a small cushion that handles bursty issue
  /// traffic without holding more sockets than a single STS vendor
  /// node ever needs.
  final int maxConnections;

  /// How long an access token returned by `signInWithPassword` is
  /// cached and reused across RPC calls before the issuer signs in
  /// again. The Java reference re-authenticates on every call;
  /// caching for a short window cuts one network round-trip from
  /// every Prism RPC without materially weakening the auth posture.
  /// Set to [Duration.zero] to disable caching (re-sign-in every
  /// call). The default of 10 minutes is well below typical Prism
  /// JWT expiry windows.
  final Duration authTokenTtl;

  const PrismConfig({
    required this.host,
    required this.port,
    required this.realm,
    required this.username,
    required this.password,
    this.insecureTls = true,
    this.connectTimeout,
    this.authTokenTtl = const Duration(minutes: 10),
    this.maxConnections = 4,
  });
}

/// Prism-HSM-backed issuer.
///
/// Connections are pooled per [PrismConfig.maxConnections]; calls
/// borrow a live client, run, and return it. The pool replaces a
/// dead client (wire-level [SocketException] / [TimeoutException]
/// during a call) with a fresh connection on the next acquire.
class PrismIssuer implements TokenIssuer {
  final PrismConfig config;

  final SocketFactory? _socketFactoryOverride;

  /// Cached JWT from the most recent successful `signInWithPassword`,
  /// reused until `expiresAt` (= issue-time + [PrismConfig.authTokenTtl]).
  _CachedAuth? _cachedAuth;

  /// In-flight sign-in coalescer: when multiple RPC calls find the
  /// cache empty / stale at the same time, only the first triggers a
  /// real `signInWithPassword`; the others await this completer.
  Completer<String>? _inflightAuth;

  late final _PrismClientPool _pool = _PrismClientPool(
    maxSize: config.maxConnections,
  );

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

  /// Returns a usable Prism access token, either from cache (if still
  /// within [PrismConfig.authTokenTtl]) or by signing in fresh. Concurrent
  /// callers that find the cache stale share a single in-flight sign-in.
  Future<String> _getAccessToken(
    prism.TokenApiClient client,
    String requestId,
  ) async {
    final ttl = config.authTokenTtl;
    final now = DateTime.now();
    final cached = _cachedAuth;
    if (ttl > Duration.zero &&
        cached != null &&
        cached.expiresAt.isAfter(now)) {
      return cached.token;
    }
    final inflight = _inflightAuth;
    if (inflight != null) return inflight.future;

    final c = Completer<String>();
    _inflightAuth = c;
    try {
      final token = await client.signInWithPassword(
        messageId: requestId,
        realm: config.realm,
        username: config.username,
        password: config.password,
      );
      if (ttl > Duration.zero) {
        _cachedAuth = _CachedAuth(token, now.add(ttl));
      } else {
        _cachedAuth = null;
      }
      c.complete(token);
      return token;
    } catch (e, st) {
      _cachedAuth = null;
      c.completeError(e, st);
      rethrow;
    } finally {
      _inflightAuth = null;
    }
  }

  /// Borrow a Thrift client from the pool, run [fn], and return /
  /// discard the client depending on whether the failure looked like
  /// a wire-level issue (broken socket -> discard) or a Prism logic
  /// error (connection is still good -> return to pool).
  Future<T> _withClient<T>(
    Future<T> Function(prism.TokenApiClient client) fn,
  ) async {
    final client = await _pool.acquire(_factory);
    var brokenWire = false;
    try {
      return await fn(client);
    } on SocketException {
      brokenWire = true;
      rethrow;
    } on TimeoutException {
      brokenWire = true;
      rethrow;
    } finally {
      if (brokenWire) {
        await _pool.discard(client, _factory);
      } else {
        await _pool.release(client);
      }
    }
  }

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

    return await _withClient((client) async {
      final accessToken = await _getAccessToken(client, requestId);

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
    });
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
    return await _withClient((client) async {
      final accessToken = await _getAccessToken(client, requestId);
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
    });
  }

  @override
  Future<Map<String, Object?>> checkBackend() async {
    final stopwatch = Stopwatch()..start();
    try {
      return await _withClient((client) async {
        final echo = await client.ping(sleepMs: 0, echo: 'nectar-sts');
        stopwatch.stop();
        return {
          'ok': true,
          'backend': name,
          'echo': echo,
          'roundTripMs': stopwatch.elapsedMilliseconds,
        };
      });
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

  @override
  Future<List<Map<String, Object?>>> getNodeStatus() async {
    final requestId = 'status-${DateTime.now().microsecondsSinceEpoch}';
    return await _withClient((client) async {
      final accessToken = await _getAccessToken(client, requestId);
      final nodes = await client.getStatus(
        messageId: requestId,
        accessToken: accessToken,
      );
      return [
        for (final n in nodes)
          {
            'info': Map<String, String>.from(n.info),
            'alerts': [
              for (final a in n.alerts) {'eCode': a.eCode, 'eMsg': a.eMsgEn},
            ],
          },
      ];
    });
  }

  @override
  Future<List<Map<String, Object?>>> issueKeyChangeTokens(
    String requestId,
    Map<String, dynamic> params,
  ) async {
    final meterConfig = _meterConfigFromParams(params);
    final newConfig = _meterConfigAmendmentFromParams(params);

    return await _withClient((client) async {
      final accessToken = await _getAccessToken(client, requestId);
      final tokens = await client.issueKeyChangeTokens(
        messageId: requestId,
        accessToken: accessToken,
        meterConfig: meterConfig,
        newConfig: newConfig,
      );
      return [
        for (final t in tokens)
          {
            'tokenNo': t.tokenDec,
            'subclass': t.subclass,
            'description': t.description,
          },
      ];
    });
  }

  @override
  Future<List<Map<String, Object?>>> issueMseToken(
    String requestId,
    int subclass,
    double transferAmount,
    Map<String, dynamic> params,
  ) async {
    final meterConfig = _meterConfigFromParams(params);
    final tokenTime = _tokenTimeSeconds(params);

    return await _withClient((client) async {
      final accessToken = await _getAccessToken(client, requestId);
      final tokens = await client.issueMseToken(
        messageId: requestId,
        accessToken: accessToken,
        meterConfig: meterConfig,
        subclass: subclass,
        transferAmount: transferAmount,
        tokenTime: tokenTime,
      );
      return [
        for (final t in tokens)
          {
            'tokenNo': t.tokenDec,
            'subclass': t.subclass,
            'description': t.description,
          },
      ];
    });
  }

  @override
  Future<Map<String, Object?>> issueMeterTestToken(
    String requestId,
    int subclass,
    int control,
    int manufacturerCode,
  ) async {
    return await _withClient((client) async {
      final accessToken = await _getAccessToken(client, requestId);
      final t = await client.issueMeterTestToken(
        messageId: requestId,
        accessToken: accessToken,
        subclass: subclass,
        control: control,
        mfrcode: manufacturerCode,
      );
      return {
        'tokenNo': t.tokenDec,
        'subclass': t.subclass,
        'control': t.control,
        'manufacturerCode': t.mfrcode,
        'description': t.description,
        'tokenHex': t.tokenHex,
      };
    });
  }

  @override
  Future<List<Map<String, Object?>>> issueCurrencyCreditToken(
    String requestId,
    int subclass,
    Map<String, dynamic> params,
  ) async {
    if (subclass < 4 || subclass > 7) {
      throw NotImplementedException(
        'PrismIssuer.issueCurrencyCreditToken: subclass must be 4..7 '
        '(ElectricityCurrency, WaterCurrency, GasCurrency, '
        'TimeCurrency). Got $subclass.',
      );
    }
    final meterConfig = _meterConfigFromParams(params);
    final amount = _requiredDouble(params, VirtualHsmParams.amount);
    final tokenTime = _tokenTimeSeconds(params);

    return await _withClient((client) async {
      final accessToken = await _getAccessToken(client, requestId);
      // Currency-credit subclasses (4–7) scale by 100000 per
      // PrismHSMConnector.generateCreditToken, vs ×10 for kWh.
      final scaled = amount * 100000;
      final tokens = await client.issueCreditToken(
        messageId: requestId,
        accessToken: accessToken,
        meterConfig: meterConfig,
        subclass: subclass,
        transferAmount: scaled,
        tokenTime: tokenTime,
        flags: prism.TokenIssueFlags.externalClock,
      );
      return [
        for (final t in tokens)
          {
            'tokenNo': t.tokenDec,
            'subclass': t.subclass,
            'description': t.description,
            'scaledAmount': t.scaledAmount,
          },
      ];
    });
  }

  @override
  Future<List<Map<String, Object?>>> fetchTokenResult(
    String requestId,
    String originalRequestId,
  ) async {
    return await _withClient((client) async {
      final accessToken = await _getAccessToken(client, requestId);
      final tokens = await client.fetchTokenResult(
        messageId: requestId,
        accessToken: accessToken,
        reqMessageId: originalRequestId,
      );
      return [
        for (final t in tokens)
          {
            'tokenNo': t.tokenDec,
            'subclass': t.subclass,
            'description': t.description,
            'scaledAmount': t.scaledAmount,
          },
      ];
    });
  }

  @override
  Future<Map<String, Object?>> verifyToken(
    String requestId,
    String tokenNo,
    Map<String, dynamic> params,
  ) async {
    final meterConfig = _meterConfigFromParams(params);
    return await _withClient((client) async {
      final accessToken = await _getAccessToken(client, requestId);
      final result = await client.verifyToken(
        messageId: requestId,
        accessToken: accessToken,
        meterConfig: meterConfig,
        tokenDec: tokenNo,
      );
      final t = result.token;
      return {
        'validationResult': result.validationResult,
        'isValid': result.isValid,
        if (t != null)
          'token': {
            'tokenNo': t.tokenDec,
            'subclass': t.subclass,
            'description': t.description,
            'scaledAmount': t.scaledAmount,
          },
      };
    });
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

  prism.MeterConfigAmendment _meterConfigAmendmentFromParams(
    Map<String, dynamic> params,
  ) {
    final toSgc = int.parse(
      _requiredString(params, VirtualHsmParams.newSupplyGroupCode),
    );
    final toKrn = int.parse(
      _requiredString(params, VirtualHsmParams.newKeyRevisionNumber),
    );
    final toTi = int.parse(
      _requiredString(params, VirtualHsmParams.newTariffIndex),
    );
    return prism.MeterConfigAmendment(toSgc: toSgc, toKrn: toKrn, toTi: toTi);
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

  @override
  Future<void> close() async {
    await _pool.closeAll();
    _cachedAuth = null;
  }
}

class _CachedAuth {
  final String token;
  final DateTime expiresAt;
  const _CachedAuth(this.token, this.expiresAt);
}

/// Tiny FIFO connection pool for [prism.TokenApiClient]. Bounded by
/// [maxSize]; callers wait FIFO once the pool is saturated. A
/// [maxSize] of 0 disables pooling entirely \u2014 every acquire opens
/// a fresh client and every release closes it.
class _PrismClientPool {
  final int maxSize;
  final ListQueue<prism.TokenApiClient> _idle = ListQueue();
  final ListQueue<Completer<prism.TokenApiClient>> _waiters = ListQueue();
  int _inUse = 0;
  bool _closed = false;

  _PrismClientPool({required this.maxSize});

  /// Pool is disabled when [maxSize] is 0; every call connects fresh.
  bool get _disabled => maxSize == 0;

  Future<prism.TokenApiClient> acquire(SocketFactory factory) async {
    if (_closed) throw StateError('PrismClientPool is closed');
    if (_disabled) {
      return prism.TokenApiClient.connect(factory);
    }
    if (_idle.isNotEmpty) {
      _inUse++;
      return _idle.removeLast();
    }
    if (_inUse < maxSize) {
      _inUse++;
      try {
        return await prism.TokenApiClient.connect(factory);
      } catch (_) {
        _inUse--;
        rethrow;
      }
    }
    final c = Completer<prism.TokenApiClient>();
    _waiters.add(c);
    return c.future;
  }

  Future<void> release(prism.TokenApiClient client) async {
    if (_closed) {
      await _safeClose(client);
      return;
    }
    if (_disabled) {
      await _safeClose(client);
      return;
    }
    if (_waiters.isNotEmpty) {
      // Hand the live client directly to the next waiter; the
      // borrowed-slot count is unchanged.
      _waiters.removeFirst().complete(client);
      return;
    }
    _idle.add(client);
    _inUse--;
  }

  /// Wire-level failure path: close the dead client and free its
  /// slot. If anyone is waiting, immediately try to refill with a
  /// fresh connection so the queue doesn't stall.
  Future<void> discard(
    prism.TokenApiClient client,
    SocketFactory factory,
  ) async {
    await _safeClose(client);
    if (_disabled) return;
    _inUse--;
    if (_closed) return;
    if (_waiters.isEmpty) return;
    final waiter = _waiters.removeFirst();
    _inUse++;
    try {
      final fresh = await prism.TokenApiClient.connect(factory);
      waiter.complete(fresh);
    } catch (e, st) {
      _inUse--;
      waiter.completeError(e, st);
    }
  }

  Future<void> closeAll() async {
    if (_closed) return;
    _closed = true;
    final waiters = List<Completer<prism.TokenApiClient>>.from(_waiters);
    _waiters.clear();
    for (final c in waiters) {
      c.completeError(StateError('PrismClientPool is closed'));
    }
    final idle = List<prism.TokenApiClient>.from(_idle);
    _idle.clear();
    for (final c in idle) {
      await _safeClose(c);
    }
  }

  static Future<void> _safeClose(prism.TokenApiClient c) async {
    try {
      await c.close();
    } catch (_) {
      // Already torn down; nothing to do.
    }
  }
}
