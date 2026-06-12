// Vendored from the local tls package
// (https://github.com/KellyKinyama/tls, publish_to: none) so that
// nectar_sts_dart has no path: dependencies and can be published.
// This file is internal to the package. Do not import it directly;
// the public API uses these primitives only inside the algorithm core.

/// DES and 3DES (EDE) in CBC mode. Direct port of `ch02/des.c`.
///
/// Educational only - DES has a 56-bit effective key size and is broken;
/// 3DES is deprecated. Do not use for real security.
import 'dart:typed_data';

const int desBlockSize = 8;
const int desKeySize = 8;
const int _expansionBlockSize = 6;
const int _pc1KeySize = 7;
const int _subkeySize = 6;

int _getBit(List<int> a, int bit) =>
    (a[bit ~/ 8] & (0x80 >> (bit % 8))) == 0 ? 0 : 1;
void _setBit(List<int> a, int bit) {
  a[bit ~/ 8] |= 0x80 >> (bit % 8);
}

void _xor(Uint8List target, List<int> src, int len) {
  for (var i = 0; i < len; i++) {
    target[i] ^= src[i];
  }
}

void _permute(Uint8List target, List<int> src, List<int> table, int len) {
  for (var i = 0; i < len * 8; i++) target[i ~/ 8] &= ~(0x80 >> (i % 8));
  for (var i = 0; i < len * 8; i++) {
    if (_getBit(src, table[i] - 1) != 0) _setBit(target, i);
  }
}

const _ipTable = <int>[
  58, 50, 42, 34, 26, 18, 10, 2, //
  60, 52, 44, 36, 28, 20, 12, 4,
  62, 54, 46, 38, 30, 22, 14, 6,
  64, 56, 48, 40, 32, 24, 16, 8,
  57, 49, 41, 33, 25, 17, 9, 1,
  59, 51, 43, 35, 27, 19, 11, 3,
  61, 53, 45, 37, 29, 21, 13, 5,
  63, 55, 47, 39, 31, 23, 15, 7,
];

const _fpTable = <int>[
  40, 8, 48, 16, 56, 24, 64, 32, //
  39, 7, 47, 15, 55, 23, 63, 31,
  38, 6, 46, 14, 54, 22, 62, 30,
  37, 5, 45, 13, 53, 21, 61, 29,
  36, 4, 44, 12, 52, 20, 60, 28,
  35, 3, 43, 11, 51, 19, 59, 27,
  34, 2, 42, 10, 50, 18, 58, 26,
  33, 1, 41, 9, 49, 17, 57, 25,
];

const _pc1Table = <int>[
  57, 49, 41, 33, 25, 17, 9, 1, //
  58, 50, 42, 34, 26, 18, 10, 2,
  59, 51, 43, 35, 27, 19, 11, 3,
  60, 52, 44, 36, //
  63, 55, 47, 39, 31, 23, 15, 7,
  62, 54, 46, 38, 30, 22, 14, 6,
  61, 53, 45, 37, 29, 21, 13, 5,
  28, 20, 12, 4,
];

const _pc2Table = <int>[
  14, 17, 11, 24, 1, 5, //
  3, 28, 15, 6, 21, 10,
  23, 19, 12, 4, 26, 8,
  16, 7, 27, 20, 13, 2,
  41, 52, 31, 37, 47, 55,
  30, 40, 51, 45, 33, 48,
  44, 49, 39, 56, 34, 53,
  46, 42, 50, 36, 29, 32,
];

const _expansionTable = <int>[
  32, 1, 2, 3, 4, 5, //
  4, 5, 6, 7, 8, 9,
  8, 9, 10, 11, 12, 13,
  12, 13, 14, 15, 16, 17,
  16, 17, 18, 19, 20, 21,
  20, 21, 22, 23, 24, 25,
  24, 25, 26, 27, 28, 29,
  28, 29, 30, 31, 32, 1,
];

const _sbox = <List<int>>[
  [
    14, 0, 4, 15, 13, 7, 1, 4, 2, 14, 15, 2, 11, 13, 8, 1, //
    3, 10, 10, 6, 6, 12, 12, 11, 5, 9, 9, 5, 0, 3, 7, 8,
    4, 15, 1, 12, 14, 8, 8, 2, 13, 4, 6, 9, 2, 1, 11, 7,
    15, 5, 12, 11, 9, 3, 7, 14, 3, 10, 10, 0, 5, 6, 0, 13,
  ],
  [
    15, 3, 1, 13, 8, 4, 14, 7, 6, 15, 11, 2, 3, 8, 4, 14, //
    9, 12, 7, 0, 2, 1, 13, 10, 12, 6, 0, 9, 5, 11, 10, 5,
    0, 13, 14, 8, 7, 10, 11, 1, 10, 3, 4, 15, 13, 4, 1, 2,
    5, 11, 8, 6, 12, 7, 6, 12, 9, 0, 3, 5, 2, 14, 15, 9,
  ],
  [
    10, 13, 0, 7, 9, 0, 14, 9, 6, 3, 3, 4, 15, 6, 5, 10, //
    1, 2, 13, 8, 12, 5, 7, 14, 11, 12, 4, 11, 2, 15, 8, 1,
    13, 1, 6, 10, 4, 13, 9, 0, 8, 6, 15, 9, 3, 8, 0, 7,
    11, 4, 1, 15, 2, 14, 12, 3, 5, 11, 10, 5, 14, 2, 7, 12,
  ],
  [
    7, 13, 13, 8, 14, 11, 3, 5, 0, 6, 6, 15, 9, 0, 10, 3, //
    1, 4, 2, 7, 8, 2, 5, 12, 11, 1, 12, 10, 4, 14, 15, 9,
    10, 3, 6, 15, 9, 0, 0, 6, 12, 10, 11, 1, 7, 13, 13, 8,
    15, 9, 1, 4, 3, 5, 14, 11, 5, 12, 2, 7, 8, 2, 4, 14,
  ],
  [
    2, 14, 12, 11, 4, 2, 1, 12, 7, 4, 10, 7, 11, 13, 6, 1, //
    8, 5, 5, 0, 3, 15, 15, 10, 13, 3, 0, 9, 14, 8, 9, 6,
    4, 11, 2, 8, 1, 12, 11, 7, 10, 1, 13, 14, 7, 2, 8, 13,
    15, 6, 9, 15, 12, 0, 5, 9, 6, 10, 3, 4, 0, 5, 14, 3,
  ],
  [
    12, 10, 1, 15, 10, 4, 15, 2, 9, 7, 2, 12, 6, 9, 8, 5, //
    0, 6, 13, 1, 3, 13, 4, 14, 14, 0, 7, 11, 5, 3, 11, 8,
    9, 4, 14, 3, 15, 2, 5, 12, 2, 9, 8, 5, 12, 15, 3, 10,
    7, 11, 0, 14, 4, 1, 10, 7, 1, 6, 13, 0, 11, 8, 6, 13,
  ],
  [
    4, 13, 11, 0, 2, 11, 14, 7, 15, 4, 0, 9, 8, 1, 13, 10, //
    3, 14, 12, 3, 9, 5, 7, 12, 5, 2, 10, 15, 6, 8, 1, 6,
    1, 6, 4, 11, 11, 13, 13, 8, 12, 1, 3, 4, 7, 10, 14, 7,
    10, 9, 15, 5, 6, 0, 8, 15, 0, 14, 5, 2, 9, 3, 2, 12,
  ],
  [
    13, 1, 2, 15, 8, 13, 4, 8, 6, 10, 15, 3, 11, 7, 1, 4, //
    10, 12, 9, 5, 3, 6, 14, 11, 5, 0, 0, 14, 12, 9, 7, 2,
    7, 2, 11, 1, 4, 14, 1, 7, 9, 4, 12, 10, 14, 8, 2, 13,
    0, 15, 6, 12, 10, 9, 13, 0, 15, 3, 3, 5, 5, 6, 8, 11,
  ],
];

const _pTable = <int>[
  16, 7, 20, 21, //
  29, 12, 28, 17,
  1, 15, 23, 26,
  5, 18, 31, 10,
  2, 8, 24, 14,
  32, 27, 3, 9,
  19, 13, 30, 6,
  22, 11, 4, 25,
];

void _rol(Uint8List t) {
  final carryLeft = (t[0] & 0x80) >> 3;
  t[0] = ((t[0] << 1) | ((t[1] & 0x80) >> 7)) & 0xFF;
  t[1] = ((t[1] << 1) | ((t[2] & 0x80) >> 7)) & 0xFF;
  t[2] = ((t[2] << 1) | ((t[3] & 0x80) >> 7)) & 0xFF;
  final carryRight = (t[3] & 0x08) >> 3;
  t[3] = ((((t[3] << 1) | ((t[4] & 0x80) >> 7)) & ~0x10) | carryLeft) & 0xFF;
  t[4] = ((t[4] << 1) | ((t[5] & 0x80) >> 7)) & 0xFF;
  t[5] = ((t[5] << 1) | ((t[6] & 0x80) >> 7)) & 0xFF;
  t[6] = ((t[6] << 1) | carryRight) & 0xFF;
}

void _ror(Uint8List t) {
  final carryRight = (t[6] & 0x01) << 3;
  t[6] = ((t[6] >> 1) | ((t[5] & 0x01) << 7)) & 0xFF;
  t[5] = ((t[5] >> 1) | ((t[4] & 0x01) << 7)) & 0xFF;
  t[4] = ((t[4] >> 1) | ((t[3] & 0x01) << 7)) & 0xFF;
  final carryLeft = (t[3] & 0x10) << 3;
  t[3] = ((((t[3] >> 1) | ((t[2] & 0x01) << 7)) & ~0x08) | carryRight) & 0xFF;
  t[2] = ((t[2] >> 1) | ((t[1] & 0x01) << 7)) & 0xFF;
  t[1] = ((t[1] >> 1) | ((t[0] & 0x01) << 7)) & 0xFF;
  t[0] = ((t[0] >> 1) | carryLeft) & 0xFF;
}

enum _Op { encrypt, decrypt }

void _desBlockOperate(
  List<int> plaintext,
  Uint8List ciphertext,
  List<int> key,
  _Op op,
) {
  final ipBlock = Uint8List(desBlockSize);
  final expansionBlock = Uint8List(_expansionBlockSize);
  final substitutionBlock = Uint8List(desBlockSize ~/ 2);
  final pboxTarget = Uint8List(desBlockSize ~/ 2);
  final recombBox = Uint8List(desBlockSize ~/ 2);
  final pc1key = Uint8List(_pc1KeySize);
  final subkey = Uint8List(_subkeySize);

  _permute(ipBlock, plaintext, _ipTable, desBlockSize);
  _permute(pc1key, key, _pc1Table, _pc1KeySize);

  for (var round = 0; round < 16; round++) {
    _permute(expansionBlock, ipBlock.sublist(4), _expansionTable, 6);
    if (op == _Op.encrypt) {
      _rol(pc1key);
      if (!(round <= 1 || round == 8 || round == 15)) _rol(pc1key);
    }
    _permute(subkey, pc1key, _pc2Table, _subkeySize);
    if (op == _Op.decrypt) {
      _ror(pc1key);
      if (!(round >= 14 || round == 7 || round == 0)) _ror(pc1key);
    }
    _xor(expansionBlock, subkey, 6);

    substitutionBlock[0] = _sbox[0][(expansionBlock[0] & 0xFC) >> 2] << 4;
    substitutionBlock[0] |=
        _sbox[1][(expansionBlock[0] & 0x03) << 4 |
            (expansionBlock[1] & 0xF0) >> 4];
    substitutionBlock[1] =
        _sbox[2][(expansionBlock[1] & 0x0F) << 2 |
            (expansionBlock[2] & 0xC0) >> 6] <<
        4;
    substitutionBlock[1] |= _sbox[3][expansionBlock[2] & 0x3F];
    substitutionBlock[2] = _sbox[4][(expansionBlock[3] & 0xFC) >> 2] << 4;
    substitutionBlock[2] |=
        _sbox[5][(expansionBlock[3] & 0x03) << 4 |
            (expansionBlock[4] & 0xF0) >> 4];
    substitutionBlock[3] =
        _sbox[6][(expansionBlock[4] & 0x0F) << 2 |
            (expansionBlock[5] & 0xC0) >> 6] <<
        4;
    substitutionBlock[3] |= _sbox[7][expansionBlock[5] & 0x3F];

    _permute(pboxTarget, substitutionBlock, _pTable, desBlockSize ~/ 2);

    recombBox.setRange(0, 4, ipBlock);
    ipBlock.setRange(0, 4, ipBlock, 4);
    _xor(recombBox, pboxTarget, desBlockSize ~/ 2);
    ipBlock.setRange(4, 8, recombBox);
  }
  // Final swap
  final tmp = Uint8List.fromList(ipBlock.sublist(0, 4));
  ipBlock.setRange(0, 4, ipBlock, 4);
  ipBlock.setRange(4, 8, tmp);

  _permute(ciphertext, ipBlock, _fpTable, desBlockSize);
}

void _desOperate(
  List<int> input,
  Uint8List output,
  Uint8List iv,
  List<int> key,
  _Op op, {
  bool triplicate = false,
}) {
  if (input.length % desBlockSize != 0) {
    throw ArgumentError('input must be a multiple of DES block size (8)');
  }
  final block = Uint8List(desBlockSize);
  final keyBytes = key is Uint8List ? key : Uint8List.fromList(key);
  for (var off = 0; off < input.length; off += desBlockSize) {
    block.setRange(0, desBlockSize, input, off);
    if (op == _Op.encrypt) {
      _xor(block, iv, desBlockSize);
      _desBlockOperate(
        block,
        output.buffer.asUint8List(off, desBlockSize),
        keyBytes.sublist(0, desKeySize),
        op,
      );
      if (triplicate) {
        block.setRange(0, desBlockSize, output, off);
        _desBlockOperate(
          block,
          output.buffer.asUint8List(off, desBlockSize),
          keyBytes.sublist(desKeySize, 2 * desKeySize),
          _Op.decrypt,
        );
        block.setRange(0, desBlockSize, output, off);
        _desBlockOperate(
          block,
          output.buffer.asUint8List(off, desBlockSize),
          keyBytes.sublist(2 * desKeySize, 3 * desKeySize),
          op,
        );
      }
      iv.setRange(0, desBlockSize, output, off);
    } else {
      if (triplicate) {
        _desBlockOperate(
          block,
          output.buffer.asUint8List(off, desBlockSize),
          keyBytes.sublist(2 * desKeySize, 3 * desKeySize),
          op,
        );
        block.setRange(0, desBlockSize, output, off);
        _desBlockOperate(
          block,
          output.buffer.asUint8List(off, desBlockSize),
          keyBytes.sublist(desKeySize, 2 * desKeySize),
          _Op.encrypt,
        );
        block.setRange(0, desBlockSize, output, off);
        _desBlockOperate(
          block,
          output.buffer.asUint8List(off, desBlockSize),
          keyBytes.sublist(0, desKeySize),
          op,
        );
      } else {
        _desBlockOperate(
          block,
          output.buffer.asUint8List(off, desBlockSize),
          keyBytes.sublist(0, desKeySize),
          op,
        );
      }
      _xor(output.buffer.asUint8List(off, desBlockSize), iv, desBlockSize);
      iv.setRange(0, desBlockSize, input, off);
    }
  }
}

Uint8List desEncrypt(List<int> plaintext, List<int> iv, List<int> key) {
  final out = Uint8List(plaintext.length);
  _desOperate(plaintext, out, Uint8List.fromList(iv), key, _Op.encrypt);
  return out;
}

Uint8List desDecrypt(List<int> ciphertext, List<int> iv, List<int> key) {
  final out = Uint8List(ciphertext.length);
  _desOperate(ciphertext, out, Uint8List.fromList(iv), key, _Op.decrypt);
  return out;
}

Uint8List des3Encrypt(List<int> plaintext, List<int> iv, List<int> key) {
  final out = Uint8List(plaintext.length);
  _desOperate(
    plaintext,
    out,
    Uint8List.fromList(iv),
    key,
    _Op.encrypt,
    triplicate: true,
  );
  return out;
}

Uint8List des3Decrypt(List<int> ciphertext, List<int> iv, List<int> key) {
  final out = Uint8List(ciphertext.length);
  _desOperate(
    ciphertext,
    out,
    Uint8List.fromList(iv),
    key,
    _Op.decrypt,
    triplicate: true,
  );
  return out;
}
