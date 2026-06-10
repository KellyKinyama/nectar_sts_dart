import 'dart:typed_data';

import 'package:nectar_sts_dart/src/encryption/misty1.dart';
import 'package:test/test.dart';

Uint8List _h(String hex) {
  final clean = hex.replaceAll(' ', '').replaceAll(':', '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('MISTY1 — RFC 2994 test vectors', () {
    // RFC 2994 Appendix A.1 (single key, two-block plaintext).
    final key = _h('00112233 44556677 8899aabb ccddeeff');

    test('block 1: 0123456789abcdef -> 8b1da5f56ab3d07c', () {
      final pt = _h('01234567 89abcdef');
      final ctExpected = _h('8b1da5f5 6ab3d07c');

      final ct = Misty1.encrypt(key, pt);
      expect(_hex(ct), _hex(ctExpected));

      final pt2 = Misty1.decrypt(key, ct);
      expect(_hex(pt2), _hex(pt));
    });

    test('block 2: fedcba9876543210 -> 04b68240b13be95d', () {
      final pt = _h('fedcba98 76543210');
      final ctExpected = _h('04b68240 b13be95d');

      final ct = Misty1.encrypt(key, pt);
      expect(_hex(ct), _hex(ctExpected));

      final pt2 = Misty1.decrypt(key, ct);
      expect(_hex(pt2), _hex(pt));
    });
  });

  group('MISTY1 — round-trip property', () {
    test('100 random encrypt+decrypt round-trips', () {
      // Deterministic pseudo-random — no platform RNG so vector
      // failures are reproducible.
      var state = 0x12345678;
      int next() {
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
        return state & 0xFF;
      }

      for (var i = 0; i < 100; i++) {
        final key = Uint8List.fromList(List.generate(16, (_) => next()));
        final pt = Uint8List.fromList(List.generate(8, (_) => next()));
        final ct = Misty1.encrypt(key, pt);
        final pt2 = Misty1.decrypt(key, ct);
        expect(_hex(pt2), _hex(pt), reason: 'iteration $i');
      }
    });
  });

  group('MISTY1 — input validation', () {
    test('rejects wrong key length', () {
      expect(
        () => Misty1.encrypt(Uint8List(15), Uint8List(8)),
        throwsA(anything),
      );
      expect(
        () => Misty1.encrypt(Uint8List(17), Uint8List(8)),
        throwsA(anything),
      );
    });

    test('rejects wrong block length', () {
      expect(
        () => Misty1.encrypt(Uint8List(16), Uint8List(7)),
        throwsA(anything),
      );
      expect(
        () => Misty1.decrypt(Uint8List(16), Uint8List(9)),
        throwsA(anything),
      );
    });
  });
}
