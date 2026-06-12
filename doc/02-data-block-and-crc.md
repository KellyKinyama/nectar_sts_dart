# 02 — Building the data block

[◀ 01 — The vending key & DKGA-02](./01-the-vending-key-and-dkga-02.md) · [TOC](./README.md) · [Next chapter: 03 — EA07 encryption ▶](./03-ea07-encryption.md)

---

The decoder key is in hand. Now the utility needs to encode
*what this token actually does* into the 64 bits that will get
encrypted. For a Class 0 / SubClass 0 (electricity credit) token
the layout is fixed:

```
 bit  0..15   CRC-16/IBM             (16)
 bit 16..31   Amount                 (16)
 bit 32..55   TokenIdentifier (TID)  (24)
 bit 56..59   RandomNo               ( 4)
 bit 60..63   TokenSubClass          ( 4)
```

We'll build it field by field, then compute the CRC and assemble
the final 64-bit block.

Source: [`Class0TokenGenerator.buildDataBlock`](../lib/src/tokengen/class0_token_generators.dart)
and [`Class0Token`](../lib/src/token/class0_tokens.dart).

## Bit 60..63 — `TokenSubClass`

Four bits identifying the *sub-class* within Class 0:

| Value | Sub-class                |
| ----- | ------------------------ |
| `0`   | Electricity              |
| `1`   | Water *(not ported)*     |
| `2`   | Gas *(not ported)*       |
| `3`   | Time                     |
| `4`   | Electricity (currency)   |

For our electricity token: `0` → binary `0000`.

Source: [`TokenSubClass.electricityCredit()`](../lib/src/domain/token_subclass.dart).

## Bit 56..59 — `RandomNo`

Four bits of pure decorrelation. The random number isn't
cryptographically meaningful: it only ensures that two otherwise-
identical tokens (same meter, same amount, same minute) encrypt to
different ciphertexts. Real vending systems use a CSPRNG; in our
example the official vector pins it to `0x5` so the test is
reproducible.

```dart
RandomNo.fromInt(0x5);   // binary  0101
```

Source: [`lib/src/domain/random_no.dart`](../lib/src/domain/random_no.dart).

## Bit 32..55 — `TokenIdentifier`

This is the 24-bit *minute counter* since the chosen base date. It
acts as the token's serial number for the meter's replay-detection
window.

```
TID (minutes) = floor((issued_at_UTC - baseDate_UTC) / 60_000)
```

For our example:

- `BaseDate.date1993` → epoch `1993-01-01 00:00:00 UTC`
- `issued_at` → `2004-03-01 13:55:00 UTC`
- Difference: `11 years 2 months ≈ 5 836 875 minutes`

Specifically: `0x591A8B` (binary `0101 1001 0001 1010 1000 1011`).

There's one Joda-compatibility quirk preserved from the Java
original: if the **minute-of-day is 1 and the hour is 0**, the TID
is bumped by `+1 minute`. This handles a midnight-rounding edge in
the upstream code. Source:
[`lib/src/domain/token_identifier.dart`](../lib/src/domain/token_identifier.dart).

## Bit 16..31 — `Amount`

The amount field is a 16-bit floating-point-style value with a
2-bit exponent in the **high** bits and a 14-bit mantissa in the
**low** bits, encoding the purchase in **tenths of a unit**
(0.1 kWh resolution).

For `0.1 kWh`:

```
tenths = ceil(0.1 * 10) = 1
encoded mantissa = 1, exponent = 0
16-bit value = 0x0001 = binary  0000 0000 0000 0001
```

For `25.6 kWh` (the other example we use in chapter 07):

```
tenths = floor(25.6 * 10) = 256
encoded as exponent=0, mantissa=256
16-bit value = 0x0100 = binary  0000 0001 0000 0000
```

Source: [`Amount`](../lib/src/domain/amount.dart) and
`Utils.convertToBitString` in
[`lib/src/util/utils.dart`](../lib/src/util/utils.dart).

The "tenths of a unit" rule has one wrinkle: values **below 1 kWh**
use `ceil` (so even a `0.05` kWh top-up encodes as `1` tenth);
values `≥ 1 kWh` truncate. This matches the Java reference and is
the reason a few corner-case tests pin a specific double.

## Bit 0..15 — CRC-16/IBM

Once Amount, TID, RandomNo and SubClass are concatenated (in **that
order**, low-to-high), the upper 48 bits of the data block are
known. The CRC fills the bottom 16 bits.

The CRC input is **not** quite "everything above bit 16" — it's:

```
crc_input = Amount || TID || RandomNo || SubClass || TokenClass
          = 16   +  24  +    4    +    4    +    2     = 50 bits
```

i.e. the 2-bit `TokenClass` (`00` for Class 0) is appended after
the SubClass. This couples the CRC to the class even though the
class itself never lives in the data block — that's intentional,
so a stray bit-flip in transposition (chapter 04) won't decode as
a valid token of a different class.

The algorithm is plain **CRC-16/IBM** with reversed polynomial
`0xA001` (== reversed `0x8005`), initial value `0xFFFF`, with the
final 16-bit result **byte-swapped** (high and low bytes exchanged)
before being treated as the 16-bit CRC field. See
[`Crc.generateCrcBytes`](../lib/src/domain/crc.dart) in
[`lib/src/domain/crc.dart`](../lib/src/domain/crc.dart):

```dart
int generateCrcBytes(List<int> bytes) {
  var crc = 0xFFFF;
  for (var pos = 0; pos < bytes.length; pos++) {
    crc ^= (0xFF & bytes[pos]);
    for (var i = 8; i != 0; i--) {
      if ((crc & 0x0001) != 0) {
        crc >>= 1;
        crc ^= 0xA001;
      } else {
        crc >>= 1;
      }
    }
  }
  final swapped = ((crc & 0xFF) << 8) | ((crc >> 8) & 0xFF);
  return swapped & 0xFFFF;
}
```

## Assembling the 64-bit block

With CRC in hand, the data block is just a left-to-right concat
of the five fields in storage order (low bit first):

```dart
// from Class0TokenGenerator.buildDataBlock
final crcInput = amount.concat([tid, rnd, sub, cls]);
final crc      = Crc().generateCrc(crcInput);
token.crc      = Crc.fromBitString(crc);

// 64-bit data block: crc || amount || tid || rnd || sub
return crc.concat([amount, tid, rnd, sub]);
```

Source: [`lib/src/tokengen/class0_token_generators.dart`](../lib/src/tokengen/class0_token_generators.dart).

The result, for our example, is a 64-bit value whose MSB-first
binary form is (split into nibbles for readability):

```
 SubClass    RandomNo  TokenIdentifier            Amount             CRC
   0000      0101      0101 1001 0001 1010 1000 1011   0000 0000 0000 0001   <16-bit CRC>
   bit 60..63 bit 56..59 ─── bit 32..55 ─────────────  bit 16..31 ───────  bit 0..15
```

That is the **plaintext data block** — the bits that the meter,
after decoding, will read back as "credit 0.1 kWh, issued at
minute 5 836 875, random 5, electricity sub-class".

In the next chapter we encrypt this 64-bit block under the decoder
key from chapter 01.

---

[◀ 01 — The vending key & DKGA-02](./01-the-vending-key-and-dkga-02.md) · [TOC](./README.md) · [Next chapter: 03 — EA07 encryption ▶](./03-ea07-encryption.md)
