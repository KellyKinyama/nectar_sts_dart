# 04 — Transposition & the 20-digit token

[◀ 03 — EA07 encryption](./03-ea07-encryption.md) · [TOC](./README.md) · [Next chapter: 05 — The decode path ▶](./05-decode-path.md)

---

We now have a 64-bit ciphertext. The customer needs **20 decimal
digits** they can punch into a meter keypad. Two final steps stand
between the ciphertext and that string:

1. **Transposition** — splice the 2-bit token class into the
   ciphertext, producing a 66-bit value.
2. **BigInt → decimal** — interpret those 66 bits as an unsigned
   integer and print it zero-padded to 20 decimal digits.

Both are implemented in
[`TokenTransposition`](../lib/src/token/token.dart) inside
[`lib/src/token/token.dart`](../lib/src/token/token.dart).

## Why transpose?

A naïve design would just prepend the 2-bit class to the 64-bit
ciphertext, giving a 66-bit number. That works — but it leaves
two ciphertext bits *unauthenticated*: an attacker who flips bit
0 or bit 1 of the prepended class would change the apparent class
and the meter would route the token to the wrong decoder.

STS6 instead **swaps** the 2 class bits with bits 27 and 28 of the
ciphertext, then prepends the *displaced* original bits at positions
65 and 64. The 64-bit value the cipher sees is still a complete
"ciphertext-with-class-bits-mixed-in"; any bit flip in the high
two bits of the token *also* flips a bit of the ciphertext, so the
CRC check after decryption catches the tamper.

## Generator side

```dart
// lib/src/token/token.dart  —  TokenTransposition.transposeToBinary66
final out = encrypted64.clone();
final b27 = out.getBit(27).intValue;
final b28 = out.getBit(28).intValue;
out.setBitChar(27, tokenClass.bitString.getBit(0).value);
out.setBitChar(28, tokenClass.bitString.getBit(1).value);
final low64Bin = out.toPaddedBinary();
return '$b28$b27$low64Bin';
```

Step by step:

1. **Clone** the ciphertext (don't mutate the caller's buffer).
2. **Read** the original bits at positions 27 and 28; remember them.
3. **Overwrite** those positions with the two class bits (bit 0 of
   the class goes to bit 27, bit 1 to bit 28).
4. **Stringify** the now-modified 64-bit block as 64 chars of '0'/'1',
   MSB-first.
5. **Prepend** the two displaced bits — `b28` first, then `b27` —
   to give a 66-char binary string.

For our Class 0 token both class bits are `0`, so the substitution
just *zeros* bits 27/28 — the displaced bits could be anything from
`00` through `11` depending on the ciphertext. They get carried at
the top of the 66-bit number.

## From 66 bits to 20 digits

The 66-bit binary string is interpreted as a positive integer
(MSB-first) and formatted decimally:

```dart
// lib/src/token/token.dart  —  Token.tokenNo
String get tokenNo {
  final n = BigInt.parse(encryptedTokenBitString!, radix: 2);
  return n.toString().padLeft(20, '0');
}
```

Since `2^66 - 1 ≈ 7.38 × 10^19`, the result is *at most* 20 digits,
so left-padding with zeros to a fixed 20-digit width gives the
canonical token string.

For our example the result is:

```
23716100501183194197
```

That string is the token. The customer reads it from their
voucher, types it into the meter's keypad, the meter reverses
this whole pipeline (see chapter 05), credits 0.1 kWh to their
balance, and the journey ends.

## A note on Dart's signed 64-bit int

The decoder side has a subtle hazard. To go from a 64-bit binary
string back to a `BitString`, the obvious implementation is
`int.parse(binary64, radix: 2)`. **That breaks** on the Dart VM
whenever the MSB of the ciphertext is set, because `int` is signed
64-bit and `int.parse(radix: 2)` rejects values `≥ 2^63`.

The fix in
[`TokenTransposition.untransposeFromBinary66`](../lib/src/token/token.dart)
is to round-trip through `BigInt` and then `toSigned(64).toInt()`:

```dart
final low64 = BigInt.parse(restored, radix: 2).toSigned(64).toInt();
```

`toSigned(64)` preserves the bit pattern even when bit 63 is set —
the resulting Dart `int` is just *negative* on the JS / VM side,
which is fine because everything downstream reads it bit-by-bit,
not arithmetically.

## What the customer actually sees

The 20-digit token (`23716100501183194197`) typically gets printed
on a paper voucher in 4-digit groups:

```
2371   6100   5011   8319   4197
```

That visual grouping is a vendor convenience; it isn't in the
protocol. Our decoder accepts the unspaced 20-digit form *and*
strips whitespace before parsing (see `tokenNoToBinary66`), so
either presentation round-trips correctly.

In the next chapter we follow the same 20 digits in reverse —
through the meter's decode pipeline — and watch the original
0.1 kWh credit pop back out.

---

[◀ 03 — EA07 encryption](./03-ea07-encryption.md) · [TOC](./README.md) · [Next chapter: 05 — The decode path ▶](./05-decode-path.md)
