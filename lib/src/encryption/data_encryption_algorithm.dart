import 'dart:typed_data';

import 'package:tls/tls.dart' as tls;

import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import 'encryption_algorithm.dart';

/// EA09 / Data Encryption Algorithm — single-DES in ECB mode on a
/// single 8-byte block.
///
/// Direct port of `domain/encryptionalgorithm/DataEncryptionAlgorithm.java`
/// but the DES primitive comes from the local `tls` package
/// (`package:tls/cipher/des.dart`) instead of JCE / BouncyCastle.
///
/// Notes on the Java original we deliberately do NOT replicate:
///
/// - The Java `convertToDESKeyWithOddParity` uses `1 << 8` instead of
///   `1 << 0`, so the "parity fix" is a no-op — it never actually
///   alters the key bytes. We skip that whole step.
/// - The Java code only implements `encrypt(...)`. `decrypt(...)`
///   throws `NotImplementedException`. We provide a real DES decrypt
///   because the Dart port has no reason to omit it.
class DataEncryptionAlgorithm extends EncryptionAlgorithm {
  DataEncryptionAlgorithm() : super(EncryptionAlgorithmCode.dea);

  @override
  BitString encrypt(DecoderKey decoderKey, BitString dataBlock) {
    final ct = _desEcbEncrypt(
      decoderKey.keyData,
      _longTo8Bytes(dataBlock.value),
    );
    return BitString.fromValue(_bytesToLong(ct));
  }

  @override
  BitString decrypt(DecoderKey decoderKey, BitString dataBlock) {
    final pt = _desEcbDecrypt(
      decoderKey.keyData,
      _longTo8Bytes(dataBlock.value),
    );
    return BitString.fromValue(_bytesToLong(pt));
  }

  /// Public form used by DKGA-02 with raw vending-key bytes.
  Uint8List encryptBytes(List<int> key, List<int> input) =>
      _desEcbEncrypt(key, input);

  Uint8List decryptBytes(List<int> key, List<int> input) =>
      _desEcbDecrypt(key, input);
}

Uint8List _desEcbEncrypt(List<int> key, List<int> input) {
  if (key.length != 8) {
    throw const InvalidKeyDataException('DES key must be exactly 8 bytes');
  }
  if (input.length % 8 != 0) {
    throw const InvalidKeyDataException(
      'DES input length must be a multiple of 8 bytes',
    );
  }
  // ECB == CBC with zero IV and one block, processed independently.
  final out = Uint8List(input.length);
  for (var off = 0; off < input.length; off += 8) {
    final zeroIv = Uint8List(8);
    final block = input.sublist(off, off + 8);
    final ct = tls.desEncrypt(block, zeroIv, key);
    out.setRange(off, off + 8, ct);
  }
  return out;
}

Uint8List _desEcbDecrypt(List<int> key, List<int> input) {
  if (key.length != 8) {
    throw const InvalidKeyDataException('DES key must be exactly 8 bytes');
  }
  if (input.length % 8 != 0) {
    throw const InvalidKeyDataException(
      'DES input length must be a multiple of 8 bytes',
    );
  }
  final out = Uint8List(input.length);
  for (var off = 0; off < input.length; off += 8) {
    final zeroIv = Uint8List(8);
    final block = input.sublist(off, off + 8);
    final pt = tls.desDecrypt(block, zeroIv, key);
    out.setRange(off, off + 8, pt);
  }
  return out;
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
