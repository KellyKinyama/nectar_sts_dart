# 07 — Compliance, testing & conclusion

[◀ 06 — The virtual HSM & virtual meter](./06-virtual-hsm-and-meter.md) · [TOC](./README.md)

---

We've now traced one token from `VendingUniqueDesKey` through the
20 decimal digits and back to a credited meter balance. This final
chapter looks at how we **prove** the implementation matches the
official IEC 62055-41 / STS6 spec, and where you might take this
codebase next.

## The STS6 conformance vectors

The Standard Transfer Specification ships with a set of *Compliance
Test Suite for Algorithms* (CTSA) reference vectors. Each vector
nails down the exact inputs and expected derived key / expected
token string, so any compliant implementation must produce the same
20 decimal digits down to the last character.

This port reproduces the following STS6 CTSA vectors **bit-exactly**.
All values match the Java upstream
(`NectarAPI/tokens-service`, commit `609cea0`) to the last decimal
digit; see [the compliance reference](./sts_compliance.md) for full
input tables.

### DKGA-02 + EA07 (STA) — [test/sts_compliance_class2_test.dart](../test/sts_compliance_class2_test.dart) (+ the original [test/sts_compliance_test.dart](../test/sts_compliance_test.dart))

| CTSA / Vector                                  | Class / SubClass            | Notes                                               |
| ---------------------------------------------- | --------------------------- | --------------------------------------------------- |
| CTSA01 step1, step2                            | 0/0 TransferElectricityCredit | Also asserts derived key `6ff35b9d1f3453e6`.      |
| CTSA02 step1, step2                            | 1/0, 1/1 InitiateMeterTestOrDisplay | Class 1 emitted in the clear (no encryption). |
| CTSA03 step1                                   | 2/0 SetMaximumPowerLimit    | MPL=1000.                                           |
| CTSA04 step1                                   | 2/1 ClearCredit             | Register-clear token.                               |
| CTSA05 step1, step2                            | 2/3, 2/4 1st/2nd Section Decoder Key | Pair of 64-bit halves for STA key rotation. |
| CTSA06 step1                                   | 2/5 ClearTamperCondition    |                                                     |
| CTSA07 step1                                   | 2/6 SetMaximumPhasePowerUnbalanceLimit |                                          |
| CTSA09 step1, step2, step3 (×3 time-shifted)  | 2/2 SetTariffRate           | Multi-minute series exercised as independent vectors. |
| CTSA12 step1                                   | 2/9 NewTariffRate           |                                                     |
| CTSA13 step1                                   | 2/10 NewMaximumPowerLimit   |                                                     |
| CTSA14 step1                                   | 2/13 RolloverKeyChange      |                                                     |
| CTSA25 step1, step2, step3                     | 0/0 (DKGA-04+STA combo)     | 20-byte vending key, `BaseDate` sweep 1993/2014/2035. |
| Nectar_1                                       | 0/0 vendor amount sweep     | 15 amounts spanning all Amount-encoding ranges.     |

### DKGA-04 + EA11 (MISTY1) — [test/sts_compliance_class2_misty1_test.dart](../test/sts_compliance_class2_misty1_test.dart)

| CTSA / Vector                                  | Class / SubClass            | Notes                                               |
| ---------------------------------------------- | --------------------------- | --------------------------------------------------- |
| CTSA01_04 step1, step4 (×2), step8/9/12/13    | 0/0 TransferElectricityCredit | Electricity steps only.                           |
| CTSA03_04 step1                                | 2/0 SetMaximumPowerLimit    |                                                     |
| CTSA05_04 step1…step4                          | 2/3, 2/4, 2/8, 2/9 4-section KCT | Full 128-bit MISTY1 key-rotation set.          |
| CTSA06_04 step1                                | 2/5 ClearTamperCondition    |                                                     |
| CTSA07_04 step1                                | 2/6 SetMaximumPhasePowerUnbalanceLimit |                                          |
| CTSA09_04 step1, step2, step3 (×3)            | 2/2 SetTariffRate           |                                                     |
| CTSA12_04 step1                                | 2/9 NewTariffRate           |                                                     |
| CTSA13_04 step1                                | 2/10 NewMaximumPowerLimit   |                                                     |
| CTSA14_04 step1                                | 2/13 RolloverKeyChange      |                                                     |
| `TransferElectricityCreditTokenGeneratorTest`  | 0/0 (standalone direct key) | Token `29054347139309851356` from a 25.6 kWh purchase. |

If you change any algorithm-affecting code — `BitString` semantics,
CRC byte-swap, EA07 S-boxes, MISTY1 FI/FL/FO, DKGA-02 byte
reversal, DKGA-04 HMAC chain, transposition, TID rounding — and
CTSA01 step1 still emits `23716100501183194197` AND CTSA01_04
step1 still emits its expected token, you almost certainly haven't
broken anything observable.

## Vectors deliberately **not** ported

| Upstream test                                                  | Why skipped                                                                                                                |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| CTSA01 step3/4 (water) + step5/6 (gas)                         | This port implements electricity only. Water/gas would need `TransferWaterCreditToken` / `TransferGasCreditToken` classes. |
| CTSA01_04 step2/3/6/7/10/11/14/15                              | Same reason — water / gas steps in the MISTY1 sweep.                                                                       |
| CTSA10_04 (Class 1 under DKGA-04 / MISTY1)                     | Not yet transcribed. The Class 1 path itself is correct — see CTSA02 above — only the additional vector ports are pending.|
| CTSA11 (Class 1 STA extended vectors)                          | Not yet transcribed; the generator/decoder are exercised by CTSA02 and the round-trip tests.                               |
| CTSA16_04 (exception path) / CTSA19_04 (mixed scenarios)       | Dart exception types differ in shape; the underlying generators are exercised by other vectors.                            |

The `KeyExpiryNumber` (KEN) parameter that the Java generators
take in their constructor is **not** modelled here. By inspection,
KEN is stored on the Java generator object but never enters the
data block (`crc || amount || tid || rnd || sub` — no KEN) and is
not consumed by DKGA-02 / DKGA-04. Omitting it is bit-compatible,
and the passing CTSA01 step1 derived-key assertion is the proof.

## What else is tested

Beyond the conformance vectors, the suite covers:

| Test file                                                                       | Focus                                                                                       |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| [test/dkga_test.dart](../test/dkga_test.dart)                                   | DKGA-02 and DKGA-04 derivation + EA07 round-trip on a derived key.                          |
| [test/dkga04_misty1_test.dart](../test/dkga04_misty1_test.dart)                 | DKGA-04 derives a 16-byte key for MISTY1 + full EA11 round-trip on the derived key.         |
| [test/encryption_test.dart](../test/encryption_test.dart)                       | EA07 / EA09 round-trip and `Key.getKeyBit` LSB-first semantics.                             |
| [test/misty1_test.dart](../test/misty1_test.dart)                               | MISTY1 (EA11) round-trip + RFC 2994 Appendix A.1 reference vectors + 100-iter LCG fuzz.     |
| [test/base_layer_test.dart](../test/base_layer_test.dart)                       | `BitString`, `Nibble`, CRC-16/IBM, Luhn check digit, `TokenIdentifier`, amount-encoding helpers. |
| [test/meter_pan_parser_test.dart](../test/meter_pan_parser_test.dart)           | `MeterPrimaryAccountNumber.fromString` legacy / generic prefix parsing + validation modes.  |
| [test/token_round_trip_test.dart](../test/token_round_trip_test.dart)           | Generator → 20-digit display → decoder preserves Amount + TID across many random inputs.    |
| [test/class1_and_dispatcher_test.dart](../test/class1_and_dispatcher_test.dart) | Class 1 InitiateMeterTestOrDisplay (both sub-classes) round-trip; multi-class dispatch.     |
| [test/class2_register_tokens_test.dart](../test/class2_register_tokens_test.dart) | Class 2 register family generator/decoder coverage.                                       |
| [test/class2_kct_test.dart](../test/class2_kct_test.dart)                       | Class 2 register family + 1st/2nd Section STA KCT round-trip through the HSM dispatcher.    |
| [test/class2_kct_misty1_test.dart](../test/class2_kct_misty1_test.dart)         | Class 2 3rd/4th Section MISTY1 KCT generator ↔ decoder and 4-section 128-bit key rebuild.   |
| [test/sts_compliance_class2_test.dart](../test/sts_compliance_class2_test.dart) | DKGA-02 + STA CTSA02/03/04/05/06/07/09/12/13/14, CTSA25, Nectar_1 bit-exact vectors.        |
| [test/sts_compliance_class2_misty1_test.dart](../test/sts_compliance_class2_misty1_test.dart) | DKGA-04 + MISTY1 CTSA01/03/05/06/07/09/12/13/14 bit-exact vectors.            |
| [test/virtual_meter_test.dart](../test/virtual_meter_test.dart)                 | Apply → balance update, replay detection, 1st+2nd STA KCT + 4-section MISTY1 KCT rotation, tamper latch, save/load. |
| [test/virtual_hsm_dispatch_test.dart](../test/virtual_hsm_dispatch_test.dart)   | Param-map API matches the upstream Java `tokens-service` contract.                          |
| [test/api_server_test.dart](../test/api_server_test.dart)                       | HTTP — `/v1/tokens`, `/v1/tokens/key-change`, `/v1/tokens/meter-test`, `/v1/meters`, tariff pricing, bearer auth, `X-Request-Id` propagation, vending-log persistence. |
| [test/openapi_spec_test.dart](../test/openapi_spec_test.dart)                   | `GET /openapi.json` is a well-formed OpenAPI 3.0 doc and reachable without bearer auth.     |
| [test/tariff_test.dart](../test/tariff_test.dart)                               | `Tariff.moneyFor` / `kwhFor` inverses, admin-fee math, currency mismatches.                 |
| [test/token_issuer_test.dart](../test/token_issuer_test.dart)                   | `PrismConfig` plumbing on `PrismIssuer` (no network calls).                                 |
| [test/db_store_test.dart](../test/db_store_test.dart)                           | MySQL-backed `DbMeterRegistry` + `DbVendingLog` integration (skipped unless `STS_DB_HOST` is set). |
| [test/prism/thrift_protocol_test.dart](../test/prism/thrift_protocol_test.dart) | Pure encoder/decoder round-trips for the hand-rolled Thrift binary protocol + framed transport. |
| [test/prism/token_api_client_test.dart](../test/prism/token_api_client_test.dart) | `TokenApiClient` end-to-end against an in-process fake Thrift server (signIn + issueCreditToken + exception paths). |
| [test/prism/prism_issuer_test.dart](../test/prism/prism_issuer_test.dart)       | `PrismIssuer.generateToken` mapping back into `TransferElectricityCreditToken`.             |

Total: **431 tests passing** (plus **10 skipped** — the MySQL
integration suite and a handful of env-gated cases), all green on
Dart SDK ≥ 3.4 on Windows/macOS/Linux.

```powershell
# from c:\www\dart\nectar_sts_dart
dart test
# → All tests passed!
```

## Where to go from here

If you want to extend this port, the most useful next steps are
roughly in order of effort:

1. **Water + gas Class 0 sub-classes.** Two new token classes
   (`TransferWaterCreditToken`, `TransferGasCreditToken`) and two
   one-line generator subclasses are enough to make CTSA01 steps
   3..6 (STA) and CTSA01_04 steps 2/3/6/7/10/11/14/15 (MISTY1)
   pass. The Class 0 decoder dispatch also needs to look at the
   sub-class nibble after CRC verification.

2. **Transcribe CTSA10_04 and CTSA11 Class 1 vectors.** The Class 1
   path is now correct (CTSA02 passes bit-exactly); the remaining
   work is just transcribing the extended Java vector tables.

3. **Finish the Prism HSM path.** The hand-rolled Thrift binary
   protocol + framed transport, `TokenApiClient`, and the
   `PrismIssuer` glue layer are in place and exercised end-to-end
   against an in-process fake server
   ([test/prism/](../test/prism/)). What's still missing is the
   typed `Hsm`-interface wrapper — i.e. making the existing
   [`PrismHsm`](../lib/src/hsm/hsm.dart) stub actually call into
   `TokenApiClient` for `deriveDecoderKeyDkga02` /
   `deriveDecoderKeyDkga04` — plus the rest of the Prism
   management RPCs (sign-in lifecycle, key-rotation, audit). Today
   production setups should drive the Prism path via `PrismIssuer`
   on the HTTP server.

4. **Meter state hardening.** The virtual meter uses a naive
   `Set<int>` of applied TIDs. Real meters track a sliding window
   with explicit "min/max accepted minute" and a small bitmap;
   this is the easiest place to harden if you want to use the
   meter sim in fuzz tests.

## Conclusion

STS at the algorithmic level is, in the end, small and self-
contained: a DES-based KDF (DKGA-02) or HMAC-SHA-256 KDF (DKGA-04)
produces a per-meter 64-bit key, a custom 16-round SP-network
(EA07) encrypts a 64-bit data block under that key, a 2-bit class
gets transposed into bits 27/28, and the resulting 66-bit number
prints as 20 decimal digits.

Every spec quirk — the byte-reversal at the end of DKGA-02, the
asymmetric key-bit offset in EA07 encrypt vs decrypt, the
byte-swap inside the CRC, the bit-27/28 splice — is in service of
*one* property: that the same 20 digits, anywhere in the world,
always credit the same number of kWh to the meter the utility
intended them for, and exactly once.

That's the whole nut. Thank you for reading.

---

[◀ 06 — The virtual HSM & virtual meter](./06-virtual-hsm-and-meter.md) · [TOC](./README.md)
