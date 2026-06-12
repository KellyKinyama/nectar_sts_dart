# 01 — The vending key & DKGA-02

[◀ 00 — Infrastructure](./00-infrastructure.md) · [TOC](./README.md) · [Next chapter: 02 — Building the data block ▶](./02-data-block-and-crc.md)

---

In this chapter the journey starts. The utility has one secret —
the **vending key** — and one fact about your specific meter —
its **PAN**. From those two values DKGA-02 derives an 8-byte
**decoder key** that is unique to your meter, and which the meter
itself was personalised with at the factory. Every token the
utility issues to your meter from now on will be encrypted under
*that* derived key.

## The vending key

At the utility, the secret lives as a `VendingUniqueDesKey` — an
8-byte (64-bit) DES key:

```dart
final vudk = VendingUniqueDesKey([
  0xab, 0xab, 0xab, 0xab, 0xab, 0xab, 0xab, 0xab,
]);
```

See [`lib/src/keys/vending_key.dart`](../lib/src/keys/vending_key.dart).
Three concrete vending-key types exist in the spec; for this walkthrough
all we care about is the **VUDK** (Vending Unique DES Key) above.

## The PAN block

Your meter has a **Primary Account Number (PAN)** —
`600727000000000009`. The leading `600727` is the
**Issuer Identification Number (IIN)**; the next 11 digits
(`00000000000`) are the **Individual Account Identification Number
(IAIN)** which includes a Luhn check digit; the final digit (`9`) is
the overall PAN check digit.

The first thing DKGA-02 does is build an 8-byte **PAN block**. The
layout depends on whether the IIN is 6 digits or the special
`"0000"` 4-zero form. For 6-digit IINs (our case) it's:

```
PAN block = last-5-digits-of-IIN || last-11-digits-of-IAIN
```

See [`PrimaryAccountNumberBlock`](../lib/src/domain/primitives.dart)
in [`lib/src/domain/primitives.dart`](../lib/src/domain/primitives.dart).

For our meter the resulting 16 hex chars are:

```
00727 00000000000   →  hex bytes  00 72 70 00 00 00 00 00
```

> **Aside.** For `KeyType = 3` (DCTK / common transfer key) the
> IAIN portion is replaced by zeros, because a common key isn't
> tied to a single meter. We're using `KeyType = 2`, so the full
> IAIN bits are kept.

## The control block

The second 8-byte block carries the *non-secret* parameters of the
key being derived. From [`ControlBlock`](../lib/src/domain/primitives.dart):

```
control block = <KT><SGC><TI><KRN>FFFFFF
              =   2  123456  01  1  FFFFFF
              →  hex bytes  21 23 45 60 11 FF FF FF
```

| Slice  | Field                | Our value |
| ------ | -------------------- | --------- |
| `KT`   | KeyType              | `2`       |
| `SGC`  | SupplyGroupCode      | `123456`  |
| `TI`   | TariffIndex          | `01`      |
| `KRN`  | KeyRevisionNumber    | `1`       |
| `FFFFFF` | `maximumPhasePowerUnbalanceLimit` (hard-coded all-ones) | — |

## The five XOR + DES steps

With those two 8-byte buffers, DKGA-02 is just a fixed sequence of
XORs around a single DES-ECB block encryption. From
[`lib/src/decoderkey/dkga02.dart`](../lib/src/decoderkey/dkga02.dart):

```dart
final panBytes = hexDecode8(panBlock.value);      // 1. PAN block
final ctlBytes = hexDecode8(ctlBlock.value);      // 2. Control block
final mixed    = xorBytes(panBytes, ctlBytes);    // 3. mix
final enc      = ea09.encryptBytes(vendingKey.keyData, mixed);  // 4. DES_ECB
final doubled  = xorBytes(enc, mixed);            // 5. XOR with input
final derived  = xorBytes(doubled, vendingKey.keyData);  // 6. XOR with key
return DecoderKey(_reverseBytes(derived));         // 7. byte-reverse
```

That's it — seven small operations. The XOR-with-input dance after
DES is the IEC 62055-41 *key-derivation* construction; it turns the
one-way DES step into a Davies-Meyer-flavoured compression so that
recovering the vending key from a leaked decoder key would require
breaking DES.

> **Why DES?** Because the spec was written in the early 1990s and
> the vending key is 64 bits anyway. The DES instance here is **not**
> used to *encrypt tokens* — it's only used as the one-way step
> inside DKGA-02. Token encryption uses EA07 (covered in chapter 03).

The implementation of DES itself lives in
[`lib/src/encryption/data_encryption_algorithm.dart`](../lib/src/encryption/data_encryption_algorithm.dart)
as `DataEncryptionAlgorithm` (EA09 in STS terms).

## Walking through the actual bytes

Starting from our example inputs:

```text
VUDK              ab ab ab ab ab ab ab ab
PAN block         00 72 70 00 00 00 00 00
control block     21 23 45 60 11 ff ff ff
                  ────────────────────────  XOR
mixed             21 51 35 60 11 ff ff ff
                  ────────────────────────  DES_ECB(VUDK, ·)
enc               <8 bytes from DES>
                  ────────────────────────  XOR mixed
doubled           <enc XOR mixed>
                  ────────────────────────  XOR VUDK
derived           <doubled XOR ab ab ab ab ab ab ab ab>
                  ────────────────────────  reverse_bytes
decoder key       6f f3 5b 9d 1f 34 53 e6   ←  the official answer
```

That last line — `6f f3 5b 9d 1f 34 53 e6` — is the expected derived
key from STS6 CTSA01 step1. It is asserted bit-exactly here:

```dart
expect(
  _hexOf(decoderKey.keyData),
  equals('6ff35b9d1f3453e6'),
  reason: 'DKGA-02 derived key must match STS6 expected value',
);
```

(see [test/sts_compliance_test.dart](../test/sts_compliance_test.dart)).

So if you can read DES output, you can recompute the decoder key
yourself. Most readers won't (DES needs a real cipher implementation);
the point is that **everything between the public inputs and the
decoder key is fully specified and reproducible** — there are no
secret S-boxes, no oracle calls, no time-varying state. The same
inputs always produce `6ff35b9d1f3453e6`.

## Aside on time zones

The Java test uses `DateTimeFormat.forPattern("dd/MM/yyyy HH:mm:ss").parseDateTime("01/03/2004 13:55:00")`,
which is parsed in the *JVM default time zone*. The official STS6
vectors implicitly assume UTC, so the Java test only produces the
canonical token strings when the JVM is run with `-Duser.timezone=UTC`
(or on a UTC machine).

In Dart we sidestep the ambiguity by using `DateTime.utc(2004, 3, 1, 13, 55, 0)`
directly. [`TokenIdentifier`](../lib/src/domain/token_identifier.dart)
also converts any local-time input to UTC internally, so callers don't
have to think about it. This will matter in chapter 02 when we encode
the TID.

## DKGA-04 in passing

DKGA-04 is the modern HMAC-SHA-256-based KDF — it takes a 160-bit
(20-byte) vending key and produces either an 8-byte STA decoder key
(byte-reversed from the HMAC output) or a 16-byte MISTY1 key (not
implemented here). The whole algorithm fits in ~50 lines:
[`lib/src/decoderkey/dkga04.dart`](../lib/src/decoderkey/dkga04.dart).

We don't trace a DKGA-04 example in this walkthrough because the
official STS6 CTSA01 vector for DKGA-04 uses MISTY1 (EA11) for
encryption, and MISTY1 is out of scope here.

---

[◀ 00 — Infrastructure](./00-infrastructure.md) · [TOC](./README.md) · [Next chapter: 02 — Building the data block ▶](./02-data-block-and-crc.md)
