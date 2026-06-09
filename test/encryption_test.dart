import 'dart:typed_data';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Key (per-byte LSB-first bit accessors, mirrors Java)', () {
    test(
      'getKeyBit reads pos=0 as the LSB of byte 0, pos=7 as the MSB of byte 0',
      () {
        // Java `Key.getBit`: pos / 8 picks the byte, then within the byte
        // pos=0 -> LSB, pos=7 -> MSB. Bit numbering is LSB-first inside
        // each byte but byte 0 still comes "first". This mirrors
        // BitString's LSB-first convention but is unrelated to
        // network-order MSB-first.
        final k = DecoderKey([0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]);
        expect(k.getKeyBit(k.keyData, 0), 0); // LSB of 0x80
        expect(k.getKeyBit(k.keyData, 7), 1); // MSB of 0x80
        expect(k.getKeyBit(k.keyData, 56), 1); // LSB of 0x01
        expect(k.getKeyBit(k.keyData, 63), 0); // MSB of 0x01
      },
    );

    test('rotate-left by 1 moves bit p -> bit (p+1) mod 64', () {
      // input bit 7 (MSB of byte 0) -> output bit 8 = LSB of byte 1
      // input bit 56 (LSB of byte 7) -> output bit 57 = bit 1 of byte 7
      final k = DecoderKey([0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]);
      final r = k.rotateLeft(k.keyData, 1);
      expect(r, Uint8List.fromList([0x00, 0x01, 0, 0, 0, 0, 0, 0x02]));
    });

    test('rotate-right by 1 is the inverse of rotate-left by 1', () {
      final k = DecoderKey([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04]);
      final l = k.rotateLeft(k.keyData, 1);
      final r = k.rotateRight(l, 1);
      expect(r, k.keyData);
    });

    test('complement is bitwise NOT over the first 8 bytes', () {
      final k = DecoderKey([0x00, 0xFF, 0xAA, 0x55, 0x12, 0x34, 0x56, 0x78]);
      final c = k.complement(k.keyData);
      expect(
        c,
        Uint8List.fromList([0xFF, 0x00, 0x55, 0xAA, 0xED, 0xCB, 0xA9, 0x87]),
      );
    });
  });

  group('EA09 / DES round-trip', () {
    test('encrypt then decrypt restores plaintext', () {
      final key = DecoderKey([0x13, 0x34, 0x57, 0x79, 0x9B, 0xBC, 0xDF, 0xF1]);
      final plain = BitString.fromValue(0x0123456789ABCDEF);
      final ea09 = DataEncryptionAlgorithm();
      final ct = ea09.encrypt(key, plain);
      final back = ea09.decrypt(key, ct);
      expect(back.value, plain.value);
    });

    test('matches known DES test vector', () {
      // FIPS 81 test vector: key=0x0123456789ABCDEF, pt=0x0123456789ABCDE7
      // ct=0xC95744256A5ED31D. Compare as ints; Dart VM int is 64-bit
      // signed so 0xC95744256A5ED31D fits as a negative literal.
      final key = DecoderKey([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]);
      final plain = BitString.fromValue(0x0123456789ABCDE7);
      final ea09 = DataEncryptionAlgorithm();
      final ct = ea09.encrypt(key, plain);
      expect(ct.value, 0xC95744256A5ED31D);
    });
  });

  group('EA07 / Standard Transfer Algorithm round-trip', () {
    test('encrypt + decrypt restores any 64-bit block', () {
      final key = DecoderKey([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04]);
      final blocks = [
        0x0000000000000000,
        0xFFFFFFFFFFFFFFFF,
        0xDEADBEEFCAFEBABE,
        0x123456789ABCDEF0,
      ];
      final ea07 = StandardTransferAlgorithm();
      for (final v in blocks) {
        final pt = BitString.fromValue(v, 64);
        final ct = ea07.encrypt(key, pt);
        expect(ct.length, 64);
        final back = ea07.decrypt(key, ct);
        expect(
          back.value,
          pt.value,
          reason: 'failed for 0x${v.toUnsigned(64).toRadixString(16)}',
        );
      }
    });

    test('ciphertext changes when one key bit changes', () {
      final pt = BitString.fromValue(0xCAFEBABE12345678, 64);
      final ea07 = StandardTransferAlgorithm();
      final ct1 = ea07.encrypt(
        DecoderKey([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04]),
        pt,
      );
      final ct2 = ea07.encrypt(
        DecoderKey([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x05]),
        pt,
      );
      expect(ct1.value, isNot(equals(ct2.value)));
    });
  });
}
