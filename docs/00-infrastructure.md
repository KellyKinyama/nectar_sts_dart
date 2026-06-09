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
| Encryption (EA07, EA09) | [`lib/src/encryption/`](../lib/src/encryption/)                          |
| Decoder-key derivation (DKGA-02, DKGA-04) | [`lib/src/decoderkey/`](../lib/src/decoderkey/)        |
| Tokens (Class 0/0, Class 1/0+1) | [`lib/src/token/`](../lib/src/token/)                            |
| Generators           | [`lib/src/tokengen/`](../lib/src/tokengen/)                                 |
| Decoders + dispatcher| [`lib/src/tokendec/`](../lib/src/tokendec/)                                 |
| Virtual HSM          | [`lib/src/hsm/`](../lib/src/hsm/)                                           |
| Virtual meter        | [`lib/src/meter/`](../lib/src/meter/)                                       |
| HTTP MVP             | [`lib/src/server/`](../lib/src/server/) — thin wrapper, not the focus       |

## What this package is **not**

This port intentionally omits:

- **Class 2 tokens** (engineering / set-parameter family: `Pad`,
  `Register`, `MaximumPowerLimit`, `Rate`, `NewKey*`, `RolloverKeyChange`,
  `_3KCT`, etc.). They're large, only used in meter management, and
  cleanly rejected by the dispatcher with `DecodeFailure(NotImplementedException(...))`.
- **Class 3 tokens** — reserved by the spec.
- **Class 0 / SubClass 1 (water)** and **Class 0 / SubClass 2 (gas)**.
  STS supports them but this port focuses on electricity.
- **MISTY1 / EA11**. DKGA-04 itself **is** ported, but only the
  EA07 (STA) output path is implemented — see the explicit
  `NotImplementedException` in
  [`lib/src/decoderkey/dkga04.dart`](../lib/src/decoderkey/dkga04.dart).
- **DKGA-01, DKGA-03**.
- **Real HSM transport** (Prism, Thrift). [`PrismHsm`](../lib/src/hsm/hsm.dart)
  is a stub that documents the API but always throws.
- **Persistent DB, audit log, key revocation lists, REST controllers** —
  out of scope for an algorithm-core package.

## Build & run

Prerequisites:

- Dart SDK **≥ 3.4.0** (uses pattern matching, sealed classes, and
  modern primary-constructor syntax).
- Windows / macOS / Linux — pure Dart, no native deps.

```powershell
# from c:\www\dart\nectar_sts_dart
dart pub get
dart test
```

Expected output: `All tests passed!` with ~76 tests across 8 test
files. The most interesting suites:

| Test file                                                                       | What it covers                                                                  |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| [test/sts_compliance_test.dart](../test/sts_compliance_test.dart)               | STS6 reference vectors ported verbatim from the Java original.                  |
| [test/token_round_trip_test.dart](../test/token_round_trip_test.dart)           | Generate → 20-digit display → decode preserves Amount + TID.                    |
| [test/dkga_test.dart](../test/dkga_test.dart)                                   | DKGA-02 + DKGA-04 derivation against EA07.                                      |
| [test/encryption_test.dart](../test/encryption_test.dart)                       | EA07 / EA09 round-trip + per-byte LSB-first bit accessors.                      |
| [test/virtual_meter_test.dart](../test/virtual_meter_test.dart)                 | End-to-end: mint a token, apply it, replay-detect, persist + reload.            |
| [test/virtual_hsm_dispatch_test.dart](../test/virtual_hsm_dispatch_test.dart)   | The `Map<String, dynamic>` param API that mirrors the Java service.             |
| [test/api_server_test.dart](../test/api_server_test.dart)                       | HTTP MVP — `POST /v1/tokens` round-trip with bearer-token auth.                 |
| [test/class1_and_dispatcher_test.dart](../test/class1_and_dispatcher_test.dart) | Class 1 (InitiateMeterTestOrDisplay) round-trip + multi-class dispatch.         |

## Dependency graph

```
              ┌──────────────────────────────────────────┐
              │           nectar_sts_dart.dart           │  (umbrella export)
              └─────────────────┬────────────────────────┘
                                │
   ┌──── server/ ────┐          │          ┌──── meter/ ───┐
   │  HTTP MVP API   │◀─────────┼─────────▶│ VirtualMeter  │
   └─────────────────┘          │          └───────┬───────┘
                                │                  │
   ┌──── hsm/ ──────────────────┴────────────────┐ │
   │  Hsm, VirtualHsm, VirtualHsmDispatch       │◀┘
   └─────┬──────────┬───────────────────────────┘
         │          │
         ▼          ▼
   ┌─tokengen/─┐ ┌─tokendec/────────────────────────┐
   │ Class0    │ │ Class0/Class1 decoders +         │
   │ Class1    │ │ TokenDecoderDispatcher           │
   └─────┬─────┘ └─────────────────┬────────────────┘
         │                         │
         ▼                         ▼
   ┌──────────────── token/, domain/, encryption/, decoderkey/, keys/ ──────────────────┐
   │  BitString, Nibble, Crc, EA07 (STA), EA09 (DES/DEA), DKGA-02, DKGA-04,              │
   │  Amount, TokenIdentifier, RandomNo, TokenClass/SubClass, IIN, IAIN, SGC,           │
   │  TariffIndex, KRN, KeyType, VendingKey, DecoderKey                                  │
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
