# 05 — The decode path

[◀ 04 — Transposition & the 20-digit token](./04-transposition-and-token-no.md) · [TOC](./README.md) · [Next chapter: 06 — The virtual HSM & virtual meter ▶](./06-virtual-hsm-and-meter.md)

---

Decoding is encoding played in reverse. Given:

- the **20-digit token** (`23716100501183194197`), and
- the same **decoder key** the utility used (`6ff35b9d1f3453e6`)
  — burned into the meter at factory personalisation,

the meter reconstructs the original 64-bit data block, verifies
the CRC, identifies the class/sub-class, and extracts the credit
amount + Token Identifier.

The whole pipeline is in
[`lib/src/tokendec/transfer_electricity_credit_decoder.dart`](../lib/src/tokendec/transfer_electricity_credit_decoder.dart),
fronted by the class-dispatching
[`TokenDecoderDispatcher`](../lib/src/tokendec/token_decoder_dispatcher.dart).

## Step 1 — decimal back to 66 bits

```dart
// lib/src/token/token.dart  —  TokenTransposition.tokenNoToBinary66
final cleaned = decimal20.replaceAll(RegExp(r'\s'), '');
final n = BigInt.parse(cleaned);
return n.toRadixString(2).padLeft(66, '0');
```

Whitespace is stripped (so `2371 6100 5011 8319 4197` works), the
decimal string is parsed as a `BigInt`, and the result is rendered
as a 66-char binary string, MSB-first, zero-padded.

## Step 2 — untransposition

The inverse of the splice from chapter 04. Bits 65 and 64 of the
66-bit string are the *original* ciphertext bits at positions 28
and 27 respectively; bits 27 and 28 of the embedded 64-bit block
currently hold the **class** bits.

```dart
// lib/src/token/token.dart  —  TokenTransposition.untransposeFromBinary66
final b28 = binary66[0];
final b27 = binary66[1];
final low64Bin = binary66.substring(2);

// Class bits live at bit positions 27 (low) and 28 (high) of
// the embedded 64-bit block. In MSB-first indexing, bit N is at
// string index 63-N.
final classLowChar  = low64Bin[63 - 27];
final classHighChar = low64Bin[63 - 28];
final klass = ((classHighChar == '1' ? 1 : 0) << 1)
            |  (classLowChar  == '1' ? 1 : 0);

// Restore the original ciphertext by string-splicing.
final chars = low64Bin.split('');
chars[63 - 27] = b27;
chars[63 - 28] = b28;
final restored = chars.join();
final low64 = BigInt.parse(restored, radix: 2).toSigned(64).toInt();
```

We now have:

- the **token class** (2 bits — for our example, `00`), and
- the **original 64-bit ciphertext** that the cipher emitted.

The dispatcher looks at the class and routes to the right decoder:

```dart
// lib/src/tokendec/token_decoder_dispatcher.dart
switch (klass) {
  case 0: /* TransferElectricityCreditDecoder */
  case 1: /* Class1TokenDecoder (InitiateMeterTestOrDisplay) */
  case 2: /* DecodeFailure(NotImplementedException(...)) */
  case 3: /* DecodeFailure(NotImplementedException(...)) */
}
```

Class 2 and 3 tokens are **cleanly rejected** here rather than
silently mis-routed, so callers can detect the gap without crashing.

## Step 3 — EA07 decrypt

```dart
final decrypted = encryptionAlgorithm.decrypt(decoderKey, encrypted64);
```

This is the inverse cipher from chapter 03 (permute → S-box → key
rotate-right, 16 rounds). After 16 rounds the output is — bit for
bit — the original 64-bit data block from chapter 02.

## Step 4 — CRC verification

The first 16 bits of the decrypted block are the CRC field; the
upper 48 bits are `Amount || TID || RandomNo || SubClass`. The
meter recomputes the CRC over those 48 bits plus the 2-bit class
recovered in step 2:

```dart
// lib/src/token/token.dart  —  Token.checkCrc / calculateCrc
final apdu     = decryptedDataBlock.extractBits(16, 48);
final combined = apdu.concat([tokenClass.bitString]);
final computed = Crc().generateCrc(combined);

final extracted = decryptedDataBlock.extractBits(0, 16);
if (computed.compareTo(extracted) != BitString.sameCmp) {
  throw const CrcError('CRC mismatch on token decode');
}
```

If the CRC matches, the token is structurally valid. If not, we
throw `CrcError` — and because the CRC input includes the token
class, a tamper that successfully reroutes a token from one class
to another almost certainly fails this check.

## Step 5 — field extraction

With CRC verified, decoding the upper bits is trivial — they sit in
fixed positions:

```dart
// lib/src/token/class0_tokens.dart  —  Class0Token.decode
crc             = extractCrc(decryptedDataBlock);
amountPurchased = extractAmount(decryptedDataBlock);        // bits 16..31
tokenIdentifier = extractTokenIdentifier(decryptedDataBlock); // bits 32..55
randomNo        = extractRandomNo(decryptedDataBlock);       // bits 56..59
```

For our example token, the meter now knows:

| Field           | Value                                                                |
| --------------- | -------------------------------------------------------------------- |
| `Amount`        | `0.1 kWh`                                                            |
| `TID` (minutes) | `5 836 875` — i.e. issued at `2004-03-01 13:55:00 UTC`               |
| `RandomNo`      | `5`                                                                  |
| `TokenClass`    | `0` (recovered from transposition step)                              |
| `TokenSubClass` | `0` (from bits 60..63 of the data block, implied by Class0 decoder)  |

The decoder returns a fully-populated
`TransferElectricityCreditToken` via the `.decoded()` factory
([`lib/src/token/class0_tokens.dart`](../lib/src/token/class0_tokens.dart)).

## What's *not* checked here

A few things deliberately don't live in the decoder:

- **Replay detection.** Whether this specific TID has already been
  applied is a *meter-state* question, not a token-decoder question.
  It's enforced in [`VirtualMeter.applyToken`](../lib/src/meter/virtual_meter.dart),
  covered next chapter.
- **TID window enforcement.** Real meters reject tokens whose TID
  is more than ±N days from their internal clock. The virtual meter
  in this port does not enforce a window (it just stores the full
  set of applied TIDs).
- **Tariff-index / key-revision rotation.** Out of scope.

All of these are deferred to the meter's state machine on purpose,
so the cryptographic decoder remains a pure, stateless function.

In the next chapter we wire the generator and decoder together
via a software HSM and a software meter, and watch a token actually
*credit a balance*.

---

[◀ 04 — Transposition & the 20-digit token](./04-transposition-and-token-no.md) · [TOC](./README.md) · [Next chapter: 06 — The virtual HSM & virtual meter ▶](./06-virtual-hsm-and-meter.md)
