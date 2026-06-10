/// `shelf` handler exposing a NectarAPI-compatible REST surface on
/// top of a [TokenIssuer] (electricity-credit tokens only — MVP scope).
///
/// Endpoints:
///   POST /v1/tokens                — generate. Body: VirtualHsmParams JSON.
///   POST /v1/tokens/{tokenNo}      — decode.   Body: VirtualHsmParams JSON.
///   POST /v1/tokens/key-change     — issue the atomic Key Change Token
///                                    bundle (2 entries for STA/DEA, 4 for
///                                    MISTY1). Body adds `new_supply_group_code`,
///                                    `new_key_revision_number`,
///                                    `new_tariff_index` to the regular
///                                    VirtualHsmParams shape.
///   POST /v1/tokens/mse/clear-credit    — Class 2 / subclass 1
///   POST /v1/tokens/mse/clear-tamper    — Class 2 / subclass 5
///   POST /v1/tokens/mse/set-max-power   — Class 2 / subclass 0;
///                                          body adds `maximum_power_limit` (kW)
///   POST /v1/tokens/mse/set-tariff      — Class 2 / subclass 2;
///                                          body adds `tariff_rate`
///   POST /v1/tokens/mse/set-flag        — Class 2 / subclass 10;
///                                          body adds `flag_type` (0..11) and
///                                          `flag_value` (0|1). The wire
///                                          payload is encoded the same way as
///                                          the Java reference
///                                          (`PrismHSMConnector.getTokenFlag`).
///   POST /v1/tokens/meter-test          — Class 1 / 3 NMSE test token.
///                                          Body: `subclass` (int),
///                                          `control` (int — see
///                                          `PrismHSMConnector.NMseType`),
///                                          `manufacturer_code` (int).
///                                          Returns a single token, not a
///                                          bundle.
///   POST /v1/tokens/credit/electricity-currency — Class 0 / subclass 4
///   POST /v1/tokens/credit/water-currency       — Class 0 / subclass 5
///   POST /v1/tokens/credit/gas-currency         — Class 0 / subclass 6
///   POST /v1/tokens/credit/time-currency        — Class 0 / subclass 7
///                                    Body: standard VirtualHsmParams +
///                                    `amount` (currency units; scaled
///                                    ×100000 internally per
///                                    `PrismHSMConnector.generateCreditToken`).
///                                    Returns a token list with
///                                    `{tokenNo, subclass, description,
///                                     scaledAmount}` per entry.
///   GET  /v1/tokens/results/{originalRequestId}
///                                  — idempotency replay. Re-fetch the
///                                    tokens previously issued for an earlier
///                                    request whose reply the caller never
///                                    got (timeout, dropped connection).
///                                    Returns the same `{tokenNo, subclass,
///                                    description, scaledAmount}` shape as
///                                    the issue endpoints.
///   POST /v1/tokens/{tokenNo}/verify
///                                  — non-throwing token validation. Body is
///                                    the standard VirtualHsmParams shape
///                                    (meter context). Always 200 on a
///                                    completed verify; the result is in
///                                    `data.validationResult` (`"Valid"`,
///                                    `"Expired"`, `"InvalidCRC"`, …) and
///                                    `data.isValid` (bool). When the backend
///                                    chose to return the decoded token, it
///                                    is in `data.token` (same flat shape as
///                                    the issue endpoints). Use this when the
///                                    caller wants to branch on the specific
///                                    validation status rather than
///                                    success / failure (`POST /v1/tokens/{tokenNo}`
///                                    instead throws on invalid).
///   GET  /healthz                  — liveness probe.
///   GET  /v1/health/backend        — issuer-backend probe (ping the
///                                    Prism HSM / VirtualHsm). 200 when
///                                    healthy, 503 when not.
///   GET  /v1/status/nodes          — per-node status (Prism cluster
///                                    info + alerts; VirtualHsm returns
///                                    a single synthetic entry).
///
/// All JSON responses use the `ApiResponse` envelope:
///   { "status":  { "code": <int>, "message": <string> },
///     "request_id": <string>,
///     "data": <object|null> }
///
/// HTTP status codes follow REST conventions (200 on success, 400 on
/// validation errors, 501 on out-of-scope features, 500 on anything
/// else). The envelope's `status.code` mirrors the HTTP status so a
/// caller can read either.
///
/// Auth: if the `NECTAR_API_TOKEN` env var is set when the handler is
/// built (see `buildApiHandler`), every `/v1/*` request must carry a
/// matching `Authorization: Bearer <token>` header. If the env var is
/// empty the API is open — fine for local dev, NOT for production.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../nectar_sts_dart.dart';
import 'db_queries.dart' show MissingForeignRowException;
import 'meter_registry.dart';
import 'tariff.dart';
import 'token_issuer.dart';
import 'vending_log.dart';

export 'meter_registry.dart';
export 'tariff.dart';
export 'token_issuer.dart';
export 'vending_log.dart';

/// `{status: {code, message}, request_id, data}` envelope, matching
/// the shape produced by NectarAPI's Spring Boot `ApiResponse`.
Map<String, dynamic> _envelope({
  required int code,
  required String message,
  required String requestId,
  Object? data,
}) =>
    {
      'status': {'code': code, 'message': message},
      'request_id': requestId,
      if (data != null) 'data': data,
    };

Response _json(int status, Map<String, dynamic> body) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

String _newRequestId() =>
    'req-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

/// Build a `shelf` `Handler` bound to [issuer]. Pass [bearerToken]
/// (or set `NECTAR_API_TOKEN`) to require
/// `Authorization: Bearer <token>`.
Handler buildApiHandler(
  TokenIssuer issuer, {
  String? bearerToken,
  VendingLogStore? log,
  MeterStore? registry,
  TariffBook? tariffs,
}) {
  final router = Router()
    ..get('/healthz', _healthHandler)
    ..get('/v1/health/backend', (Request r) => _backendHealthHandler(r, issuer))
    ..get('/v1/status/nodes', (Request r) => _nodeStatusHandler(r, issuer))
    ..post(
      '/v1/tokens',
      (Request r) => _generateHandler(r, issuer, log, registry, tariffs),
    )
    ..get('/v1/tokens', (Request r) => _listHandler(r, log))
    ..post('/v1/tokens/key-change', (Request r) => _keyChangeHandler(r, issuer))
    ..post(
      '/v1/tokens/mse/clear-credit',
      (Request r) => _mseHandler(r, issuer, _MseOp.clearCredit),
    )
    ..post(
      '/v1/tokens/mse/clear-tamper',
      (Request r) => _mseHandler(r, issuer, _MseOp.clearTamper),
    )
    ..post(
      '/v1/tokens/mse/set-max-power',
      (Request r) => _mseHandler(r, issuer, _MseOp.setMaxPower),
    )
    ..post(
      '/v1/tokens/mse/set-tariff',
      (Request r) => _mseHandler(r, issuer, _MseOp.setTariff),
    )
    ..post(
      '/v1/tokens/mse/set-flag',
      (Request r) => _mseHandler(r, issuer, _MseOp.setFlag),
    )
    ..post('/v1/tokens/meter-test', (Request r) => _meterTestHandler(r, issuer))
    ..post(
      '/v1/tokens/credit/electricity-currency',
      (Request r) => _currencyCreditHandler(r, issuer, 4, 'electricity'),
    )
    ..post(
      '/v1/tokens/credit/water-currency',
      (Request r) => _currencyCreditHandler(r, issuer, 5, 'water'),
    )
    ..post(
      '/v1/tokens/credit/gas-currency',
      (Request r) => _currencyCreditHandler(r, issuer, 6, 'gas'),
    )
    ..post(
      '/v1/tokens/credit/time-currency',
      (Request r) => _currencyCreditHandler(r, issuer, 7, 'time'),
    )
    ..get(
      '/v1/tokens/results/<originalRequestId>',
      (Request r, String originalRequestId) =>
          _fetchTokenResultHandler(r, issuer, originalRequestId),
    )
    ..post(
      '/v1/tokens/<tokenNo>/verify',
      (Request r, String tokenNo) =>
          _verifyHandler(r, issuer, tokenNo, registry),
    )
    ..get(
      '/v1/tokens/<tokenNo>',
      (Request r, String tokenNo) => _lookupHandler(r, log, tokenNo),
    )
    ..post(
      '/v1/tokens/<tokenNo>',
      (Request r, String tokenNo) =>
          _decodeHandler(r, issuer, tokenNo, registry),
    )
    ..post('/v1/meters', (Request r) => _registerMeterHandler(r, registry))
    ..get('/v1/meters', (Request r) => _listMetersHandler(r, registry))
    ..get(
      '/v1/meters/<serial>',
      (Request r, String serial) => _getMeterHandler(r, registry, serial),
    )
    ..delete(
      '/v1/meters/<serial>',
      (Request r, String serial) => _deleteMeterHandler(r, registry, serial),
    );

  return Pipeline()
      .addMiddleware(_authMiddleware(bearerToken))
      .addMiddleware(_errorHandlingMiddleware())
      .addHandler(router.call);
}

// ---- endpoints --------------------------------------------------

Response _healthHandler(Request request) =>
    _json(200, {'status': 'ok', 'service': 'nectar_sts_dart'});

Future<Response> _backendHealthHandler(
  Request request,
  TokenIssuer issuer,
) async {
  final report = await issuer.checkBackend();
  final ok = report['ok'] == true;
  return _json(ok ? 200 : 503, report);
}

Future<Response> _nodeStatusHandler(Request request, TokenIssuer issuer) async {
  try {
    final nodes = await issuer.getNodeStatus();
    return _json(200, {'nodes': nodes});
  } catch (e) {
    return _json(503, {
      'nodes': const <Map<String, Object?>>[],
      'error': e.toString(),
    });
  }
}

Future<Response> _generateHandler(
  Request request,
  TokenIssuer issuer,
  VendingLogStore? log,
  MeterStore? registry,
  TariffBook? tariffs,
) async {
  final requestId = _newRequestId();
  final rawBody = await _readJsonBody(request);
  _rejectSensitiveParams(rawBody);
  final resolved = await _resolveMeterSerial(rawBody, registry);
  final params = resolved.params;
  final pricing = _resolvePricing(params, tariffs);
  _validateAmount(params);

  // Pre-check TID collision if a log is configured + the request
  // carries enough info to compute the would-be TID. We let the
  // dispatch layer canonicalize class/subclass/base_date by doing
  // a no-op param read here.
  if (log != null) {
    final tid = _previewTidMinutes(params);
    final fp = _identityFingerprint(params);
    if (tid != null &&
        fp != null &&
        await log.tidExists(identityFingerprint: fp, tidMinutes: tid)) {
      final prior = await log.findCollision(
        identityFingerprint: fp,
        tidMinutes: tid,
      );
      final priorMsg = prior == null
          ? ''
          : ' (token_no=${prior.tokenNo}, request_id=${prior.requestId})';
      return _json(
        409,
        _envelope(
          code: 409,
          message: 'TID collision: a token with tid_minutes=$tid was already '
              'issued for this meter$priorMsg. Use a fresh token_id.',
          requestId: requestId,
        ),
      );
    }
  }

  final token = await issuer.generateToken(requestId, params);

  if (log != null) {
    await log.record(
      _recordFor(requestId, token, params, resolved.meterSerial, pricing),
    );
  }

  return _json(
    200,
    _envelope(
      code: 200,
      message: 'Token generated',
      requestId: requestId,
      data: {
        'token': [_tokenToJson(token)],
        if (resolved.meterSerial != null) 'meter_serial': resolved.meterSerial,
        if (pricing != null) 'pricing': pricing.toJson(),
      },
    ),
  );
}

Future<Response> _decodeHandler(
  Request request,
  TokenIssuer issuer,
  String tokenNo,
  MeterStore? registry,
) async {
  final requestId = _newRequestId();
  final rawBody = await _readJsonBody(request);
  _rejectSensitiveParams(rawBody);
  final params = (await _resolveMeterSerial(rawBody, registry)).params;
  final decoded = await issuer.decodeToken(requestId, tokenNo, params);

  return _json(
    200,
    _envelope(
      code: 200,
      message: 'Token decoded',
      requestId: requestId,
      data: {'token_details': _tokenToJson(decoded)},
    ),
  );
}

Future<Response> _keyChangeHandler(Request request, TokenIssuer issuer) async {
  final requestId = _newRequestId();
  final body = await _readJsonBody(request);
  _rejectSensitiveParams(body);
  final tokens = await issuer.issueKeyChangeTokens(requestId, body);
  return _json(
    200,
    _envelope(
      code: 200,
      message: 'Key change tokens issued',
      requestId: requestId,
      data: {'tokens': tokens},
    ),
  );
}

/// Class 2 / MSE operations exposed as discrete `/v1/tokens/mse/*` routes.
/// Each entry carries the wire subclass (per
/// `PrismHSMConnector.MseToken`) and a request-body resolver that turns
/// the JSON request into a `transferAmount` double for Prism.
enum _MseOp {
  clearCredit(1, 'Clear credit'),
  clearTamper(5, 'Clear tamper'),
  setMaxPower(0, 'Set max power'),
  setTariff(2, 'Set tariff rate'),
  setFlag(10, 'Set flag');

  final int subclass;
  final String description;
  const _MseOp(this.subclass, this.description);
}

Future<Response> _mseHandler(
  Request request,
  TokenIssuer issuer,
  _MseOp op,
) async {
  final requestId = _newRequestId();
  final body = await _readJsonBody(request);
  _rejectSensitiveParams(body);
  final transferAmount = _resolveMseTransferAmount(op, body);
  final tokens = await issuer.issueMseToken(
    requestId,
    op.subclass,
    transferAmount,
    body,
  );
  return _json(
    200,
    _envelope(
      code: 200,
      message: '${op.description} token issued',
      requestId: requestId,
      data: {'tokens': tokens},
    ),
  );
}

/// Resolve the `transferAmount` Prism wire field for a given MSE op.
/// Matches `PrismHSMConnector.generateMseToken` semantics: max-power
/// uses `maximum_power_limit`, tariff-rate uses `tariff_rate`, set-flag
/// encodes `flag_type`+`flag_value` the same way as
/// `PrismHSMConnector.getTokenFlag`, everything else is `0`.
double _resolveMseTransferAmount(_MseOp op, Map<String, dynamic> body) {
  switch (op) {
    case _MseOp.clearCredit:
    case _MseOp.clearTamper:
      return 0;
    case _MseOp.setMaxPower:
      return _requireBodyDouble(body, 'maximum_power_limit');
    case _MseOp.setTariff:
      return _requireBodyDouble(body, 'tariff_rate');
    case _MseOp.setFlag:
      final flagType = _requireBodyInt(body, 'flag_type');
      final flagValue = _requireBodyInt(body, 'flag_value');
      return _encodeSetFlagPayload(flagType, flagValue);
  }
}

double _requireBodyDouble(Map<String, dynamic> body, String key) {
  final v = body[key];
  if (v is num) return v.toDouble();
  if (v is String) {
    final parsed = double.tryParse(v);
    if (parsed != null) return parsed;
  }
  throw _BadRequest('Field "$key" is required and must be numeric');
}

int _requireBodyInt(Map<String, dynamic> body, String key) {
  final v = body[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final parsed = int.tryParse(v);
    if (parsed != null) return parsed;
  }
  throw _BadRequest('Field "$key" is required and must be an integer');
}

/// Mirrors `PrismHSMConnector.getTokenFlag`: pack a constant 6-bit
/// index (63), a 9-bit `flag_type`, and a 1-bit `flag_value` as a
/// 16-char string of '0'/'1' chars, then parse it as a *decimal*
/// integer (not binary). Faithful to the Java reference quirk.
double _encodeSetFlagPayload(int flagType, int flagValue) {
  String pad(int v, int w) => v.toRadixString(2).padLeft(w, '0');
  final s = '111111${pad(flagType, 9)}${pad(flagValue, 1)}';
  return double.parse(s);
}

Future<Response> _meterTestHandler(Request request, TokenIssuer issuer) async {
  final requestId = _newRequestId();
  final body = await _readJsonBody(request);
  _rejectSensitiveParams(body);
  final subclass = _requireBodyInt(body, 'subclass');
  final control = _requireBodyInt(body, 'control');
  final manufacturerCode = _requireBodyInt(body, 'manufacturer_code');
  final token = await issuer.issueMeterTestToken(
    requestId,
    subclass,
    control,
    manufacturerCode,
  );
  return _json(
    200,
    _envelope(
      code: 200,
      message: 'Meter-test token issued',
      requestId: requestId,
      data: {'token': token},
    ),
  );
}

Future<Response> _currencyCreditHandler(
  Request request,
  TokenIssuer issuer,
  int subclass,
  String resourceLabel,
) async {
  final requestId = _newRequestId();
  final body = await _readJsonBody(request);
  _rejectSensitiveParams(body);
  final tokens = await issuer.issueCurrencyCreditToken(
    requestId,
    subclass,
    body,
  );
  return _json(
    200,
    _envelope(
      code: 200,
      message: 'Currency-credit token issued ($resourceLabel)',
      requestId: requestId,
      data: {'tokens': tokens},
    ),
  );
}

Future<Response> _fetchTokenResultHandler(
  Request request,
  TokenIssuer issuer,
  String originalRequestId,
) async {
  final requestId = _newRequestId();
  if (originalRequestId.isEmpty) {
    throw const _BadRequest('Path segment "originalRequestId" is required');
  }
  final tokens = await issuer.fetchTokenResult(requestId, originalRequestId);
  return _json(
    200,
    _envelope(
      code: 200,
      message: 'Token result fetched',
      requestId: requestId,
      data: {'original_request_id': originalRequestId, 'tokens': tokens},
    ),
  );
}

Future<Response> _verifyHandler(
  Request request,
  TokenIssuer issuer,
  String tokenNo,
  MeterStore? registry,
) async {
  final requestId = _newRequestId();
  if (tokenNo.isEmpty) {
    throw const _BadRequest('Path segment "tokenNo" is required');
  }
  final body = await _readJsonBody(request);
  _rejectSensitiveParams(body);
  final params = (await _resolveMeterSerial(body, registry)).params;
  final result = await issuer.verifyToken(requestId, tokenNo, params);
  return _json(
    200,
    _envelope(
      code: 200,
      message: 'Token verified',
      requestId: requestId,
      data: {'tokenNo': tokenNo, ...result},
    ),
  );
}

Future<Response> _listHandler(Request request, VendingLogStore? log) async {
  final requestId = _newRequestId();
  if (log == null) {
    return _json(
      503,
      _envelope(
        code: 503,
        message: 'Vending log is not enabled on this server',
        requestId: requestId,
      ),
    );
  }
  final iin = request.url.queryParameters['iin'];
  final iain = request.url.queryParameters['iain'];
  final matches = await log.forMeter(iin: iin, iain: iain);
  return _json(
    200,
    _envelope(
      code: 200,
      message: 'Found ${matches.length} issued token(s)',
      requestId: requestId,
      data: {
        'count': matches.length,
        'issues': matches.map((r) => r.toJson()).toList(),
      },
    ),
  );
}

Future<Response> _lookupHandler(
  Request request,
  VendingLogStore? log,
  String tokenNo,
) async {
  final requestId = _newRequestId();
  if (log == null) {
    return _json(
      503,
      _envelope(
        code: 503,
        message: 'Vending log is not enabled on this server',
        requestId: requestId,
      ),
    );
  }
  final hit = await log.lookupToken(tokenNo);
  if (hit == null) {
    return _json(
      404,
      _envelope(
        code: 404,
        message: 'No issued token matches $tokenNo',
        requestId: requestId,
      ),
    );
  }
  return _json(
    200,
    _envelope(
      code: 200,
      message: 'Issued-token record found',
      requestId: requestId,
      data: {'issued_token': hit.toJson()},
    ),
  );
}

// ---- meter registry endpoints ----------------------------------

Response _registryDisabled(String requestId) => _json(
      503,
      _envelope(
        code: 503,
        message: 'Meter registry is not enabled on this server',
        requestId: requestId,
      ),
    );

Future<Response> _registerMeterHandler(
  Request request,
  MeterStore? registry,
) async {
  final requestId = _newRequestId();
  if (registry == null) return _registryDisabled(requestId);
  final body = await _readJsonBody(request);
  _rejectSensitiveParams(body);

  final serial = body['serial']?.toString();
  if (serial == null || serial.isEmpty) {
    throw const _BadRequest('Field "serial" is required');
  }
  final identityMap = body['identity'];
  final Map<String, dynamic> identityJson;
  if (identityMap is Map<String, dynamic>) {
    identityJson = identityMap;
  } else {
    // Allow flat form: identity fields at top level.
    identityJson = <String, dynamic>{
      for (final k in const [
        'issuer_identification_no',
        'decoder_reference_number',
        'key_type',
        'supply_group_code',
        'tariff_index',
        'key_revision_no',
        'decoder_key_generation_algorithm',
        'base_date',
      ])
        if (body.containsKey(k)) k: body[k],
    };
  }
  final MeterIdentity identity;
  try {
    identity = MeterIdentity.fromJson({
      'issuer_identification_no':
          identityJson['issuer_identification_no']?.toString(),
      'decoder_reference_number':
          identityJson['decoder_reference_number']?.toString(),
      'key_type': identityJson['key_type'],
      'supply_group_code': identityJson['supply_group_code']?.toString(),
      'tariff_index': identityJson['tariff_index']?.toString(),
      'key_revision_no': identityJson['key_revision_no'],
      'decoder_key_generation_algorithm':
          identityJson['decoder_key_generation_algorithm']?.toString() ?? '02',
      if (identityJson['base_date'] != null)
        'base_date': identityJson['base_date']?.toString(),
    });
  } catch (e) {
    throw _BadRequest('Invalid identity: $e');
  }

  final meter = RegisteredMeter(
    serial: serial,
    identity: identity,
    encryptionAlgorithm:
        (body['encryption_algorithm'] ?? 'sta').toString().toLowerCase(),
    subscriberLabel: body['subscriber_label']?.toString(),
    registeredAt: DateTime.now().toUtc(),
  );
  try {
    await registry.add(meter);
  } on DuplicateMeterSerialException {
    return _json(
      409,
      _envelope(
        code: 409,
        message: 'Meter serial "$serial" is already registered',
        requestId: requestId,
      ),
    );
  } on MissingForeignRowException catch (e) {
    return _json(
      412,
      _envelope(
        code: 412,
        message: 'Missing prerequisite row (${e.table}.${e.key}=${e.value}). '
            'Create it in the Laravel dashboard before registering this '
            'meter.',
        requestId: requestId,
      ),
    );
  }

  return _json(
    201,
    _envelope(
      code: 201,
      message: 'Meter registered',
      requestId: requestId,
      data: {'meter': meter.toJson()},
    ),
  );
}

Future<Response> _listMetersHandler(
  Request request,
  MeterStore? registry,
) async {
  final requestId = _newRequestId();
  if (registry == null) return _registryDisabled(requestId);
  final meters = await registry.list();
  return _json(
    200,
    _envelope(
      code: 200,
      message: '${meters.length} meter(s) registered',
      requestId: requestId,
      data: {
        'count': meters.length,
        'meters': meters.map((m) => m.toJson()).toList(),
      },
    ),
  );
}

Future<Response> _getMeterHandler(
  Request request,
  MeterStore? registry,
  String serial,
) async {
  final requestId = _newRequestId();
  if (registry == null) return _registryDisabled(requestId);
  final hit = await registry.lookup(serial);
  if (hit == null) {
    return _json(
      404,
      _envelope(
        code: 404,
        message: 'No meter registered with serial "$serial"',
        requestId: requestId,
      ),
    );
  }
  return _json(
    200,
    _envelope(
      code: 200,
      message: 'Meter found',
      requestId: requestId,
      data: {'meter': hit.toJson()},
    ),
  );
}

Future<Response> _deleteMeterHandler(
  Request request,
  MeterStore? registry,
  String serial,
) async {
  final requestId = _newRequestId();
  if (registry == null) return _registryDisabled(requestId);
  final removed = await registry.delete(serial);
  if (!removed) {
    return _json(
      404,
      _envelope(
        code: 404,
        message: 'No meter registered with serial "$serial"',
        requestId: requestId,
      ),
    );
  }
  return _json(
    200,
    _envelope(
      code: 200,
      message: 'Meter "$serial" deregistered',
      requestId: requestId,
    ),
  );
}

// ---- helpers ----------------------------------------------------

Future<Map<String, dynamic>> _readJsonBody(Request request) async {
  final raw = await request.readAsString();
  if (raw.isEmpty) return <String, dynamic>{};
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const _BadRequest('Request body must be a JSON object');
  }
  return decoded;
}

/// The server holds its own configured vending key. Allowing a
/// client to override it per-request would let any caller mint
/// tokens for *any* meter on the network.
void _rejectSensitiveParams(Map<String, dynamic> params) {
  for (final forbidden in const ['vending_key', 'decoder_key']) {
    if (params.containsKey(forbidden)) {
      throw _BadRequest(
        'Param "$forbidden" is not accepted over the wire — the server '
        'uses its own configured key',
      );
    }
  }
}

/// Identity fields that the meter registry **always** owns. For
/// DKGA-04 meters the registry's identity also carries `base_date`;
/// that field is added dynamically in [_resolveMeterSerial].
const _identityFields = <String>[
  'issuer_identification_no',
  'decoder_reference_number',
  'key_type',
  'supply_group_code',
  'tariff_index',
  'key_revision_no',
  'decoder_key_generation_algorithm',
  'encryption_algorithm',
];

class _ResolvedParams {
  final Map<String, dynamic> params;
  final String? meterSerial;
  const _ResolvedParams(this.params, this.meterSerial);
}

/// If [body] contains `meter_serial`, look it up in [registry] and
/// produce a params map with the registry's identity merged in.
/// Otherwise return [body] unchanged.
Future<_ResolvedParams> _resolveMeterSerial(
  Map<String, dynamic> body,
  MeterStore? registry,
) async {
  final serial = body['meter_serial'];
  if (serial == null) return _ResolvedParams(body, null);
  if (registry == null) {
    throw const _BadRequest(
      'meter_serial was provided but the server has no meter registry '
      '(set METER_REGISTRY_FILE)',
    );
  }
  final hit = await registry.lookup(serial.toString());
  if (hit == null) {
    throw _MeterNotFound(serial.toString());
  }
  final identityJson = hit.identity.toJson();
  // A DKGA-04 meter pins base_date to the value used at key
  // derivation; a DKGA-02 meter doesn't store one, so per-request
  // base_date is fine.
  final ownedFields = <String>{..._identityFields, ...identityJson.keys};
  final conflicts = ownedFields.where(body.containsKey).toList();
  if (conflicts.isNotEmpty) {
    throw _BadRequest(
      'meter_serial cannot be combined with identity fields: '
      '${conflicts.join(", ")}',
    );
  }
  final merged = <String, dynamic>{...body}
    ..remove('meter_serial')
    ..addAll(identityJson)
    ..['encryption_algorithm'] = hit.encryptionAlgorithm;
  return _ResolvedParams(merged, hit.serial);
}

void _validateAmount(Map<String, dynamic> params) {
  if (params['class']?.toString() != '0') return;
  if (params['subclass']?.toString() != '0') return;
  final raw = params['amount'];
  if (raw == null) return; // dispatch will throw a clearer error
  final v = raw is num ? raw.toDouble() : double.tryParse(raw.toString());
  if (v == null || v <= 0) {
    throw _BadRequest('amount must be a positive number, got: $raw');
  }
}

/// Resolve the kWh ↔ money relationship for a credit-token mint.
///
/// - Returns `null` for non-credit tokens or when no tariff applies.
/// - When the request supplies `amount_money` (and no `amount`),
///   the helper INJECTS the converted kWh into `params['amount']`
///   so the downstream cipher sees the same shape as a raw kWh
///   request would.
/// - When the request supplies `amount` (kWh) and a tariff exists,
///   the helper computes the cash equivalent for the response
///   envelope but does NOT touch `params['amount']`.
/// - 400s on conflicts: both fields, missing tariff for money
///   request, currency mismatch, non-positive money, etc.
PricingBreakdown? _resolvePricing(
  Map<String, dynamic> params,
  TariffBook? tariffs,
) {
  if (params['class']?.toString() != '0') return null;
  if (params['subclass']?.toString() != '0') return null;

  final hasMoney = params.containsKey('amount_money');
  final hasKwh = params.containsKey('amount');
  if (hasMoney && hasKwh) {
    throw const _BadRequest(
      'Provide either "amount" (kWh) or "amount_money" (cash), not both',
    );
  }

  final requestCurrency = params['currency']?.toString().toUpperCase();
  final tariffIndex = params['tariff_index']?.toString();
  final tariff = tariffs?.lookup(tariffIndex);

  if (hasMoney) {
    if (tariff == null) {
      throw const _BadRequest(
        'amount_money requires a configured tariff for the request '
        'tariff_index (set TARIFF_PRICE_PER_KWH or TARIFF_TABLE on '
        'the server)',
      );
    }
    if (requestCurrency != null && requestCurrency != tariff.currency) {
      throw _BadRequest(
        'currency mismatch: request says "$requestCurrency" but tariff '
        'is "${tariff.currency}"',
      );
    }
    final rawMoney = params['amount_money'];
    final money = rawMoney is num
        ? rawMoney.toDouble()
        : double.tryParse(rawMoney?.toString() ?? '');
    if (money == null || money <= 0) {
      throw _BadRequest(
        'amount_money must be a positive number, got: $rawMoney',
      );
    }
    final kwh = tariff.kwhFor(money);
    if (kwh <= 0) {
      throw _BadRequest(
        'amount_money=$money ${tariff.currency} only covers the admin '
        'fee (${tariff.adminFee} ${tariff.currency}) — no kWh purchased',
      );
    }
    // Inject the resolved kWh + currency for downstream consumers.
    params['amount'] = kwh;
    params.remove('amount_money');
    params['currency'] = tariff.currency;
    return PricingBreakdown(
      tariffIndex: tariffIndex ?? '',
      currency: tariff.currency,
      pricePerKwh: tariff.pricePerKwh,
      adminFee: tariff.adminFee,
      kwh: kwh,
      amountMoney: money - tariff.adminFee,
      total: money,
    );
  }

  if (!hasKwh || tariff == null) return null;

  // Plain kWh request + we have a tariff — compute money for the
  // response envelope but leave params['amount'] alone.
  final rawKwh = params['amount'];
  final kwh = rawKwh is num
      ? rawKwh.toDouble()
      : double.tryParse(rawKwh?.toString() ?? '');
  if (kwh == null || kwh <= 0) return null; // _validateAmount handles
  if (requestCurrency != null && requestCurrency != tariff.currency) {
    throw _BadRequest(
      'currency mismatch: request says "$requestCurrency" but tariff '
      'is "${tariff.currency}"',
    );
  }
  final money = kwh * tariff.pricePerKwh;
  final total = money + tariff.adminFee;
  params['currency'] = tariff.currency;
  return PricingBreakdown(
    tariffIndex: tariffIndex ?? '',
    currency: tariff.currency,
    pricePerKwh: tariff.pricePerKwh,
    adminFee: tariff.adminFee,
    kwh: kwh,
    amountMoney: money,
    total: total,
  );
}

/// Best-effort TID preview from request params, matching the same
/// arithmetic `TokenIdentifier` does. Returns `null` when the
/// request isn't a Class 0 credit token or doesn't carry a token_id.
int? _previewTidMinutes(Map<String, dynamic> params) {
  if (params['class']?.toString() != '0') return null;
  final rawTid = params['token_id'];
  if (rawTid == null) return null;
  final DateTime issued;
  if (rawTid is DateTime) {
    issued = rawTid.toUtc();
  } else if (rawTid is String) {
    issued = DateTime.parse(rawTid).toUtc();
  } else {
    return null;
  }
  final baseYear = switch ((params['base_date'] ?? '1993').toString()) {
    '2014' || '14' => 2014,
    '2035' || '35' => 2035,
    _ => 1993,
  };
  final base = DateTime.utc(baseYear, 1, 1);
  var diff = issued.difference(base).inMinutes;
  if (issued.minute == 1 && issued.hour == 0) diff += 1;
  return diff & 0xFFFFFF; // 24-bit TID
}

String? _identityFingerprint(Map<String, dynamic> params) {
  String? s(String k) => params[k]?.toString();
  final iin = s('issuer_identification_no');
  final iain = s('decoder_reference_number');
  final kt = s('key_type');
  final sgc = s('supply_group_code');
  final ti = s('tariff_index');
  final krn = s('key_revision_no');
  final dkga = s('decoder_key_generation_algorithm') ?? '02';
  if (iin == null ||
      iain == null ||
      kt == null ||
      sgc == null ||
      ti == null ||
      krn == null) {
    return null;
  }
  return '$iin|$iain|$kt|$sgc|$ti|$krn|$dkga';
}

IssuedTokenRecord _recordFor(
  String requestId,
  Token token,
  Map<String, dynamic> params,
  String? meterSerial,
  PricingBreakdown? pricing,
) {
  double? amount;
  int? tid;
  int? randomNo;
  if (token is TransferElectricityCreditToken) {
    amount = token.amountPurchased?.unitsPurchased;
    tid = token.tokenIdentifier?.bitString.value;
    randomNo = token.randomNo?.bitString.value;
  }
  return IssuedTokenRecord(
    requestId: requestId,
    tokenNo: token.tokenNo,
    issuedAt: DateTime.now().toUtc(),
    iin: params['issuer_identification_no'].toString(),
    iain: params['decoder_reference_number'].toString(),
    keyType: int.parse(params['key_type'].toString()),
    supplyGroupCode: params['supply_group_code'].toString(),
    tariffIndex: params['tariff_index'].toString(),
    keyRevisionNumber: int.parse(params['key_revision_no'].toString()),
    decoderKeyGenerationAlgorithm:
        (params['decoder_key_generation_algorithm'] ?? '02').toString(),
    tokenClass: token.tokenClass?.bitString.value ?? 0,
    tokenSubclass: token.tokenSubClass?.bitString.value ?? 0,
    amountKwh: amount,
    tidMinutes: tid,
    randomNo: randomNo,
    amountMoney: pricing?.total,
    currency: pricing?.currency ?? params['currency']?.toString(),
    meterSerial: meterSerial,
  );
}

Map<String, dynamic> _tokenToJson(Token token) {
  final base = <String, dynamic>{
    'type': token.type,
    if (token.encryptedTokenBitString != null) 'token_no': token.tokenNo,
    'request_id': token.requestID,
    if (token.tokenClass != null) 'class': token.tokenClass!.bitString.value,
    if (token.tokenSubClass != null)
      'subclass': token.tokenSubClass!.bitString.value,
    if (token.crc != null)
      'crc':
          '0x${token.crc!.bitString.value.toRadixString(16).padLeft(4, '0')}',
  };
  if (token is TransferElectricityCreditToken) {
    if (token.amountPurchased != null) {
      base['amount'] = token.amountPurchased!.unitsPurchased;
    }
    if (token.tokenIdentifier != null) {
      base['token_id_minutes'] = token.tokenIdentifier!.bitString.value;
      base['token_id_time'] =
          token.tokenIdentifier!.timeOfIssue.toIso8601String();
    }
    if (token.randomNo != null) {
      base['random_no'] = token.randomNo!.bitString.value;
    }
  }
  return base;
}

Middleware _authMiddleware(String? configuredToken) {
  final envToken =
      configuredToken ?? const String.fromEnvironment('NECTAR_API_TOKEN');
  final expected = envToken.isEmpty ? null : envToken;
  return (Handler inner) {
    return (Request request) async {
      if (expected == null) return inner(request);
      if (request.url.path == 'healthz') return inner(request);
      final auth = request.headers['authorization'];
      if (auth == null || auth != 'Bearer $expected') {
        return _json(
          401,
          _envelope(
            code: 401,
            message: 'Unauthorized',
            requestId: _newRequestId(),
          ),
        );
      }
      return inner(request);
    };
  };
}

Middleware _errorHandlingMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      try {
        return await inner(request);
      } on _BadRequest catch (e) {
        return _json(
          400,
          _envelope(code: 400, message: e.message, requestId: _newRequestId()),
        );
      } on _MeterNotFound catch (e) {
        return _json(
          404,
          _envelope(
            code: 404,
            message: 'No meter registered with serial "${e.serial}"',
            requestId: _newRequestId(),
          ),
        );
      } on FormatException catch (e) {
        return _json(
          400,
          _envelope(
            code: 400,
            message: 'Invalid JSON: ${e.message}',
            requestId: _newRequestId(),
          ),
        );
      } on NotImplementedException catch (e) {
        return _json(
          501,
          _envelope(code: 501, message: e.message, requestId: _newRequestId()),
        );
      } on StsError catch (e) {
        return _json(
          400,
          _envelope(
            code: 400,
            message: '${e.runtimeType}: ${e.message}',
            requestId: _newRequestId(),
          ),
        );
      } catch (e) {
        return _json(
          500,
          _envelope(
            code: 500,
            message: 'Internal error: $e',
            requestId: _newRequestId(),
          ),
        );
      }
    };
  };
}

class _BadRequest implements Exception {
  final String message;
  const _BadRequest(this.message);
}

class _MeterNotFound implements Exception {
  final String serial;
  const _MeterNotFound(this.serial);
}
