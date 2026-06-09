# STS compliance tests

This document describes the STS6 compliance test vectors ported from the
upstream Java reference implementation
[`NectarAPI/tokens-service`](https://github.com/NectarAPI/tokens-service)
(branch `master`, commit `609cea0`) into this Dart port, and the
deliberate scope decisions taken during the port.

Compliance vectors live in [test/sts_compliance_test.dart](../test/sts_compliance_test.dart).

## Scope

This Dart port intentionally implements **electricity-only** Class 0
credit-transfer tokens (Class 0 / SubClass 0). Water (SubClass 1) and
gas (SubClass 2) Class 0 tokens are deliberately **not** ported.

| Upstream Java test                                            | DKGA      | Encryption | Coverage in Dart port                                                                                            |
| ------------------------------------------------------------- | --------- | ---------- | ---------------------------------------------------------------------------------------------------------------- |
| `STSComplianceTests_STS_531_1_0_02_CTSA01.step1Test`          | DKGA-02   | EA07 / STA | **Ported.** Asserts both derived key (`6ff35b9d1f3453e6`) and token (`23716100501183194197`).                    |
| `STSComplianceTests_STS_531_1_0_02_CTSA01.step2Test`          | DKGA-02   | EA07 / STA | **Ported.** Asserts token `67206107716095682372`.                                                                |
| `STSComplianceTests_STS_531_1_0_02_CTSA01.step3..step6`       | DKGA-02   | EA07 / STA | **Skipped.** Water / gas variants — no water/gas token classes or generators in this port (electricity only).    |
| `STSComplianceTests_STS_531_1_0_04_CTSA01.*` (all steps)      | DKGA-04   | EA11 / MISTY1 | **Skipped.** Upstream uses `Misty1AlgorithmEncryptionAlgorithm` for both key derivation and token encryption; MISTY1 is out of scope here (see [lib/src/decoderkey/dkga04.dart](../lib/src/decoderkey/dkga04.dart)). |
| `TransferElectricityCreditTokenGeneratorTest` (standalone)    | n/a (direct decoder key) | EA07 / STA | **Ported.** Asserts token `29054347139309851356`.                                                                |

## Ported test vectors

All three ported tests pass bit-exactly against upstream Java.

### CTSA01 step1 — DKGA-02 + EA07/STA

Common CTSA01 setup (from upstream `@Before`):

| Parameter           | Value                                  |
| ------------------- | -------------------------------------- |
| `KeyType`           | `2`                                    |
| `SupplyGroupCode`   | `"123456"`                             |
| `TariffIndex`       | `"01"`                                 |
| `KeyRevisionNumber` | `1`                                    |
| `VendingUniqueDesKey` (hex) | `abababababababab`             |
| `KeyExpiryNumber`   | `255` (see note below)                 |

Step1-specific inputs:

| Parameter             | Value                       |
| --------------------- | --------------------------- |
| Meter PAN             | `600727000000000009`        |
| IIN / IAIN            | `600727` / `00000000000`    |
| Time of issue (UTC)   | `2004-03-01 13:55:00`       |
| `BaseDate`            | `1993`                      |
| `RandomNo` (4 bits)   | `0x5`                       |
| `Amount`              | `0.1 kWh`                   |

Expected (bit-exact, asserted by the Dart test):

- Derived decoder key (hex): `6ff35b9d1f3453e6`
- Token (20-digit decimal): `23716100501183194197`

### CTSA01 step2 — DKGA-02 + EA07/STA

Step2 differs from step1 only in PAN and time of issue:

| Parameter             | Value                       |
| --------------------- | --------------------------- |
| Meter PAN             | `000001000000000082`        |
| IIN / IAIN            | `000001` / `00000000008`    |
| Time of issue (UTC)   | `2004-03-01 14:00:00`       |

Expected token: `67206107716095682372`.

### Standalone — direct decoder key + EA07/STA

| Parameter             | Value                                       |
| --------------------- | ------------------------------------------- |
| `DecoderKey` (hex)    | `896745f3de12bc0a` (8 bytes, supplied directly) |
| Time of issue (UTC)   | `1996-03-25 13:55:22`                       |
| `BaseDate`            | `1993`                                      |
| `RandomNo` (4 bits)   | `0xB`                                       |
| `Amount`              | `25.6 kWh`                                  |

Expected token: `29054347139309851356`.

## Implementation notes

### `KeyExpiryNumber` (KEN) is not modelled

Upstream Java passes `new KeyExpiryNumber(255)` to every Class 0 token
generator constructor. We inspected the Java source and confirmed:

- KEN is **not** included in the 64-bit Class 0 data block
  (`crc || amount || tid || rnd || sub` — KEN is absent).
- KEN is **not** consumed by DKGA-02 derivation.

KEN is stored on the Java generator object but never affects the token
bits. Omitting it in this Dart port is therefore bit-compatible — the
passing CTSA01 step1 derived-key assertion (`6ff35b9d1f3453e6`) is the
empirical proof.

### Date / time parsing

Upstream uses Joda `DateTimeFormat.forPattern("dd/MM/yyyy HH:mm:ss").parseDateTime()`
in the JVM's default time zone. The Dart tests construct the equivalent
`DateTime.utc(...)`; this is consistent with `TokenIdentifier`'s internal
conversion to UTC (see [lib/src/domain/token_identifier.dart](../lib/src/domain/token_identifier.dart)).

### Why DKGA-04 CTSA01 is excluded

The upstream `STSComplianceTests_STS_531_1_0_04_CTSA01` constructs
both the decoder-key generator and the token generator with
`Misty1AlgorithmEncryptionAlgorithm`. Because MISTY1 (EA11) is not
implemented in this port (see the explicit `NotImplementedException`
path in [lib/src/decoderkey/dkga04.dart](../lib/src/decoderkey/dkga04.dart)),
the DKGA-04 CTSA01 vectors cannot be reproduced here. The DKGA-04
implementation itself **is** ported and is exercised against EA07
vectors elsewhere in the test suite (see
[test/dkga_test.dart](../test/dkga_test.dart)).

## Running the tests

Full regression suite:

```powershell
dart test
```

Just the compliance vectors:

```powershell
dart test test/sts_compliance_test.dart
```

Both should report all tests passing.
