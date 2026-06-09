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

This port reproduces the following vectors **bit-exactly**:

| Test                                                  | Asserts                                                                         |
| ----------------------------------------------------- | ------------------------------------------------------------------------------- |
| CTSA01 step1 — DKGA-02 + EA07                         | Derived key `6ff35b9d1f3453e6` **and** token `23716100501183194197`.            |
| CTSA01 step2 — DKGA-02 + EA07                         | Token `67206107716095682372`.                                                   |
| Standalone `TransferElectricityCreditTokenGeneratorTest` | Token `29054347139309851356` from a direct decoder key + `25.6 kWh` purchase. |

These three are in
[test/sts_compliance_test.dart](../test/sts_compliance_test.dart);
the inputs and expected outputs of each are tabulated in
[the compliance reference](./sts_compliance.md).

If you change any algorithm-affecting code — `BitString` semantics,
CRC byte-swap, EA07 S-boxes, DKGA-02 byte reversal, transposition,
TID rounding — and CTSA01 step1 still emits `23716100501183194197`,
you almost certainly haven't broken anything observable. Treat
that one assertion as the canary.

## Vectors deliberately **not** ported

| Upstream test                                                  | Why skipped                                                                                                                |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| CTSA01 step3 / step4 (water, DKGA-02 + EA07)                   | This port intentionally implements electricity only. Water/gas would need `TransferWaterCreditToken` / generator classes.  |
| CTSA01 step5 / step6 (gas, DKGA-02 + EA07)                     | Same as above.                                                                                                             |
| All steps of `STSComplianceTests_STS_531_1_0_04_CTSA01`        | Uses MISTY1 (EA11) for both key derivation and token encryption; MISTY1 is out of scope. See `lib/src/decoderkey/dkga04.dart`. |

The `KeyExpiryNumber` (KEN) parameter that the Java generators
take in their constructor is **not** modelled here. By inspection,
KEN is stored on the Java generator object but never enters the
data block (`crc || amount || tid || rnd || sub` — no KEN) and is
not consumed by DKGA-02. Omitting it is bit-compatible, and the
passing CTSA01 step1 derived-key assertion is the proof.

## What else is tested

Beyond the conformance vectors, the suite covers:

| Test file                                                                       | Focus                                                                                       |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| [test/dkga_test.dart](../test/dkga_test.dart)                                   | DKGA-02 and DKGA-04 derivation + EA07 round-trip on a derived key.                          |
| [test/encryption_test.dart](../test/encryption_test.dart)                       | EA07 / EA09 round-trip and `Key.getKeyBit` LSB-first semantics.                             |
| [test/base_layer_test.dart](../test/base_layer_test.dart)                       | `BitString`, `Nibble`, byte-array helpers.                                                  |
| [test/token_round_trip_test.dart](../test/token_round_trip_test.dart)           | Generator → 20-digit display → decoder preserves Amount + TID across many random inputs.    |
| [test/class1_and_dispatcher_test.dart](../test/class1_and_dispatcher_test.dart) | Class 1 InitiateMeterTestOrDisplay (both sub-classes) round-trip; multi-class dispatch.     |
| [test/virtual_meter_test.dart](../test/virtual_meter_test.dart)                 | Apply → balance update, replay detection, corrupted-token rejection, save/load persistence. |
| [test/virtual_hsm_dispatch_test.dart](../test/virtual_hsm_dispatch_test.dart)   | Param-map API matches the upstream Java `tokens-service` contract.                          |
| [test/api_server_test.dart](../test/api_server_test.dart)                       | HTTP MVP — `POST /v1/tokens` + `POST /v1/tokens/{tokenNo}` with bearer-token auth.          |

Total: about **76 tests across 8 files**, all passing on Dart SDK
≥ 3.4 on Windows/macOS/Linux.

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
   3..6 pass. A previous iteration did this — see the commit
   history — but it was rolled back to keep the scope electricity-
   only. The Class 0 decoder dispatch also needs to look at the
   sub-class nibble after CRC verification.

2. **MISTY1 (EA11).** Implementing MISTY1 unlocks the full
   `STSComplianceTests_STS_531_1_0_04_CTSA01` set and finishes the
   DKGA-04 story. The cipher is small (~300 lines in C/Java) but
   the spec is paywalled; clean-room reference is
   [RFC 2994](https://www.rfc-editor.org/rfc/rfc2994).

3. **Class 2 management tokens.** Large surface area (`NewKey*`,
   `RolloverKeyChange`, `Rate`, `MaximumPowerLimit`, `_3KCT`, …)
   but the framework — class dispatch, transposition, CRC, EA07 —
   is already in place; each new sub-class is just a data-block
   layout + a generator + a decoder.

4. **Real HSM transport.** Today `PrismHsm` is a stub. Wiring it
   to a real Prism HSM (or Thales / Utimaco equivalent) over
   Thrift is mostly RPC glue, but is what would make the port
   usable as a production vending backend.

5. **Meter state hardening.** The virtual meter uses a naive
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
