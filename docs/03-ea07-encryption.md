# 03 — EA07 / Standard Transfer Algorithm

[◀ 02 — Building the data block](./02-data-block-and-crc.md) · [TOC](./README.md) · [Next chapter: 04 — Transposition & the 20-digit token ▶](./04-transposition-and-token-no.md)

---

EA07 is the **Standard Transfer Algorithm** — the symmetric block
cipher that takes the 64-bit plaintext data block from chapter 02
and the 8-byte decoder key from chapter 01, and produces a 64-bit
ciphertext.

It is **not** DES. It is a 16-round substitution-permutation
network specified by IEC 62055-41 and implemented in this port at
[`lib/src/encryption/standard_transfer_algorithm.dart`](../lib/src/encryption/standard_transfer_algorithm.dart).

## Key pre-processing

Before round 1 starts, the decoder key is transformed:

```dart
Uint8List _processKey(DecoderKey decoderKey) {
  final ec = decoderKey.keyData;
  final complemented = decoderKey.complement(ec);
  return decoderKey.rotateComplemented(complemented);
}
```

In plain English:

1. **Bit-complement** every byte (`b → ~b & 0xFF`).
2. **Rotate right by 12 bits** as a single 64-bit word.

This becomes the round-0 key. It's purely a key schedule step —
the original decoder-key bytes are still kept around because the
*round-key bit selector* (see "S-box selection" below) reads from
the same processed key as it rotates left each round.

## One round

Each of the 16 rounds is:

```dart
b = _substitute(k, b,
                firstTable:  encryptingFirstSubstitutionTable,
                secondTable: encryptingSecondSubstitutionTable,
                keyBitOffsetWithinNibble: 3);
b = _permutate(b, encryptingPermutationTable);
k = _decoderKey.rotateLeft(k, 1);
```

Three operations: **substitute**, **permute**, **rotate key**.

### Substitution

The 64-bit block is treated as **16 nibbles** (4-bit groups). For
each nibble position `i` from 0 to 15:

1. Read **one bit** from the current round key, at index
   `i * 4 + 3` (the offset `+ 3` is unique to the *encrypt* path;
   decrypt uses `+ 0` — see below).
2. That bit selects one of two 4→4 S-boxes:
   - `0` → `encryptingFirstSubstitutionTable`
   - `1` → `encryptingSecondSubstitutionTable`
3. Look up the current nibble's value in the selected S-box.
4. Write the result back to the same nibble position.

The two S-boxes are constants in
[`lib/src/encryption/tables.dart`](../lib/src/encryption/tables.dart).

### Permutation

After all 16 nibbles have been substituted, the 64 bits are shuffled
according to a fixed permutation table:

```dart
for (var i = 0; i < 64; i++) {
  final dst    = table[i];
  final srcBit = block.getBit(i);
  out.setBitChar(dst, srcBit.value);
}
```

The encrypt table is `encryptingPermutationTable` (decrypt uses
the inverse `decryptingPermutationTable`).

### Key rotation

At the end of the round the key is rotated **left by 1 bit** as a
single 64-bit word. This means the bit-selector at offset `+ 3`
in the *next* round picks a different bit than this round did.

## Decrypt path

Decrypt is the mirror image:

```dart
for (var round = 0; round < 16; round++) {
  b = _permutate(b, decryptingPermutationTable);
  b = _substitute(k, b,
                  firstTable:  decryptingFirstSubstitutionTable,
                  secondTable: decryptingSecondSubstitutionTable,
                  keyBitOffsetWithinNibble: 0);
  k = _decoderKey.rotateRight(k, 1);
}
```

Three things change vs encrypt:

| Op           | Encrypt                  | Decrypt                  |
| ------------ | ------------------------ | ------------------------ |
| Order        | substitute → permute     | permute → substitute     |
| S-box tables | `encrypting*`            | `decrypting*` (inverses) |
| Permutation  | `encryptingPermutationTable` | `decryptingPermutationTable` (inverse) |
| Key bit offset within nibble | `+ 3`        | `+ 0`                    |
| Key rotation | left by 1                | right by 1               |

The key-bit-offset difference is the most surprising piece. It's
**not** a bug — it's part of the spec, and it makes the round
function reversible without needing a Feistel split. We verify it
end-to-end in [test/encryption_test.dart](../test/encryption_test.dart).

## Why two S-boxes?

The S-box-selector bit is what gives EA07 its key-dependent
diffusion. Without it, every plaintext nibble at a given position
would always map through the same S-box — a known fixed function —
and the cipher would degenerate into a known affine permutation
keyed only by the round-key rotations. The single bit of key per
nibble per round is what couples plaintext-dependent diffusion
to the key.

## In code

The full encryption call is one line at the top of
`TokenGenerator.generate`:

```dart
// lib/src/tokengen/token_generator.dart
final dataBlock = buildDataBlock(token);
final encrypted = encryptionAlgorithm.encrypt(decoderKey, dataBlock);
```

For our example:

```text
plaintext (data block, 64 bits)  →  EA07.encrypt(decoderKey, ·)  →  ciphertext (64 bits)
```

The decoder key here is the `6ff35b9d1f3453e6` derived in chapter
01. The plaintext is the 64-bit block built in chapter 02.

What comes out is a 64-bit ciphertext that — by design — looks
random to anyone who doesn't know the decoder key, and decrypts
exactly back to the plaintext for anyone who does.

In the next chapter we'll see how those 64 ciphertext bits are
**transposed** with the 2-bit class to form the 66-bit token,
and how that 66-bit value becomes the familiar 20-digit decimal
string the customer types into their meter.

---

[◀ 02 — Building the data block](./02-data-block-and-crc.md) · [TOC](./README.md) · [Next chapter: 04 — Transposition & the 20-digit token ▶](./04-transposition-and-token-no.md)
