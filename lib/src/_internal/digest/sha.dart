// Vendored from the local tls package
// (https://github.com/KellyKinyama/tls, publish_to: none) so that
// nectar_sts_dart has no path: dependencies and can be published.
// This file is internal to the package. Do not import it directly;
// the public API uses these primitives only inside the algorithm core.

/// SHA-1 and SHA-256, ported from `ch04/sha.c`.
import 'dart:typed_data';
import 'digest.dart';

const int sha1ResultSize = 5;
const int sha256ResultSize = 8;

const _sha1InitialHash = <int>[
  0x67452301,
  0xefcdab89,
  0x98badcfe,
  0x10325476,
  0xc3d2e1f0,
];

const _sha1K = <int>[0x5a827999, 0x6ed9eba1, 0x8f1bbcdc, 0xca62c1d6];

int _ch(int x, int y, int z) => (x & y) ^ (~x & z);
int _parity(int x, int y, int z) => x ^ y ^ z;
int _maj(int x, int y, int z) => (x & y) ^ (x & z) ^ (y & z);

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;
int _shr(int x, int n) => (x >> n) & 0xFFFFFFFF;
int _sigmaRot(int x, int i) =>
    _rotr(x, i != 0 ? 6 : 2) ^
    _rotr(x, i != 0 ? 11 : 13) ^
    _rotr(x, i != 0 ? 25 : 22);
int _sigmaShr(int x, int i) =>
    _rotr(x, i != 0 ? 17 : 7) ^
    _rotr(x, i != 0 ? 19 : 18) ^
    _shr(x, i != 0 ? 10 : 3);

void sha1BlockOperate(Uint8List block, Uint32List hash) {
  final W = Uint32List(80);
  for (var t = 0; t < 80; t++) {
    if (t < 16) {
      W[t] =
          (block[t * 4] << 24) |
          (block[t * 4 + 1] << 16) |
          (block[t * 4 + 2] << 8) |
          block[t * 4 + 3];
    } else {
      var w = W[t - 3] ^ W[t - 8] ^ W[t - 14] ^ W[t - 16];
      w = ((w << 1) | ((w & 0x80000000) >> 31)) & 0xFFFFFFFF;
      W[t] = w;
    }
  }
  var a = hash[0], b = hash[1], c = hash[2], d = hash[3], e = hash[4];
  for (var t = 0; t < 80; t++) {
    var T =
        ((((a << 5) & 0xFFFFFFFF) | (a >> 27)) + e + _sha1K[t ~/ 20] + W[t]) &
        0xFFFFFFFF;
    if (t <= 19) {
      T = (T + _ch(b, c, d)) & 0xFFFFFFFF;
    } else if (t <= 39) {
      T = (T + _parity(b, c, d)) & 0xFFFFFFFF;
    } else if (t <= 59) {
      T = (T + _maj(b, c, d)) & 0xFFFFFFFF;
    } else {
      T = (T + _parity(b, c, d)) & 0xFFFFFFFF;
    }
    e = d;
    d = c;
    c = (((b << 30) & 0xFFFFFFFF) | (b >> 2)) & 0xFFFFFFFF;
    b = a;
    a = T;
  }
  hash[0] = (hash[0] + a) & 0xFFFFFFFF;
  hash[1] = (hash[1] + b) & 0xFFFFFFFF;
  hash[2] = (hash[2] + c) & 0xFFFFFFFF;
  hash[3] = (hash[3] + d) & 0xFFFFFFFF;
  hash[4] = (hash[4] + e) & 0xFFFFFFFF;
}

/// SHA length encoding: big-endian 64-bit at end of block.
/// The book caps length to 32 bits, but we put it in the trailing 4 bytes
/// (low word) — the high word stays 0.
void shaFinalize(Uint8List block, int lengthInBits) {
  block[digestBlockSize - 8] = 0;
  block[digestBlockSize - 7] = 0;
  block[digestBlockSize - 6] = 0;
  block[digestBlockSize - 5] = 0;
  block[digestBlockSize - 4] = (lengthInBits >> 24) & 0xFF;
  block[digestBlockSize - 3] = (lengthInBits >> 16) & 0xFF;
  block[digestBlockSize - 2] = (lengthInBits >> 8) & 0xFF;
  block[digestBlockSize - 1] = lengthInBits & 0xFF;
}

DigestCtx newSha1Digest() {
  return DigestCtx(
    hash: Uint32List.fromList(_sha1InitialHash),
    hashLen: sha1ResultSize,
    blockOperate: sha1BlockOperate,
    blockFinalize: shaFinalize,
  );
}

Uint8List sha1(List<int> input) {
  final c = newSha1Digest();
  updateDigest(c, input);
  finalizeDigest(c);
  return c.bytes();
}

// -------------------------------- SHA-256 --------------------------------

const _sha256InitialHash = <int>[
  0x6a09e667,
  0xbb67ae85,
  0x3c6ef372,
  0xa54ff53a,
  0x510e527f,
  0x9b05688c,
  0x1f83d9ab,
  0x5be0cd19,
];

const _sha256K = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

void sha256BlockOperate(Uint8List block, Uint32List hash) {
  final W = Uint32List(64);
  for (var t = 0; t < 64; t++) {
    if (t <= 15) {
      W[t] =
          (block[t * 4] << 24) |
          (block[t * 4 + 1] << 16) |
          (block[t * 4 + 2] << 8) |
          block[t * 4 + 3];
    } else {
      W[t] =
          (_sigmaShr(W[t - 2], 1) +
              W[t - 7] +
              _sigmaShr(W[t - 15], 0) +
              W[t - 16]) &
          0xFFFFFFFF;
    }
  }
  var a = hash[0],
      b = hash[1],
      c = hash[2],
      d = hash[3],
      e = hash[4],
      f = hash[5],
      g = hash[6],
      h = hash[7];
  for (var t = 0; t < 64; t++) {
    final T1 =
        (h + _sigmaRot(e, 1) + _ch(e, f, g) + _sha256K[t] + W[t]) & 0xFFFFFFFF;
    final T2 = (_sigmaRot(a, 0) + _maj(a, b, c)) & 0xFFFFFFFF;
    h = g;
    g = f;
    f = e;
    e = (d + T1) & 0xFFFFFFFF;
    d = c;
    c = b;
    b = a;
    a = (T1 + T2) & 0xFFFFFFFF;
  }
  hash[0] = (hash[0] + a) & 0xFFFFFFFF;
  hash[1] = (hash[1] + b) & 0xFFFFFFFF;
  hash[2] = (hash[2] + c) & 0xFFFFFFFF;
  hash[3] = (hash[3] + d) & 0xFFFFFFFF;
  hash[4] = (hash[4] + e) & 0xFFFFFFFF;
  hash[5] = (hash[5] + f) & 0xFFFFFFFF;
  hash[6] = (hash[6] + g) & 0xFFFFFFFF;
  hash[7] = (hash[7] + h) & 0xFFFFFFFF;
}

DigestCtx newSha256Digest() {
  return DigestCtx(
    hash: Uint32List.fromList(_sha256InitialHash),
    hashLen: sha256ResultSize,
    blockOperate: sha256BlockOperate,
    blockFinalize: shaFinalize,
  );
}

Uint8List sha256(List<int> input) {
  final c = newSha256Digest();
  updateDigest(c, input);
  finalizeDigest(c);
  return c.bytes();
}
