import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

void main() {
  group('BitString', () {
    test('fromBinary round-trips through extractBits', () {
      final bs = BitString.fromBinary('1100101100110001'); // 16 bits
      // LSB-first: bit 0 == '1' (rightmost), bit 15 == '1' (leftmost).
      expect(bs.length, 16);
      expect(bs.getBit(0).intValue, 1);
      expect(bs.getBit(1).intValue, 0);
      expect(bs.getBit(15).intValue, 1);

      // Extract the low 8 bits.
      final low = bs.extractBits(0, 8);
      expect(low.length, 8);
      expect(low.value, 0x31); // 0011 0001 == 0x31
    });

    test('concat shifts new fields into higher significance', () {
      final a = BitString.fromValue(0xA, 4); // 1010
      final b = BitString.fromValue(0x5, 4); // 0101
      final ab = a.concat([b]);
      expect(ab.length, 8);
      // a stays in the low nibble (0xA), b shifts up by 4 -> 0x5A
      expect(ab.value, 0x5A);
    });

    test('rotate right by 1 on a 64-bit string', () {
      final bs = BitString.fromValue(0x8000000000000001, 64);
      final r = BitString.rotate(bs, RotateDirection.right, 1);
      expect(r.length, 64);
      // 0xC000000000000000 as a 64-bit signed int.
      expect(r.value, 0xC000000000000000);
    });
  });

  group('CRC-16/IBM (reversed 0xA001)', () {
    test('matches Modbus reference vector', () {
      // Standard Modbus test vector for "123456789" → 0x4B37
      // BUT the Nectar code byte-swaps before returning, so 0x374B.
      final c = Crc();
      final bytes = '123456789'.codeUnits;
      final raw = c.generateCrcBytes(bytes);
      expect(raw, 0x374B);
    });
  });

  group('Luhn check digit', () {
    test('Nectar variant doubles starting from the rightmost digit', () {
      // Nectar's `LuhnAlgorithm` toggles `alternate=true` BEFORE the
      // first iteration, so the rightmost digit is doubled rather than
      // left as-is (the standard Luhn rule). For 428671502 this yields
      // 6, not the standard-Luhn 3.
      expect(LuhnAlgorithm.generateCheckDigit(428671502), 6);
    });
  });

  group('TokenIdentifier', () {
    test('TID is minutes between BaseDate and time-of-issue', () {
      final t = TokenIdentifier(
        BaseDate.date1993,
        timeOfIssue: DateTime.utc(1993, 1, 1, 1, 0, 0),
      );
      expect(t.getDifferenceFromBaseTimeInMinutes(), 60);
      expect(t.bitString.length, 24);
    });
  });

  group('Utils amount encoding', () {
    test('encode + decode follows the 1/10 scaling convention', () {
      // Per IEC 62055-41 the on-wire amount is in TENTHS of the unit
      // (kWh / litre / m³). convertToBitString takes the unscaled
      // value, convertToDouble divides by 10 on the way out, so the
      // round-trip identity is `decode(encode(x)) == ceil(x) / 10`
      // for exponent==0 inputs.
      for (final units in [1, 10, 100, 999, 16383]) {
        final encoded = Utils.convertToBitString(units.toDouble());
        encoded.length = 16;
        final back = Utils.convertToDouble(encoded);
        expect(
          back,
          closeTo(units / 10.0, 1e-9),
          reason: 'units=$units back=$back',
        );
      }
    });
  });
}
