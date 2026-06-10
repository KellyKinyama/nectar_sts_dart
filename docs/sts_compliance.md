# STS compliance tests

This document is the index of STS6 compliance vectors ported from the
upstream Java reference implementation
[`NectarAPI/tokens-service`](https://github.com/NectarAPI/tokens-service)
(branch `master`, commit `609cea0`) into this Dart port.

The vectors live in three files:

- [test/sts_compliance_test.dart](../test/sts_compliance_test.dart) —
  the original three "canary" assertions (CTSA01 step1/step2 + the
  standalone direct-key generator test).
- [test/sts_compliance_class2_test.dart](../test/sts_compliance_class2_test.dart) —
  the DKGA-02 + EA07/STA broad sweep (Class 0, Class 1, Class 2,
  DKGA-04+STA via CTSA25, and the Nectar_1 amount sweep).
- [test/sts_compliance_class2_misty1_test.dart](../test/sts_compliance_class2_misty1_test.dart) —
  the DKGA-04 + EA11/MISTY1 sweep (Class 0 + Class 2 + the 4-section
  KCT).

All ported tests match the Java upstream to the last decimal digit.

## Scope

This Dart port implements **electricity-only** Class 0 credit-transfer
tokens (Class 0 / SubClass 0). Water (SubClass 1) and gas (SubClass 2)
Class 0 tokens are deliberately **not** ported — the steps that
exercise them are skipped in the ported CTSA files and called out
inline.

Both DES-based DKGA-02 + EA07 (STA) **and** HMAC/MISTY1-based DKGA-04 +
EA11 derivation/encryption paths are implemented and asserted bit-exact
against the spec vectors.

## Ported vectors

### DKGA-02 + EA07 (STA)

Standard CTSA*_02 setup (from upstream `@Before`):

| Parameter           | Value                                                            |
| ------------------- | ---------------------------------------------------------------- |
| `KeyType`           | `2`                                                              |
| `SupplyGroupCode`   | `"123456"`                                                       |
| `TariffIndex`       | `"01"`                                                           |
| `KeyRevisionNumber` | `1`                                                              |
| `VendingUniqueDesKey` (hex) | `abababababababab`                                       |
| `KeyExpiryNumber`   | `255` (see note below)                                           |
| Meter PAN           | `600727000000000009` (IIN=`600727`, IAIN=`00000000000`)           |
| `BaseDate`          | `1993`                                                           |
| `RandomNo`          | `0x5` unless noted                                               |

| Upstream Java test                                            | Class / SubClass         | Coverage |
| ------------------------------------------------------------- | ------------------------ | -------- |
| `CTSA01.step1`                                                | 0/0 TransferElectricityCredit | **Ported.** Also asserts derived key `6ff35b9d1f3453e6` and token `23716100501183194197`. |
| `CTSA01.step2`                                                | 0/0                      | **Ported.** Token `67206107716095682372`. |
| `CTSA01.step3..step6` (water, gas)                            | 0/1, 0/2                 | **Skipped** — electricity-only port. |
| `CTSA02.step1`                                                | 1/0 InitiateMeterTestOrDisplay1 | **Ported.** Token `56493153725450313471` (Class 1 emitted in the clear). |
| `CTSA02.step2`                                                | 1/1 InitiateMeterTestOrDisplay2 | **Ported.** Token `02305843005052951967`. |
| `CTSA03.step1`                                                | 2/0 SetMaximumPowerLimit | **Ported.** MPL=1000, token `50901894209860263092`. |
| `CTSA04.step1`                                                | 2/1 ClearCredit          | **Ported.** Token `29511990995826640868`. |
| `CTSA05.step1, step2`                                         | 2/3, 2/4 1st/2nd Section Decoder Key | **Ported.** STA key-rotation pair (64-bit halves). |
| `CTSA06.step1`                                                | 2/5 ClearTamperCondition | **Ported.** |
| `CTSA07.step1`                                                | 2/6 SetMaximumPhasePowerUnbalanceLimit | **Ported.** |
| `CTSA09.step1, step2, step3` (×3 time-shifted re-issues)      | 2/2 SetTariffRate        | **Ported.** Multi-minute series as independent vectors. |
| `CTSA11`                                                      | 1/x extended Class 1     | **Not yet transcribed.** Class 1 path itself is correct (see CTSA02). |
| `CTSA12.step1`                                                | 2/9 NewTariffRate        | **Ported.** |
| `CTSA13.step1`                                                | 2/10 NewMaximumPowerLimit| **Ported.** |
| `CTSA14.step1`                                                | 2/13 RolloverKeyChange   | **Ported.** |
| `CTSA25.step1, step2, step3`                                  | 0/0 (DKGA-04 + STA combo) | **Ported.** 20-byte vending key, SGC=`123457`, baseDate sweep 1993 / 2014 / 2035. |
| `STSComplianceTests_Nectar_1`                                 | 0/0 vendor amount sweep  | **Ported.** 15 amounts spanning every Amount-encoding range. |
| `TransferElectricityCreditTokenGeneratorTest` (standalone)    | 0/0 direct decoder key   | **Ported.** Token `29054347139309851356`. |

### DKGA-04 + EA11 (MISTY1)

Standard CTSA*_04 setup:

| Parameter           | Value                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------- |
| `KeyType`           | `2`                                                                                     |
| `SupplyGroupCode`   | `"123457"` *(note: 123457, not 123456)*                                                 |
| `TariffIndex`       | `"01"`                                                                                  |
| `KeyRevisionNumber` | `1`                                                                                     |
| `VendingUniqueDesKey` (hex, 20 B) | `abababababababab949494949494949401234567`                                |
| `KeyExpiryNumber`   | `255`                                                                                   |
| Meter PAN           | `600727000000000009`                                                                    |
| `BaseDate`          | `1993`                                                                                  |
| EncryptionAlgorithm | MISTY1 (EA11)                                                                           |

| Upstream Java test                                            | Class / SubClass         | Coverage |
| ------------------------------------------------------------- | ------------------------ | -------- |
| `CTSA01_04.step1, step4 (×2), step8, step9, step12, step13`   | 0/0 TransferElectricityCredit | **Ported** (electricity steps). |
| `CTSA01_04.step2/3/6/7/10/11/14/15`                            | 0/1, 0/2                 | **Skipped** — water / gas. |
| `CTSA03_04.step1`                                             | 2/0 SetMaximumPowerLimit | **Ported.** |
| `CTSA05_04.step1..step4`                                      | 2/3, 2/4, 2/8, 2/9 4-section KCT | **Ported.** Full 128-bit MISTY1 key-rotation set. |
| `CTSA06_04.step1`                                             | 2/5 ClearTamperCondition | **Ported.** |
| `CTSA07_04.step1`                                             | 2/6 SetMaximumPhasePowerUnbalanceLimit | **Ported.** |
| `CTSA09_04.step1, step2, step3` (×3)                          | 2/2 SetTariffRate        | **Ported.** |
| `CTSA10_04`                                                   | 1/x Class 1 under MISTY1 | **Not yet transcribed.** Class 1 path itself is correct (CTSA02). |
| `CTSA12_04.step1`                                             | 2/9 NewTariffRate        | **Ported.** |
| `CTSA13_04.step1`                                             | 2/10 NewMaximumPowerLimit| **Ported.** |
| `CTSA14_04.step1`                                             | 2/13 RolloverKeyChange   | **Ported.** |
| `CTSA16_04` (exception scenarios)                             | n/a                      | **Skipped** — Dart exception types differ in shape. |
| `CTSA19_04` (mixed)                                           | n/a                      | **Skipped** — deferred. |

## Implementation notes

### `KeyExpiryNumber` (KEN) is not modelled

Upstream Java passes `new KeyExpiryNumber(255)` to every token
generator constructor. By inspection:

- KEN is **not** included in any 64-bit data block layout
  (`crc || amount || tid || rnd || sub` for Class 0;
  `crc || payload || sub` for Class 2 — KEN is absent in both).
- KEN is **not** consumed by DKGA-02 or DKGA-04.

KEN is stored on the Java generator object but never affects the
token bits. Omitting it in this Dart port is therefore bit-compatible
— the passing CTSA01 step1 derived-key assertion (`6ff35b9d1f3453e6`)
is the empirical proof.

### Class 1 tokens are emitted in the clear

Per IEC 62055-41 §8.4 (and the Java upstream's `Meter.decodeNative`),
Class 1 InitiateMeterTestOrDisplay tokens skip the encryption /
decryption step entirely. The 64-bit `crc || manufacturerCode ||
control || subClass` data block is transposed directly to the
66-bit token-no representation. This lets meters execute display
and self-test commands without holding the decoder key.

The Dart `Class1TokenGenerator.generate()` and `Class1TokenDecoder`
follow this rule. The `DecoderKey` / `EncryptionAlgorithm`
constructor arguments are retained for API symmetry with Class 0 /
Class 2 but are unused on the Class 1 path.

### Date / time parsing

Upstream uses Joda `DateTimeFormat.forPattern("dd/MM/yyyy HH:mm:ss").parseDateTime()`
in the JVM's default time zone. The Dart tests construct the
equivalent `DateTime.utc(...)`; this is consistent with
`TokenIdentifier`'s internal conversion to UTC (see
[lib/src/domain/token_identifier.dart](../lib/src/domain/token_identifier.dart)).

## Running the tests

Full regression suite (all 227 tests):

```powershell
dart test
```

Just the compliance vectors:

```powershell
dart test test/sts_compliance_test.dart test/sts_compliance_class2_test.dart test/sts_compliance_class2_misty1_test.dart
```

All should report passing.
