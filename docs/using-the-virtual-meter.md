# Using `VirtualMeter` — operator's guide

[TOC](./README.md)

---

[`VirtualMeter`](../lib/src/meter/virtual_meter.dart) is a
software stand-in for a real STS prepaid-electricity meter. This
guide answers the practical questions that don't fit the
narrative chapters:

- *Can I decode real utility tokens with it?*
- *What do I have to provide to provision a meter?*
- *What outcomes can `applyToken` return?*
- *How do decoder-key rotations work end to end?*
- *Where does this differ from the JavaScript "PLN-METER" demo?*

If you want the architectural tour first, read
[06 — The virtual HSM & virtual meter](./06-virtual-hsm-and-meter.md).

## Can I use it with real utility tokens?

**Technically yes, in practice almost certainly no.**

`VirtualMeter` will decode any STS token that satisfies these
conditions:

| Prerequisite | Why it's required |
| --- | --- |
| You hold the same vending key — or the per-meter decoder key — that the utility used | The token's 64-bit data block is DES- or MISTY1-encrypted under the meter's derived decoder key. Without the key, decryption produces 64 random bits that fail the CRC check. |
| Identical `KRN`, `KT`, `TI`, `SGC`, `BaseDate`, `MeterPAN` (`IIN` + `IAIN`) | These all feed the [DKGA-02 / DKGA-04 derivation](../lib/src/decoderkey/). One field wrong → wrong decoder key → garbage decrypt. |
| KGA is DKGA-02 (DES) or DKGA-04 (MISTY1) | DKGA-01 and DKGA-03 are not ported. `VirtualMeter.setup` throws [`InvalidDecoderKeyGenerationAlgorithm`](../lib/src/decoderkey/decoder_key_generator_exception.dart) for those. |
| EA is EA-07 (STA / DES) or EA-11 (MISTY1) | Other encryption algorithms (e.g. AES variants in newer STS revisions) are not implemented. |
| Token class is supported | Class 0/0 credit tokens decode and update the balance. Class 1 returns `ApplyNonCredit`. Class 2 management tokens are staged or applied per type (see below). |

Real utility-issued tokens (PLN, KPLC, Eskom, …) **don't satisfy
condition 1**: the vending key is generated and stored inside a
tamper-resistant HSM in the utility's vault and never leaves it.
Meters are personalised at the factory by feeding that HSM each
meter's identity, then writing the derived decoder key into the
meter's secure storage. You as a downstream consumer don't have
the vending key and don't have a path to obtain it — that's the
whole security model of STS.

So this library is useful when you're on **either side of the
HSM**:

- the utility / vendor / CA running the vending system, or
- a vendor or integrator doing authorised end-to-end testing
  against a development / pre-production vending key.

It is **not** useful for "let me decode the token my power
company gave me to see what's inside" — that's the threat model
STS was designed to defeat.

## Provisioning a meter

There are two factories on [`VirtualMeter`](../lib/src/meter/virtual_meter.dart).

### From a vending key (factory personalisation)

This is what a utility's factory step does: hand the meter a
copy of the vending key plus its identity, let the meter derive
its own decoder key.

```dart
import 'dart:typed_data';
import 'package:nectar_sts_dart/nectar_sts_dart.dart';

final meter = VirtualMeter.setup(
  identity: MeterIdentity(
    issuerIdentificationNumber: '600727',
    individualAccountIdentificationNumber: '0000000009',
    keyType: 2,
    supplyGroupCode: '123457',
    tariffIndex: '01',
    keyRevisionNumber: 1,
    decoderKeyGenerationAlgorithm: '04', // or '02'
    baseDate: '1993',                    // required for DKGA-04
  ),
  vendingKeyBytes: Uint8List.fromList([
    0xab, 0xab, 0xab, 0xab, 0xab, 0xab, 0xab, 0xab,
    0x94, 0x94, 0x94, 0x94, 0x94, 0x94, 0x94, 0x94,
    0x01, 0x23, 0x45, 0x67, // DKGA-04 needs the 20-byte VUDK
  ]),
  encryptionAlgorithm: 'misty1', // 'sta' for DES, 'misty1' for MISTY1
  filePath: 'meter-600727.json', // optional — enables save() / fromJson()
);
```

### From a pre-derived decoder key

If your provisioning HSM emits decoder keys directly (e.g. you
pulled them from a CA database), construct `VirtualMeter`
yourself with the 8-byte decoder key:

```dart
final meter = VirtualMeter(
  identity: identity,
  decoderKeyBytes: Uint8List.fromList(decoderKeyHex),
  encryptionAlgorithmName: 'sta',
  filePath: 'meter-600727.json',
);
```

### Persisting and reloading

```dart
meter.save();                                  // writes filePath
final loaded = VirtualMeter.fromJson(
  jsonDecode(File('meter-600727.json').readAsStringSync()),
  filePath: 'meter-600727.json',
);
```

The JSON snapshot includes the decoder key, balance, applied-token
log, tamper flag, staged KCT halves, and current management-token
limits.

## Applying a token

The single interesting method is
[`applyToken(String tokenNo)`](../lib/src/meter/virtual_meter.dart),
which decodes the 20-digit token via the dispatcher and returns
a sealed [`ApplyResult`](../lib/src/meter/virtual_meter.dart):

| Result | When | Side-effects |
| --- | --- | --- |
| `ApplyAccepted(amountKwh, newBalanceKwh, tidMinutes, issuedAt)` | Class 0/0 credit token, valid CRC, not a replay | Balance updated, TID logged |
| `ApplyReplay(tidMinutes)` | TID already in the applied-tokens log | None — balance unchanged |
| `ApplyNonCredit(tokenType)` | Class 1 (meter-test/display) decoded cleanly | TID logged, balance unchanged |
| `ApplyRejected(reason)` | Bad CRC, wrong key, non-numeric, unsupported class, etc. | None |
| `ApplyKeyChange1stStaged({…})` | Class 2/3 STA section arrived | Half stashed, awaits the 2nd section |
| `ApplyKeyChange2ndStaged({…})` | Class 2/4 STA section arrived | Half stashed, awaits the 1st section |
| `ApplyKeyChange3rdStaged({…})` | Class 2/8 MISTY1 section arrived | Quarter stashed, awaits the other three |
| `ApplyKeyChange4thStaged({…})` | Class 2/9 MISTY1 section arrived | Quarter stashed, awaits the other three |
| `ApplyKeyRotated({newKeyRevisionNumber, newKeyType, keyExpiryNumber, newTariffIndex, rolloverKeyChange, newSupplyGroupCode?})` | All required sections (2 for STA, 4 for MISTY1) present | Decoder key replaced, KRN/KT/TI/SGC updated |

Pattern-matching usage:

```dart
switch (meter.applyToken(tokenNo)) {
  case ApplyAccepted(:final amountKwh, :final newBalanceKwh):
    print('Credited $amountKwh kWh, balance now $newBalanceKwh');
  case ApplyReplay():
    print('Token already used.');
  case ApplyRejected(:final reason):
    print('Rejected: $reason');
  case ApplyKeyRotated(:final newKeyRevisionNumber):
    print('Decoder key rotated to KRN $newKeyRevisionNumber');
  case final r:
    print('Other outcome: ${r.runtimeType}');
}
```

After an accepted credit token, `meter.balanceKwh` reflects the
new balance and `meter.appliedTokens` has the new
[`AppliedTokenRecord`](../lib/src/meter/virtual_meter.dart)
appended. `meter.save()` is not automatic — call it yourself.

## Replay detection

The applied-tokens log is keyed on **TID (token identifier in
minutes since BaseDate)**, not on the literal 20-digit string. So
a token presented twice — whether typed in twice by the customer
or replayed by an attacker — produces an `ApplyReplay` the second
time even if it was re-encoded with different padding.

A real meter holds a sliding TID window (older entries roll off);
this simulator stores the full set for clarity.

## Decoder-key rotation

The Class 2 KCT (Key Change Token) family ships the new decoder
key to the meter in **two halves** (STA) or **four quarters**
(MISTY1). `VirtualMeter` stashes each section as it arrives and
calls [`_tryRotate()`](../lib/src/meter/virtual_meter.dart) when
the complete set is present. Once rotation completes, the next
credit token must be encrypted under the new key — older tokens
issued before the rotation are rejected (`ApplyRejected: wrong
key / CRC fail`) unless their TID is already in the applied log.

The expected order is **interleaved-safe**: sections can arrive
in any order, but the meter only rotates when it has all halves
for the same target KEN.

## Tamper

[`meter.tripTamper()`](../lib/src/meter/virtual_meter.dart) sets
the internal `tamperLatched` flag. Once latched, credit tokens
still apply normally but the meter records the tamper condition
until a Class 2/5 `ClearTamperConditionToken` is applied. The
tamper bit is persisted in the JSON snapshot.

## Security caveats

- **No HSM.** The decoder key lives in process memory and on
  disk in plaintext JSON. Don't use `VirtualMeter` for production
  meter personalisation — use a real HSM and write the key into
  secure-element storage on the meter.
- **No physical anti-tamper.** `tripTamper()` is a software hook
  for testing; real meters detect chassis intrusion in hardware.
- **No clock validation.** TIDs are accepted as-is. A real meter
  also enforces "TID not too far in the future" against its RTC.
- **No KEN enforcement.** Key Expiry Number bookkeeping is
  exposed by the rotation events but not used to reject
  past-expiry tokens.

These are deliberate scope choices: the goal is a deterministic
software simulator suitable for compliance testing and vending
integration, not a meter you would ship to a customer.

## Comparison with `PLN-METER-TOKEN-STS-PREPAID-JS`

A common question is how this library compares to
[dannyjiustian/PLN-METER-TOKEN-STS-PREPAID-JS](https://github.com/dannyjiustian/PLN-METER-TOKEN-STS-PREPAID-JS),
a Node.js demo also positioned as an "STS meter simulator".

| Concern | JS demo (`v2.0`) | `nectar_sts_dart` |
| --- | --- | --- |
| Spec adherence | STS-*flavoured* tutorial derived from Mwangi Patrick's Medium series | Targets IEC 62055-41 / STS-531 reference CTSA vectors |
| KGAs | One ad-hoc DKGA-shaped routine (does not match STS 600 DKGA-02 bit layout) | DKGA-02 + DKGA-04, byte-exact against the Java reference |
| EAs | DES only | DES (EA-07) and MISTY1 (EA-11) |
| Token classes | Class 0/0 only | Class 0/0, Class 1, Class 2 (registers + 2-section + 4-section KCT) |
| "Meter" state | One shared `oldActiveToken.json` keyed by serial; stores `[token strings used] + last_kWh` | Per-meter JSON: decoder key, KRN/KT/TI/SGC, balance, TID log, tamper, staged KCT halves, MPL/MPPUL |
| Replay detection | Literal 20-digit-string match | TID-based, matching the spec |
| Decoder-key rotation | Not implemented | STA 2-section and MISTY1 4-section, full state machine |
| Test suite | None | 339 passing compliance vectors against the Java/BouncyCastle reference |
| Will it decode a real STS-compliant token? | No (DKGA does not match the spec) | Yes — given the correct vending or decoder key |

The JS demo is an excellent didactic CLI for *seeing* the shape
of an STS token. This library is a spec-faithful library and
test fixture for *building* an STS vending system.

## Worked example: round-trip in 30 lines

```dart
import 'dart:typed_data';
import 'package:nectar_sts_dart/nectar_sts_dart.dart';

void main() {
  final vudk = Uint8List.fromList([
    0xab, 0xab, 0xab, 0xab, 0xab, 0xab, 0xab, 0xab,
  ]);
  final identity = MeterIdentity(
    issuerIdentificationNumber: '600727',
    individualAccountIdentificationNumber: '0000000009',
    keyType: 2,
    supplyGroupCode: '123456',
    tariffIndex: '01',
    keyRevisionNumber: 1,
    decoderKeyGenerationAlgorithm: '02',
  );

  final meter = VirtualMeter.setup(
    identity: identity,
    vendingKeyBytes: vudk,
    encryptionAlgorithm: 'sta',
  );

  // Pretend the utility just minted this token for 0.1 kWh.
  final hsm = VirtualHsmDispatch(VirtualHsm(VendingCommonDesKey(vudk)));
  final mint = hsm.generateToken({
    'class': 0, 'subclass': 0, 'dkga': '02', 'ea': '07',
    'keyType': 2, 'supplyGroupCode': '123456', 'tariffIndex': '01',
    'keyRevisionNumber': 1, 'iin': '600727', 'iain': '00000000000',
    'vudk': 'abababababababab', 'amount': 0.1,
    'dateOfIssue': '2004-03-01T13:55:00Z', 'randomNo': 5,
  });

  print(meter.applyToken(mint['tokenNo'] as String));
  // ApplyAccepted(amountKwh: 0.1, newBalanceKwh: 0.1, ...)
  print(meter.applyToken(mint['tokenNo'] as String));
  // ApplyReplay(tidMinutes: 5836875)
}
```

---

[TOC](./README.md)
