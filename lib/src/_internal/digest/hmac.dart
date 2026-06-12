// Vendored from the local tls package
// (https://github.com/KellyKinyama/tls, publish_to: none) so that
// nectar_sts_dart has no path: dependencies and can be published.
// This file is internal to the package. Do not import it directly;
// the public API uses these primitives only inside the algorithm core.

import 'dart:typed_data';
import 'digest.dart';

/// HMAC per RFC 2104. Mirrors `hmac` in `ch04/hmac.c` but allows keys
/// of any length: if `key.length > 64` we hash it first per the spec
/// (the C version has a TODO for this).
Uint8List hmac(List<int> key, List<int> text, DigestCtx digest) {
  var k = key;
  if (k.length > digestBlockSize) {
    final hashed = digest.clone();
    updateDigest(hashed, k);
    finalizeDigest(hashed);
    k = hashed.bytes();
  }

  final ipad = Uint8List(digestBlockSize)..fillRange(0, digestBlockSize, 0x36);
  final opad = Uint8List(digestBlockSize)..fillRange(0, digestBlockSize, 0x5C);
  for (var i = 0; i < k.length; i++) {
    ipad[i] ^= k[i];
    opad[i] ^= k[i];
  }

  final inner = digest.clone();
  updateDigest(inner, ipad);
  updateDigest(inner, text);
  finalizeDigest(inner);
  final innerHash = inner.bytes();

  updateDigest(digest, opad);
  updateDigest(digest, innerHash);
  finalizeDigest(digest);
  return digest.bytes();
}
