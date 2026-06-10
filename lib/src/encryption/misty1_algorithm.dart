import 'dart:typed_data';

import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import 'encryption_algorithm.dart';
import 'misty1.dart';

/// EA11 / MISTY1 encryption algorithm.
///
/// Direct port of
/// `domain/encryptionalgorithm/Misty1AlgorithmEncryptionAlgorithm.java`.
/// The block primitive lives in [Misty1]; this class is the
/// `EncryptionAlgorithm` adapter: 64-bit `BitString` <-> 8-byte block,
/// 16-byte `DecoderKey` <-> 128-bit MISTY1 key.
class Misty1EncryptionAlgorithm extends EncryptionAlgorithm {
  Misty1EncryptionAlgorithm() : super(EncryptionAlgorithmCode.misty1);

  @override
  BitString encrypt(DecoderKey decoderKey, BitString dataBlock) {
    final ct = Misty1.encrypt(
      _checkKey(decoderKey),
      _longTo8Bytes(dataBlock.value),
    );
    return BitString.fromValue(_bytesToLong(ct));
  }

  @override
  BitString decrypt(DecoderKey decoderKey, BitString dataBlock) {
    final pt = Misty1.decrypt(
      _checkKey(decoderKey),
      _longTo8Bytes(dataBlock.value),
    );
    return BitString.fromValue(_bytesToLong(pt));
  }

  /// Public byte-array form used by callers that already have raw
  /// 16-byte key + 8-byte block buffers (e.g. test harnesses).
  Uint8List encryptBytes(List<int> key, List<int> input) =>
      Misty1.encrypt(key, input);

  Uint8List decryptBytes(List<int> key, List<int> input) =>
      Misty1.decrypt(key, input);
}

List<int> _checkKey(DecoderKey key) {
  if (key.keyData.length != Misty1.keyLength) {
    throw InvalidKeyDataException(
      'MISTY1 decoder key must be exactly 16 bytes '
      '(was ${key.keyData.length})',
    );
  }
  return key.keyData;
}

List<int> _longTo8Bytes(int v) {
  final out = Uint8List(8);
  var x = v;
  for (var i = 7; i >= 0; i--) {
    out[i] = x & 0xFF;
    x >>= 8;
  }
  return out;
}

int _bytesToLong(List<int> b) {
  var r = 0;
  for (var i = 0; i < 8; i++) {
    r <<= 8;
    r |= (b[i] & 0xFF);
  }
  return r;
}
