# nectar_sts_dart

A **pure-Dart port of the algorithm core** of
[NectarAPI/tokens-service](https://github.com/NectarAPI/tokens-service):
the IEC 62055-41 / STS6 Standard Transfer Specification used by
prepaid electricity meters.

The original Java service is a full STS vending stack — HTTP/SOAP
endpoints, persistent database, audit, key revocation, vendor HSM
integration, etc. This port deliberately picks out just the
**cryptographic + token-encoding kernel** so it can be embedded in
Dart applications, CLIs, Flutter apps and tests without dragging in
any server-side infrastructure.

## What's included

| Layer | Purpose | Files |
| --- | --- | --- |
| Base bit/byte primitives | `BitString`, `Bit`, `Nibble`, CRC-16, Luhn | `lib/src/base/`, `lib/src/util/` |
| Domain primitives | `Amount`, `TokenIdentifier`, `TokenClass`, `TokenSubClass`, `BaseDate`, `RandomNo`, `IssuerIdentificationNumber`, `IndividualAccountIdentificationNumber`, `SupplyGroupCode`, `TariffIndex`, `KeyRevisionNumber`, `KeyType`, `ManufacturerCode`, `Control` | `lib/src/domain/` |
| Keys | `VendingKey` / `VendingCommonDesKey`, `DecoderKey` | `lib/src/keys/` |
| Encryption algorithms | EA07 (`StandardTransferAlgorithm`), EA09 (`DataEncryptionAlgorithm`) | `lib/src/encryption/` |
| Decoder-key derivation | DKGA-02, DKGA-04 | `lib/src/decoderkey/` |
| Tokens | abstract `Token`, `TokenTransposition`, **Class 0** `TransferElectricityCreditToken`, **Class 1** `InitiateMeterTestOrDisplay1/2Token` | `lib/src/token/` |
| Generators | `Class0` + `Class1` token generators | `lib/src/tokengen/` |
| Decoders | per-class decoders + sealed-result `TokenDecoderDispatcher` | `lib/src/tokendec/` |
| HSM | `Hsm` interface, `VirtualHsm` (software, works), `PrismHsm` (NotImplemented stub) | `lib/src/hsm/` |

## What's deliberately NOT ported

- **Class 2 tokens** (engineering / set-parameter family: `Pad`,
  `Register`, `MaximumPowerLimit`, `Rate`, `NewKey*`, `RolloverKeyChange`,
  `_3KCT`, etc.) — large surface area, only used in the meter-management
  path, not in routine vending.
- **Class 3 tokens** — reserved by the STS spec.
- **Meter state machine** — token-cache / replay detection, key
  rollover state, tariff-index switching. Tokens are decoded
  statelessly here.
- **Prism / real-HSM transport** — `PrismHsm` is a stub that documents
  the API but always throws `NotImplementedException`.
- **HTTP / SOAP service, persistent DB, REST controllers** — out of
  scope for an algorithm-core package.

`TokenDecoderDispatcher` rejects Class 2/3 tokens cleanly with
`DecodeFailure(NotImplementedException(...))` so callers can detect
the gap without crashing.

## Bit-layout quick reference

All blocks are LSB-first, exactly as in the Java reference.

### 64-bit decrypted data block, Class 0 / SubClass 0 (electricity credit)

```
 bits  0..15   CRC-16/IBM             (16)
 bits 16..31   Amount                 (16)
 bits 32..55   TokenIdentifier (TID)  (24)
 bits 56..59   RandomNo               ( 4)
 bits 60..63   TokenSubClass          ( 4)
```

CRC is computed over `Amount || TID || RandomNo || SubClass || Class`
(48 + 2 bits).

### 64-bit decrypted data block, Class 1 (InitiateMeterTestOrDisplay)

```
 SubClass 0 (8-bit mfg + 36-bit control):
   bits  0..15   CRC-16/IBM             (16)
   bits 16..23   ManufacturerCode       ( 8)
   bits 24..59   Control                (36)
   bits 60..63   TokenSubClass          ( 4)

 SubClass 1 (16-bit mfg + 28-bit control):
   bits  0..15   CRC-16/IBM             (16)
   bits 16..31   ManufacturerCode       (16)
   bits 32..59   Control                (28)
   bits 60..63   TokenSubClass          ( 4)
```

### 66-bit transposed token (displayed form)

The 64-bit encrypted block has its bits 27 and 28 swapped with the
two `TokenClass` bits; the displaced bits are prepended, giving a
66-bit value that is converted to a 20-digit decimal string (BigInt
zero-padded). See `TokenTransposition.transposeToBinary66` /
`untransposeFromBinary66`.

## Quick start

```dart
import 'package:nectar_sts_dart/nectar_sts_dart.dart';

void main() {
  // 1. Vending key + meter identity.
  final hsm = VirtualHsm(VendingCommonDesKey([
    0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF,
  ]));

  // 2. Derive the per-meter decoder key (DKGA-02).
  final decoderKey = hsm.deriveDecoderKeyDkga02(
    issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
    individualAccountIdentificationNumber:
        IndividualAccountIdentificationNumber('12345678901'),
    keyType: KeyType(2),
    supplyGroupCode: SupplyGroupCode('123456'),
    tariffIndex: TariffIndex('07'),
    keyRevisionNumber: KeyRevisionNumber(1),
  );

  // 3. Build + generate an electricity-credit token.
  final ea07 = StandardTransferAlgorithm();
  final token = TransferElectricityCreditToken('req-001')
    ..amountPurchased = Amount(25.0)
    ..tokenIdentifier = TokenIdentifier(BaseDate.date1993)
    ..randomNo = RandomNo.random();
  TransferElectricityCreditTokenGenerator(decoderKey, ea07).generate(token);
  print(token.tokenNo); // 20-digit displayable token

  // 4. Decode it back (meter side).
  final dispatcher = TokenDecoderDispatcher(decoderKey, ea07);
  switch (dispatcher.decodeDecimal('req-001', token.tokenNo)) {
    case DecodeAccepted(:final token):
      final t = token as TransferElectricityCreditToken;
      print('OK: ${t.amountPurchased!.unitsPurchased} kWh');
    case DecodeFailure(:final reason):
      print('REJECTED: $reason');
  }
}
```

A runnable end-to-end CLI is at [bin/demo.dart](bin/demo.dart):

```
dart run bin/demo.dart
dart run bin/demo.dart --amount 12.5 --tid-time 2024-06-01T12:00Z
```

## Decode result API

`TokenDecoderDispatcher.decodeDecimal` returns a sealed
`DecodeResult`:

```dart
sealed class DecodeResult {}
class DecodeAccepted extends DecodeResult { final Token token; ... }
class DecodeFailure  extends DecodeResult { final StsError error; final String reason; ... }
```

This lets callers pattern-match (`switch (r) { ... }`) instead of
wrapping every decode in try/catch. For tests and scripts, the
`decodeOrThrow` extension is provided.

## NectarAPI-compatible params API

`VirtualHsm` also exposes `generateToken` / `decodeToken` that take
a flat `Map<String, dynamic>` whose key names match the JSON request
body accepted by the upstream
[NectarAPI tokens-service](https://github.com/NectarAPI/tokens-service)
`POST /v1/tokens` / `POST /v1/tokens/{tokenNo}` endpoints. This lets
a Dart caller swap a remote service call for a local in-process one
without reshaping the request:

```dart
final hsm = VirtualHsm(VendingCommonDesKey([...8 bytes...]));
final params = <String, dynamic>{
  VirtualHsmParams.decoderKeyGenerationAlgorithm: '02',
  VirtualHsmParams.encryptionAlgorithm: 'sta',
  VirtualHsmParams.keyType: 2,
  VirtualHsmParams.supplyGroupCode: '123456',
  VirtualHsmParams.tariffIndex: '07',
  VirtualHsmParams.keyRevisionNo: 1,
  VirtualHsmParams.issuerIdentificationNo: '600727',
  VirtualHsmParams.decoderReferenceNumber: '12345678901',
  VirtualHsmParams.tokenClass: '0',
  VirtualHsmParams.tokenSubclass: '0',
  VirtualHsmParams.amount: 25.0,
  VirtualHsmParams.tokenId: '2024-06-01T12:00:00Z',
};
final token = hsm.generateToken('req-001', params);
print(token.tokenNo);
final back = hsm.decodeToken('req-001.dec', token.tokenNo, params)
    as TransferElectricityCreditToken;
```

Param keys (string constants on `VirtualHsmParams`) — names exactly
match the Java service:

| Key | Required for | Notes |
| --- | --- | --- |
| `decoder_key_generation_algorithm` | always | `"02"` or `"04"`. `"01"` / `"03"` are not ported. |
| `encryption_algorithm` | always | `"sta"` or `"dea"`. `"misty1"` is not ported. |
| `key_type` | always | int (0–3). |
| `supply_group_code` | always | 6-digit string. |
| `tariff_index` | always | 2-digit string. |
| `key_revision_no` | always | int (1–9). |
| `issuer_identification_no` | always | 6 digits (or 4 digits for legacy IINs). |
| `decoder_reference_number` | always | 11 digits (IAIN portion of the meter PAN). |
| `base_date` | DKGA-04 | `"1993"`, `"2014"`, or `"2035"`. Default `"1993"`. |
| `class`, `subclass` | generate only | `"0,0"`, `"1,0"`, `"1,1"` supported. |
| `amount` | class 0/0 | kWh as double, or numeric string. |
| `token_id` | class 0 | ISO-8601 string or `DateTime`. |
| `random_no` | class 0 (optional) | 4-bit int. Auto-generated when omitted. |
| `manufacturer_code`, `control` | class 1 | ints. Widths inferred from subclass (8+36 vs 16+28). |
| `type` | optional | `"prism-thrift"` is rejected — use `PrismHsm`. |

`Map<String, String>` (the literal Java request body shape) is
accepted as well — int/double-shaped string values are parsed on the
way through.

## HSM

| Implementation | Status | Notes |
| --- | --- | --- |
| `VirtualHsm(VendingKey)` | ✅ working | In-process software HSM. Runs DKGA-02 / DKGA-04 + EA07 directly in Dart — the same role NectarAPI's [api-gateway](https://github.com/NectarAPI/api-gateway) calls its "internal virtual HSM". Use for tests, embedded apps, and any deployment where the vending key may live in process memory. Provides both a typed key-derivation API (`deriveDecoderKeyDkga02/04`) and the params-driven [`generateToken` / `decodeToken`](#nectarapi-compatible-params-api) endpoints. |
| `PrismHsm({host, port, clientCertificate})` | ⛔ stub | Always throws `NotImplementedException`. Mirrors the constructor surface of the Java `PrismHsm` class so the API shape is preserved for downstream code that needs to swap in a real hardware HSM (Utimaco / Thales / PKCS#11) over Thrift later, but no transport is implemented. |

## Virtual meter (customer-side simulator)

Where `VirtualHsm` plays the utility/vending side, [`VirtualMeter`](lib/src/meter/virtual_meter.dart)
plays the customer-side meter. Personalize it once with the same
identity that derives the decoder key, then "punch in" 20-digit
tokens to credit kWh. State (decoder key, kWh balance, applied-token
log) is persisted as a single human-readable JSON file.

| Class | Behaviour |
| --- | --- |
| 0/0 — electricity credit | Adds `amount` kWh to the running balance. Rejects replays (matching TID already in the log). |
| 1/* — meter test / display | Decoded for verification, but not "applied" — balance unchanged. |
| Anything else | Rejected with `ApplyRejected`. |

CLI in [bin/meter.dart](bin/meter.dart):

```powershell
# Provision a fresh meter (writes meter.json)
dart run bin/meter.dart setup `
  --file meter.json `
  --iin 600727 --iain 12345678901 `
  --key-type 2 --sgc 123456 --ti 07 --krn 1 `
  --vending-key-hex 0123456789ABCDEF `
  [--dkga 02|04] [--base-date 2014] `
  [--ea sta|dea] [--balance 0]

# Inspect current state
dart run bin/meter.dart info --file meter.json

# Apply a 20-digit token (rewrites meter.json on success)
dart run bin/meter.dart apply --file meter.json --token 69556367501624534633
```

Sample `meter.json` (trimmed):

```json
{
  "schema": "nectar_sts_dart.virtual_meter/v1",
  "created_at": "2026-06-09T19:37:00.717Z",
  "identity": {
    "issuer_identification_no": "600727",
    "decoder_reference_number": "12345678901",
    "key_type": 2, "supply_group_code": "123456",
    "tariff_index": "07", "key_revision_no": 1,
    "decoder_key_generation_algorithm": "02"
  },
  "decoder_key_hex": "34f223add29cb69a",
  "encryption_algorithm": "sta",
  "balance_kwh": 25.0,
  "applied_tokens": [
    {
      "token_no": "69556367501624534633",
      "amount_kwh": 20.0,
      "tid_minutes": 808784,
      "issued_at": "1994-07-16T15:44:00.000Z",
      "applied_at": "2026-06-09T19:37:42.009Z"
    }
  ]
}
```

Library use directly (e.g. from tests):

```dart
final meter = VirtualMeter.setup(
  identity: const MeterIdentity(
    issuerIdentificationNumber: '600727',
    individualAccountIdentificationNumber: '12345678901',
    keyType: 2, supplyGroupCode: '123456',
    tariffIndex: '07', keyRevisionNumber: 1,
  ),
  vendingKeyBytes: parseHexKey('0123456789ABCDEF'),
  initialBalanceKwh: 0,
  filePath: 'meter.json',
);

final r = meter.applyToken('69556367501624534633');
switch (r) {
  case ApplyAccepted(:final amountKwh, :final newBalanceKwh):
    print('+$amountKwh kWh -> $newBalanceKwh kWh');
  case ApplyReplay(:final tidMinutes):
    print('replay (tid=$tidMinutes)');
  case ApplyNonCredit(:final tokenType):
    print('non-credit token: $tokenType');
  case ApplyRejected(:final reason):
    print('rejected: $reason');
}
meter.save();
```

> **Note on base dates.** A 24-bit TID maxes out at ~31 years past
> its base date. `BaseDate.date1993` rolled over in late 2024 — for
> tokens issued today use `--base-date 2014` (or 2035). Replay
> detection still works either way; only the human-readable
> `issued_at` field is affected.

## HTTP server (MVP — electricity only)

A minimal `shelf`-based HTTP server lives in [bin/server.dart](bin/server.dart),
wrapping `VirtualHsm` in a NectarAPI-compatible REST surface. It is
deliberately scoped to **Class 0 / SubClass 0 electricity-credit
tokens** only; water (0/1), gas (0/2), and Class 2 requests are
rejected with HTTP 501.

Run it:

```powershell
$env:PORT='2000'                                # default 2000
$env:VENDING_KEY_HEX='0123456789ABCDEF'         # 8-byte DES key, hex
$env:NECTAR_API_TOKEN='change-me'               # optional bearer auth
$env:VENDING_LOG_FILE='vending.json'            # audit log (default)
$env:METER_REGISTRY_FILE='meters.json'          # meter registry (default)
dart run bin/server.dart
```

If `NECTAR_API_TOKEN` is unset the API is **open** — fine for local
dev only. If `VENDING_KEY_HEX` is unset a built-in demo key is used
and a warning is printed. Set `VENDING_LOG_FILE=:none:` to disable
the audit log entirely (also disables TID-collision rejection and
the `GET /v1/tokens*` endpoints). Set `METER_REGISTRY_FILE=:none:`
to disable the meter-registry endpoints and the `meter_serial`
shortcut on `POST /v1/tokens`.

Endpoints:

| Method | Path | Body | Purpose |
| --- | --- | --- | --- |
| `GET`    | `/healthz` | — | Liveness probe. Returns `{"status":"ok"}`. |
| `POST`   | `/v1/tokens` | `Map<String, Object>` matching `VirtualHsmParams` **or** `{ "meter_serial": "...", "amount": ..., "token_id": ... }` | Generate a 20-digit token. Appended to the audit log on success. |
| `GET`    | `/v1/tokens[?iin=&iain=]` | — | List every issued token (optionally filtered by meter). |
| `GET`    | `/v1/tokens/{tokenNo}` | — | Look up a previously-issued token in the audit log. |
| `POST`   | `/v1/tokens/{tokenNo}` | same params used to generate | Decode + verify a 20-digit token. |
| `POST`   | `/v1/meters` | `{ "serial": "...", "identity": {...}, "encryption_algorithm": "sta", "subscriber_label": "..." }` | Register a meter under an operator-chosen serial. |
| `GET`    | `/v1/meters` | — | List every registered meter. |
| `GET`    | `/v1/meters/{serial}` | — | Fetch one registered meter. |
| `DELETE` | `/v1/meters/{serial}` | — | Deregister a meter. |

Response envelope (mirrors the upstream Java service):

```json
{
  "status":  { "code": 200, "message": "Token generated" },
  "request_id": "req-hjbndfd95w",
  "data": { "token": [ { "type": "Electricity_00", "token_no": "...", ... } ] }
}
```

Smoke test:

```powershell
$body = @{
  decoder_key_generation_algorithm='02'; encryption_algorithm='sta';
  key_type=2; supply_group_code='123456'; tariff_index='07';
  key_revision_no=1; issuer_identification_no='600727';
  decoder_reference_number='12345678901'; class='0'; subclass='0';
  amount=25.5; token_id='2024-06-01T12:00:00Z'; random_no=7;
  base_date='1993'
} | ConvertTo-Json -Compress
Invoke-RestMethod -Uri 'http://localhost:2000/v1/tokens' -Method Post `
  -ContentType 'application/json' -Body $body
```

Error mapping:

| Condition | HTTP status | `status.code` |
| --- | --- | --- |
| Success | 200 | 200 |
| Bad JSON / missing params / unknown algorithm / `amount <= 0` / `vending_key` in body | 400 | 400 |
| Missing or wrong `Authorization: Bearer …` header | 401 | 401 |
| `GET /v1/tokens*` lookup miss | 404 | 404 |
| TID collision (same meter + same `token_id`) | 409 | 409 |
| Out-of-scope feature (`NotImplementedException`) | 501 | 501 |
| `GET /v1/tokens*` called when no audit log is configured | 503 | 503 |
| Anything else | 500 | 500 |

### Persistence + tightening (for physical-meter testing)

When `VENDING_LOG_FILE` points at a JSON file (default `vending.json`),
the server keeps a [`VendingLog`](lib/src/server/vending_log.dart) on
disk and uses it for three things:

1. **Audit log** — every successful `POST /v1/tokens` appends one
   record (request id, 20-digit token number, meter identity, TID,
   amount, random_no). The vending key and derived decoder key are
   **never** persisted.
2. **TID-collision rejection** — re-issuing the same meter +
   `token_id` (which would mint a token a real meter would silently
   reject as a replay) fails fast with `409 Conflict` and a message
   pointing back at the prior `request_id` / `token_no`.
3. **Lookup** — `GET /v1/tokens/{tokenNo}` returns the audit row
   so a field engineer can ask "what did we mint for that meter?".

The server also enforces two pre-checks before calling the HSM:

- `amount` must be a positive number (for Class 0/0 requests).
- `vending_key` / `decoder_key` are rejected if present in the
  request body — the server only ever uses its own configured key,
  preventing a caller from minting tokens for a meter outside the
  utility's key domain.

Sample `vending.json`:

```json
{
  "schema": "nectar_sts_dart.vending_log/v1",
  "created_at": "2026-06-09T19:50:00.176Z",
  "issues": [{
    "request_id": "req-hjbo01j5u0",
    "token_no": "02215913157043837656",
    "issued_at": "2026-06-09T19:50:02.831Z",
    "iin": "600727", "iain": "12345678901",
    "key_type": 2, "supply_group_code": "123456",
    "tariff_index": "07", "key_revision_no": 1,
    "decoder_key_generation_algorithm": "02",
    "token_class": 0, "token_subclass": 0,
    "amount_kwh": 20.0, "tid_minutes": 6541200, "random_no": 4
  }]
}
```

> **Pair with a physical meter.** Set `VENDING_KEY_HEX` to the same
> vending key your meter was personalized with, mint a token, key it
> into the meter, then `GET /v1/tokens/{tokenNo}` to confirm the
> server-side record matches what the meter accepted (or to diagnose
> a rejection). Use a per-meter `token_id` strictly greater than
> previously-issued TIDs so the meter's own replay-window stays
> happy.

Still out of scope: database-backed persistence (the JSON log is a
flat-file MVP — fine for hundreds of issues, not millions), key
revocation, real hardware-HSM transport, Spring-Security-style RBAC,
water/gas, Class 2. See [README §What's deliberately NOT ported](#whats-deliberately-not-ported).

### Meter registry (single-utility)

For pilots with more than a handful of physical meters, typing the
full identity tuple (IIN / IAIN / KEN / SGC / TI / KRN / DKGA / EA)
on every `POST /v1/tokens` request gets old fast. The meter registry
lets you provision a meter **once** and then vend by an
operator-chosen serial:

```powershell
# 1. Register METER-001 once.
$reg = @{
  serial='METER-001'
  subscriber_label='Acme Bakery'
  encryption_algorithm='sta'
  identity=@{
    issuer_identification_no='600727'
    decoder_reference_number='12345678901'
    key_type=2; supply_group_code='123456'
    tariff_index='07'; key_revision_no=1
    decoder_key_generation_algorithm='02'
  }
} | ConvertTo-Json -Compress -Depth 4
Invoke-RestMethod -Uri 'http://localhost:2000/v1/meters' -Method Post `
  -ContentType 'application/json' -Body $reg

# 2. Vend by serial — the server fills in the identity for you.
$vend = @{
  meter_serial='METER-001'
  class='0'; subclass='0'; amount=20
  token_id='2024-07-01T09:00:00Z'; base_date='1993'
} | ConvertTo-Json -Compress
Invoke-RestMethod -Uri 'http://localhost:2000/v1/tokens' -Method Post `
  -ContentType 'application/json' -Body $vend
```

Rules:

- The registry stores **identity only** — never the vending key.
  Token generation always uses the server's single global
  `VENDING_KEY_HEX`, which matches the **single-utility** model.
- Sending `meter_serial` together with any identity field the
  registry owns is a `400` (the registry is the source of truth).
  For DKGA-02 meters, `base_date` is *not* owned by the registry
  (it's a per-request TID-epoch choice) so it stays in the request.
  For DKGA-04 meters, store the `base_date` in `identity` and the
  registry will own it.
- Unknown `meter_serial` → `404`. Duplicate registration → `409`.
- The audit log row gains a `meter_serial` field whenever a vending
  request used the shortcut, so `GET /v1/tokens/{tokenNo}` can be
  cross-referenced with `GET /v1/meters/{serial}`.

Sample `meters.json`:

```json
{
  "schema": "nectar_sts_dart.meter_registry/v1",
  "created_at": "2026-06-09T20:10:00.000Z",
  "meters": [{
    "serial": "METER-001",
    "registered_at": "2026-06-09T20:10:30.000Z",
    "encryption_algorithm": "sta",
    "subscriber_label": "Acme Bakery",
    "identity": {
      "issuer_identification_no": "600727",
      "decoder_reference_number": "12345678901",
      "key_type": 2, "supply_group_code": "123456",
      "tariff_index": "07", "key_revision_no": 1,
      "decoder_key_generation_algorithm": "02"
    }
  }]
}
```

## Tests

```
dart test
```

Currently 73 tests, covering base layer, DKGA-02 / DKGA-04, EA07/EA09
encryption, Class 0 + Class 1 token round-trips, dispatcher behaviour
(success + structured failure), the params-driven `VirtualHsm`
dispatch surface (including rejection of out-of-scope DKGA-01/03,
MISTY1, Class 2, and `type=prism-thrift`), the `shelf`-based HTTP
API (healthz, generate + decode round-trip, JSON validation,
bearer-token auth, and 501 mapping for out-of-scope classes), the
JSON-backed vending log (audit append, TID-collision rejection,
filtered listing, lookup, sensitive-param rejection, and persistence
across simulated restarts), the meter registry (CRUD, duplicate /
unknown / disabled handling, `meter_serial` vending shortcut with
identity-conflict rejection, and persistence across restarts), and
the `VirtualMeter` simulator (provisioning, balance accrual, replay
rejection, and JSON save/load across restarts).

## Dependencies

This package depends on a local `tls` package (DES + SHA + HMAC
primitives) via a path dependency. See `pubspec.yaml`.

## License & provenance

Algorithm specification: IEC 62055-41 (STS Association, "STS6").

Java reference implementation:
[NectarAPI/tokens-service](https://github.com/NectarAPI/tokens-service)
(check upstream for license terms). This Dart port carries no
warranty.
