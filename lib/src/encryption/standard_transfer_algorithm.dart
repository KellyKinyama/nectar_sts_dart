import 'dart:typed_data';

import '../base/bit_string.dart';
import '../base/nibble.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import 'encryption_algorithm.dart';
import 'tables.dart';

/// EA07 / Standard Transfer Algorithm — the 16-round
/// substitution-permutation cipher used by IEC 62055-41 to encrypt a
/// 64-bit token block under a 64-bit decoder key.
///
/// Direct port of
/// `domain/encryptionalgorithm/StandardTransferAlgorithmEncryptionAlgorithm.java`.
///
/// Pre-processing for encryption: the decoder key is bit-complemented
/// then rotated right by 12 bits. Each round substitutes 16 nibbles
/// using one of two 4→4 S-boxes (selected by the MSB of the key nibble
/// at the same position), runs a 64-bit permutation, and rotates the
/// key left by 1 bit. Decryption inverts the order: permute → S-box →
/// rotate-key-right.
class StandardTransferAlgorithm extends EncryptionAlgorithm {
  /// Constructs the EA07 (Standard Transfer Algorithm) cipher.
  StandardTransferAlgorithm() : super(EncryptionAlgorithmCode.sta);

  late DecoderKey _decoderKey;

  /// The decoder key used by the most recent [encrypt] / [decrypt]
  /// call (populated as a side-effect of those operations).
  DecoderKey get decoderKey => _decoderKey;

  @override
  BitString encrypt(DecoderKey decoderKey, BitString dataBlock64) {
    _decoderKey = decoderKey;
    final processedKey = _processKey(decoderKey);
    // Clone: _substitute mutates the BitString in place (it calls
    // setNibble), so without this the caller's plaintext would be
    // corrupted after the first round.
    return _encrypt64(processedKey, dataBlock64.clone());
  }

  @override
  BitString decrypt(DecoderKey decoderKey, BitString dataBlock64) {
    _decoderKey = decoderKey;
    return _decrypt64(
      Uint8List.fromList(decoderKey.keyData),
      dataBlock64.clone(),
    );
  }

  Uint8List _processKey(DecoderKey decoderKey) {
    final ec = decoderKey.keyData;
    final complemented = decoderKey.complement(ec);
    return decoderKey.rotateComplemented(complemented);
  }

  BitString _encrypt64(Uint8List key, BitString block) {
    var k = key;
    var b = block;
    for (var round = 0; round < 16; round++) {
      b = _substitute(
        k,
        b,
        firstTable: encryptingFirstSubstitutionTable,
        secondTable: encryptingSecondSubstitutionTable,
        // Encrypt path: check the MSB of the key nibble at offset +3
        // within the nibble's 4-bit window (i.e. the high bit of the
        // 4-bit window when read MSB-first).
        keyBitOffsetWithinNibble: 3,
      );
      b = _permutate(b, encryptingPermutationTable);
      k = _decoderKey.rotateLeft(k, 1);
    }
    return b;
  }

  BitString _decrypt64(Uint8List key, BitString block) {
    var k = key;
    var b = block;
    for (var round = 0; round < 16; round++) {
      b = _permutate(b, decryptingPermutationTable);
      b = _substitute(
        k,
        b,
        firstTable: decryptingFirstSubstitutionTable,
        secondTable: decryptingSecondSubstitutionTable,
        // Decrypt path: the key-bit selector is at offset 0 within the
        // nibble (not +3 as in encrypt).
        keyBitOffsetWithinNibble: 0,
      );
      k = _decoderKey.rotateRight(k, 1);
    }
    return b;
  }

  BitString _permutate(BitString block, List<int> table) {
    if (block.length != 64) {
      throw const InvalidBitStringException(
        'EA07 permutate requires a 64-bit data block',
      );
    }
    final out = BitString.fromValue(0, 64);
    for (var i = 0; i < 64; i++) {
      final dst = table[i];
      final srcBit = block.getBit(i);
      out.setBitChar(dst, srcBit.value);
    }
    return out;
  }

  BitString _substitute(
    Uint8List key,
    BitString block, {
    required List<int> firstTable,
    required List<int> secondTable,
    required int keyBitOffsetWithinNibble,
  }) {
    var b = block;
    for (var nibblePos = 0; nibblePos < 16; nibblePos++) {
      final keyBitIndex = nibblePos * 4 + keyBitOffsetWithinNibble;
      final selector = _decoderKey.getKeyBit(key, keyBitIndex);

      final currentNibble = b.getNibble(nibblePos);
      final nibbleValue = currentNibble.nibble.value;

      final substituted = selector == 0
          ? _lookupNibble(nibbleValue, firstTable)
          : _lookupNibble(nibbleValue, secondTable);

      b.setNibble(nibblePos, substituted);
    }
    return b;
  }

  Nibble _lookupNibble(int nibbleValue, List<int> table) {
    final mapped = table[nibbleValue];
    final bs = BitString.fromValue(mapped, 4);
    return Nibble.fromBitString(bs);
  }
}
