// Vendored from the local tls package
// (https://github.com/KellyKinyama/tls, publish_to: none) so that
// nectar_sts_dart has no path: dependencies and can be published.
// This file is internal to the package. Do not import it directly;
// the public API uses these primitives only inside the algorithm core.

/// Streaming message-digest abstraction modeled after `ch04/digest.h`.
/// Uses `Uint32List` for the running hash words.
import 'dart:typed_data';

const int digestBlockSize = 64; // 512 bits
const int inputBlockSize = 56; // 64 - 8 (length)

/// Block-update callback signature: `(block[64], hash)`.
typedef BlockOperate = void Function(Uint8List block, Uint32List hash);

/// Finalize-block callback: writes the message length (in bits) into the
/// trailing 8 bytes of a padded block. Different digests place those bytes
/// in different positions / endianness.
typedef BlockFinalize = void Function(Uint8List block, int lengthInBits);

class DigestCtx {
  final Uint32List hash;
  final int hashLen; // in 32-bit words
  int inputLen = 0;
  final BlockOperate blockOperate;
  final BlockFinalize blockFinalize;
  final Uint8List block = Uint8List(digestBlockSize);
  int blockLen = 0;
  final bool littleEndian;

  DigestCtx({
    required this.hash,
    required this.hashLen,
    required this.blockOperate,
    required this.blockFinalize,
    this.littleEndian = false,
  });

  /// Output the hash as a packed byte array, respecting the digest's
  /// natural word endianness (big-endian for SHA, little-endian for MD5).
  Uint8List bytes() {
    final out = Uint8List(hashLen * 4);
    for (var i = 0; i < hashLen; i++) {
      final w = hash[i];
      if (littleEndian) {
        out[i * 4] = w & 0xFF;
        out[i * 4 + 1] = (w >> 8) & 0xFF;
        out[i * 4 + 2] = (w >> 16) & 0xFF;
        out[i * 4 + 3] = (w >> 24) & 0xFF;
      } else {
        out[i * 4] = (w >> 24) & 0xFF;
        out[i * 4 + 1] = (w >> 16) & 0xFF;
        out[i * 4 + 2] = (w >> 8) & 0xFF;
        out[i * 4 + 3] = w & 0xFF;
      }
    }
    return out;
  }

  DigestCtx clone() {
    final c = DigestCtx(
      hash: Uint32List.fromList(hash),
      hashLen: hashLen,
      blockOperate: blockOperate,
      blockFinalize: blockFinalize,
      littleEndian: littleEndian,
    );
    c.inputLen = inputLen;
    c.block.setAll(0, block);
    c.blockLen = blockLen;
    return c;
  }
}

void updateDigest(DigestCtx c, List<int> input) {
  var off = 0;
  var len = input.length;
  c.inputLen += len;
  if (c.blockLen > 0) {
    final borrow = digestBlockSize - c.blockLen;
    if (len < borrow) {
      c.block.setRange(c.blockLen, c.blockLen + len, input);
      c.blockLen += len;
      return;
    }
    c.block.setRange(c.blockLen, c.blockLen + borrow, input);
    c.blockOperate(c.block, c.hash);
    c.blockLen = 0;
    off += borrow;
    len -= borrow;
  }
  while (len >= digestBlockSize) {
    final view = (input is Uint8List)
        ? input.buffer.asUint8List(input.offsetInBytes + off, digestBlockSize)
        : Uint8List.fromList(input.sublist(off, off + digestBlockSize));
    c.blockOperate(view, c.hash);
    off += digestBlockSize;
    len -= digestBlockSize;
  }
  if (len > 0) {
    c.block.setRange(0, len, input, off);
    c.blockLen = len;
  }
}

void finalizeDigest(DigestCtx c) {
  // Zero-fill rest of block, set 0x80 padding marker
  for (var i = c.blockLen; i < digestBlockSize; i++) {
    c.block[i] = 0;
  }
  c.block[c.blockLen] = 0x80;
  if (c.blockLen >= inputBlockSize) {
    c.blockOperate(c.block, c.hash);
    for (var i = 0; i < digestBlockSize; i++) {
      c.block[i] = 0;
    }
    c.blockLen = 0;
  }
  c.blockFinalize(c.block, c.inputLen * 8);
  c.blockOperate(c.block, c.hash);
}
