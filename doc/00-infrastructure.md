# 00 — Infrastructure

[◀ TOC](./README.md) · [Next chapter: 01 — The vending key & DKGA-02 ▶](./01-the-vending-key-and-dkga-02.md)

---

## What this package is

`nectar_sts_dart` is the **algorithmic core** of the Java service
[`NectarAPI/tokens-service`](https://github.com/NectarAPI/tokens-service),
re-implemented in pure Dart. The original is a full STS vending
backend (HTTP, database, audit, HSM transport). This port deliberately
keeps only the parts that **produce and decode tokens**, so the
algorithms can be embedded in CLIs, Flutter apps, server-side Dart,
or any test harness without dragging in a Spring Boot stack.

Concretely, in scope:

| Layer                | Files                                                                       |
| -------------------- | --------------------------------------------------------------------------- |
| Bit / byte primitives| [`lib/src/base/`](../lib/src/base/), [`lib/src/util/`](../lib/src/util/)    |
| Domain primitives    | [`lib/src/domain/`](../lib/src/domain/)                                     |
| Keys                 | [`lib/src/keys/`](../lib/src/keys/)                                         |
| Encryption (EA07, EA09, EA11/MISTY1) | [`lib/src/encryption/`](../lib/src/encryption/)             |
| Decoder-key derivation (DKGA-02, DKGA-04) | [`lib/src/decoderkey/`](../lib/src/decoderkey/)        |
| Tokens (Class 0, Class 1, Class 2) | [`lib/src/token/`](../lib/src/token/)                         |
| Generators           | [`lib/src/tokengen/`](../lib/src/tokengen/)                                 |
| Decoders + dispatcher| [`lib/src/tokendec/`](../lib/src/tokendec/)                                 |
| Virtual HSM          | [`lib/src/hsm/`](../lib/src/hsm/)                                           |
| Virtual meter        | [`lib/src/meter/`](../lib/src/meter/)                                       |
| Prism Thrift client  | [`lib/src/prism/`](../lib/src/prism/) — hand-rolled Thrift binary protocol + framed transport + `TokenApiClient` |
| HTTP server          | [`lib/src/server/`](../lib/src/server/) — `shelf`-based REST surface, optional MySQL-backed audit log + meter registry, tariff / pricing, OpenAPI spec, `PrismIssuer` |
| CLI entry points     | [`bin/server.dart`](../bin/server.dart) (HTTP server), [`bin/meter.dart`](../bin/meter.dart) (one-shot meter sim), [`bin/demo.dart`](../bin/demo.dart) (end-to-end demo) |

## What this package is **not**

This port intentionally omits:

- **Class 3 tokens** — reserved by the spec.
- **Class 0 / SubClass 1 (water)** and **Class 0 / SubClass 2 (gas)**.
  STS supports them but this port focuses on electricity.
- **DKGA-01, DKGA-03**.
- **Live Prism HSM driver.** A hand-rolled Thrift binary protocol +
  framed transport ([`lib/src/prism/`](../lib/src/prism/)) and a
  `PrismIssuer` glue layer ([`lib/src/server/token_issuer.dart`](../lib/src/server/token_issuer.dart))
  are in place and tested against an in-process fake server, but
  [`PrismHsm`](../lib/src/hsm/hsm.dart) — the implementation of
  the typed `Hsm` interface that would speak to a real device — is
  still a stub. The end-to-end RPC path is exercised by the
  [test/prism/](../test/prism/) suite.
- **Key revocation lists, multi-tenant ACLs, full vending-station
  dashboard** — out of scope for an algorithm-core package. A
  minimal MySQL-backed audit log + meter registry is provided
  ([`lib/src/server/database.dart`](../lib/src/server/database.dart)
  + siblings) that shares schema with the Laravel `sts-vending`
  dashboard, but it's deliberately small.

Class 1 (InitiateMeterTestOrDisplay), Class 2 (register / KCT
management), DKGA-04 and EA11/MISTY1 **are** all in scope and
bit-exact against the Java upstream — see
[07 — Compliance & conclusion](./07-compliance-and-conclusion.md)
for the ported vector inventory.

## Build & run

Prerequisites:

- Dart SDK **≥ 3.4.0** (uses pattern matching, sealed classes, and
  modern primary-constructor syntax).
- Windows / macOS / Linux — pure Dart, no native deps.
- Optional: MySQL 5.7+ if you want the DB-backed audit log + meter
  registry. Without `STS_DB_HOST` set, everything falls back to
  JSON-file storage and the `test/db_store_test.dart` integration
  suite is skipped.

```powershell
# from c:\www\dart\nectar_sts_dart
dart pub get
dart test
```

Expected output: `All tests passed!` with **431 tests passing**
(plus **10 skipped** — the MySQL integration suite and a handful
of env-gated cases) across **24 test files** (21 in `test/` + 3 in
`test/prism/`).

To run the HTTP server or the standalone meter simulator:

```powershell
# REST server (see bin/server.dart for the full env-var list)
dart run bin/server.dart

# One-shot meter simulator
dart run bin/meter.dart

# Self-contained generate → apply demo
dart run bin/demo.dart
```

The most interesting suites:

| Test file                                                                                       | What it covers                                                                  |
| ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| [test/sts_compliance_test.dart](../test/sts_compliance_test.dart)                               | STS6 reference vectors — the original 3 CTSA01 / standalone bit-exact assertions. |
| [test/sts_compliance_class2_test.dart](../test/sts_compliance_class2_test.dart)                 | DKGA-02 + STA: CTSA01/02/03/04/05/06/07/09/12/13/14, CTSA25, Nectar_1 sweep. |
| [test/sts_compliance_class2_misty1_test.dart](../test/sts_compliance_class2_misty1_test.dart)   | DKGA-04 + MISTY1: CTSA01/03/05/06/07/09/12/13/14 plus 4-section KCT (CTSA05_04). |
| [test/token_round_trip_test.dart](../test/token_round_trip_test.dart)                           | Generate → 20-digit display → decode preserves Amount + TID.                    |
| [test/dkga_test.dart](../test/dkga_test.dart)                                                   | DKGA-02 + DKGA-04 derivation against EA07.                                      |
| [test/dkga04_misty1_test.dart](../test/dkga04_misty1_test.dart)                                 | DKGA-04 derives 16-byte key + full EA11 round-trip on the derived key.          |
| [test/encryption_test.dart](../test/encryption_test.dart)                                       | EA07 / EA09 round-trip + per-byte LSB-first bit accessors.                      |
| [test/misty1_test.dart](../test/misty1_test.dart)                                               | MISTY1 (EA11) RFC 2994 Appendix A.1 reference vectors + 100-iter LCG fuzz.      |
| [test/base_layer_test.dart](../test/base_layer_test.dart)                                       | `BitString`, `Nibble`, CRC-16/IBM, Luhn, `TokenIdentifier` primitives.          |
| [test/meter_pan_parser_test.dart](../test/meter_pan_parser_test.dart)                           | `MeterPrimaryAccountNumber.fromString` legacy / generic / validation cases.     |
| [test/virtual_meter_test.dart](../test/virtual_meter_test.dart)                                 | End-to-end: mint, apply, replay-detect, STA + MISTY1 KCT rotation, persist.     |
| [test/virtual_hsm_dispatch_test.dart](../test/virtual_hsm_dispatch_test.dart)                   | The `Map<String, dynamic>` param API that mirrors the Java service.             |
| [test/api_server_test.dart](../test/api_server_test.dart)                                       | HTTP — `/v1/tokens`, `/v1/tokens/key-change`, `/v1/meters`, tariffs, bearer auth, request-id propagation. |
| [test/openapi_spec_test.dart](../test/openapi_spec_test.dart)                                   | `GET /openapi.json` is well-formed and reachable without auth.                  |
| [test/tariff_test.dart](../test/tariff_test.dart)                                               | `Tariff.moneyFor` / `kwhFor` inverses, admin-fee math, currency checks.         |
| [test/token_issuer_test.dart](../test/token_issuer_test.dart)                                   | `PrismConfig` plumbing on `PrismIssuer` (no network).                           |
| [test/db_store_test.dart](../test/db_store_test.dart)                                           | MySQL-backed `DbMeterRegistry` + `DbVendingLog` integration (skipped when `STS_DB_HOST` is unset). |
| [test/class1_and_dispatcher_test.dart](../test/class1_and_dispatcher_test.dart)                 | Class 1 (InitiateMeterTestOrDisplay) round-trip + multi-class dispatch.         |
| [test/class2_register_tokens_test.dart](../test/class2_register_tokens_test.dart)               | Class 2 register family generator/decoder coverage.                             |
| [test/class2_kct_test.dart](../test/class2_kct_test.dart)                                       | Class 2 1st/2nd Section STA Key Change Token through the HSM dispatcher.        |
| [test/class2_kct_misty1_test.dart](../test/class2_kct_misty1_test.dart)                         | Class 2 3rd/4th Section MISTY1 KCT generator ↔ decoder, 4-section 128-bit key rebuild. |
| [test/prism/thrift_protocol_test.dart](../test/prism/thrift_protocol_test.dart)                 | Pure encoder/decoder tests for the hand-rolled Thrift binary protocol.          |
| [test/prism/token_api_client_test.dart](../test/prism/token_api_client_test.dart)               | `TokenApiClient` end-to-end against an in-process fake Thrift server.           |
| [test/prism/prism_issuer_test.dart](../test/prism/prism_issuer_test.dart)                       | `PrismIssuer.generateToken` mapping back to `TransferElectricityCreditToken`.   |

## Dependency graph

```
              ┌──────────────────────────────────────────┐
              │           nectar_sts_dart.dart           │  (umbrella export)
              └─────────────────┬────────────────────────┘
                                │
   ┌──── server/ ──────────┐    │    ┌──── meter/ ───┐
   │  api_server (shelf),  │◀───┼───▶│ VirtualMeter  │
   │  token_issuer,        │    │    └───────┬───────┘
   │  tariff, openapi_spec,│    │            │
   │  vending_log,         │    │            │
   │  meter_registry,      │    │            │
   │  database / db_*      │    │            │
   └─────┬─────────┬───────┘    │            │
         │         │            │            │
         │         ▼            ▼            │
         │   ┌── prism/ ─────────────────┐   │
         │   │  ThriftBinaryProtocol,    │   │
         │   │  FramedTransport,         │   │
         │   │  TokenApiClient           │   │
         │   └───────────────────────────┘   │
         ▼                                   │
   ┌──── hsm/ ──────────────────────────────┴───┐
   │  Hsm, VirtualHsm, VirtualHsmDispatch,      │
   │  PrismHsm (stub)                           │
   └─────┬──────────┬───────────────────────────┘
         │          │
         ▼          ▼
   ┌─tokengen/─┐ ┌─tokendec/────────────────────────┐
   │ Class0    │ │ Class0/Class1/Class2 decoders +  │
   │ Class1    │ │ TokenDecoderDispatcher           │
   │ Class2    │ │                                  │
   └─────┬─────┘ └─────────────────┬────────────────┘
         │                         │
         ▼                         ▼
   ┌──────────────── token/, domain/, encryption/, decoderkey/, keys/ ──────────────────┐
   │  BitString, Nibble, Crc, EA07 (STA), EA09 (DES/DEA), EA11 (MISTY1),                 │
   │  DKGA-02, DKGA-04, Amount, TokenIdentifier, RandomNo,                               │
   │  TokenClass/SubClass, IIN, IAIN, SGC, TariffIndex, KRN, KeyType,                    │
   │  VendingKey, DecoderKey                                                             │
   └─────────────────────────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
                                ┌────── base/, util/ ──────┐
                                │ Bit, Nibble, BitString,   │
                                │ Luhn, byte/long helpers   │
                                └───────────────────────────┘
```

## The example we'll follow

For the next seven chapters we'll trace a **single token** end-to-end:

| Parameter         | Value                                                         |
| ----------------- | ------------------------------------------------------------- |
| `KeyType`         | `2` (DUTK — Decoder Unique Transfer Key)                      |
| `SupplyGroupCode` | `123456`                                                      |
| `TariffIndex`     | `01`                                                          |
| `KeyRevisionNumber` | `1`                                                         |
| `VendingUniqueDesKey` (hex) | `abababababababab`                                  |
| Meter PAN         | `600727000000000009` → IIN `600727`, IAIN `00000000000`       |
| Time of issue (UTC) | `2004-03-01 13:55:00`                                       |
| `BaseDate`        | `1993`                                                        |
| `RandomNo` (4 bits) | `0x5`                                                       |
| `Amount`          | `0.1 kWh`                                                     |
| Expected derived decoder key (hex) | `6ff35b9d1f3453e6`                           |
| Expected token (20 decimal digits) | `23716100501183194197`                       |

This is *CTSA01 step1* — the first official STS6 conformance vector,
asserted bit-exactly by
[test/sts_compliance_test.dart](../test/sts_compliance_test.dart).

---

[◀ TOC](./README.md) · [Next chapter: 01 — The vending key & DKGA-02 ▶](./01-the-vending-key-and-dkga-02.md)
