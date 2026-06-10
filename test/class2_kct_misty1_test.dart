import 'dart:typed_data';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('Class 2 3rd/4th Section Decoder Key Change (MISTY1)', () {
    // 160-bit vending key required by DKGA-04.
    final vendingKey = VendingCommonDesKey(
      parseHexKey('0123456789ABCDEF0123456789ABCDEF01234567'),
    );

    DecoderKey deriveCurrent({int kr = 1, String ti = '07'}) =>
        DecoderKeyGeneratorAlgorithm04(
          baseDate: BaseDate.date1993,
          tariffIndex: TariffIndex(ti),
          supplyGroupCode: SupplyGroupCode('123456'),
          keyType: KeyType(2),
          keyRevisionNumber: KeyRevisionNumber(kr),
          encryptionAlgorithm: Misty1EncryptionAlgorithm(),
          meterPan: MeterPrimaryAccountNumber(
            issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
            individualAccountIdentificationNumber:
                IndividualAccountIdentificationNumber('12345678901'),
          ),
          vendingKey: vendingKey,
        ).generate();

    test('splitMisty1DecoderKey + combineMisty1DecoderKey are inverses', () {
      final bytes = Uint8List.fromList(List<int>.generate(16, (i) => i * 17));
      final key = DecoderKey(bytes);
      final s = splitMisty1DecoderKey(key);
      final rebuilt = combineMisty1DecoderKey(
        s.high,
        s.middle2,
        s.middle1,
        s.low,
      );
      expect(_hex(rebuilt.keyData), _hex(key.keyData));
    });

    test('splitMisty1DecoderKey is bytewise big-endian', () {
      // bytes [0..15] = [0x00, 0x11, .. 0xFF] -> halves in BE order.
      final bytes = Uint8List.fromList(List<int>.generate(16, (i) => i * 0x11));
      final key = DecoderKey(bytes);
      final s = splitMisty1DecoderKey(key);
      expect(s.high.bitString.toPaddedBinary().substring(0, 8), '00000000');
      expect(s.middle2.bitString.toPaddedBinary().substring(0, 8), '01000100');
      expect(s.middle1.bitString.toPaddedBinary().substring(0, 8), '10001000');
      expect(s.low.bitString.toPaddedBinary().substring(0, 8), '11001100');
    });

    test(
      'SupplyGroupCodeHighOrder/LowOrder split a 6-digit SGC bit-exactly',
      () {
        final sgc = SupplyGroupCode('999999'); // 20 bits set
        final hi = SupplyGroupCodeHighOrder.fromSupplyGroupCode(sgc);
        final lo = SupplyGroupCodeLowOrder.fromSupplyGroupCode(sgc);
        // 999999 = 0b11110100001000111111 padded to 24 bits:
        //   0000 1111 0100 0010 0011 1111
        // high 12 = 0000 1111 0100 = 0x0F4 = 244
        // low  12 = 0010 0011 1111 = 0x23F = 575
        expect(hi.bitString.value, 0x0F4);
        expect(lo.bitString.value, 0x23F);
      },
    );

    test('Set3rdSection round-trip: generator → decoder', () {
      final currentKey = deriveCurrent(kr: 1, ti: '07');
      final newKey = deriveCurrent(kr: 2, ti: '08');
      final gen = Set3rdSectionDecoderKeyTokenGenerator(
        decoderKey: currentKey,
        encryptionAlgorithm: Misty1EncryptionAlgorithm(),
        supplyGroupCode: SupplyGroupCode('123456'),
        newDecoderKey: newKey,
      );
      final token = gen.generateNew('rt-3rd');

      final decoder = Class2TokenDecoder(
        currentKey,
        Misty1EncryptionAlgorithm(),
      );
      final decoded =
          decoder.decodeBinary66('rt-3rd-dec', token.encryptedTokenBitString!)
              as Set3rdSectionDecoderKeyToken;

      final expectedSgclo = SupplyGroupCodeLowOrder.fromSupplyGroupCode(
        SupplyGroupCode('123456'),
      );
      final expectedNkmo2 = splitMisty1DecoderKey(newKey).middle2;

      expect(
        decoded.supplyGroupCodeLowOrder!.bitString.value,
        expectedSgclo.bitString.value,
      );
      expect(
        decoded.newKeyMiddleOrder2!.bitString.toPaddedBinary(),
        expectedNkmo2.bitString.toPaddedBinary(),
      );
      expect(decoded.tokenSubClass!.bitString.value, 0x8);
    });

    test('Set4thSection round-trip: generator → decoder', () {
      final currentKey = deriveCurrent(kr: 1, ti: '07');
      final newKey = deriveCurrent(kr: 2, ti: '08');
      final gen = Set4thSectionDecoderKeyTokenGenerator(
        decoderKey: currentKey,
        encryptionAlgorithm: Misty1EncryptionAlgorithm(),
        supplyGroupCode: SupplyGroupCode('123456'),
        newDecoderKey: newKey,
      );
      final token = gen.generateNew('rt-4th');

      final decoder = Class2TokenDecoder(
        currentKey,
        Misty1EncryptionAlgorithm(),
      );
      final decoded =
          decoder.decodeBinary66('rt-4th-dec', token.encryptedTokenBitString!)
              as Set4thSectionDecoderKeyToken;

      final expectedSgcho = SupplyGroupCodeHighOrder.fromSupplyGroupCode(
        SupplyGroupCode('123456'),
      );
      final expectedNkmo1 = splitMisty1DecoderKey(newKey).middle1;

      expect(
        decoded.supplyGroupCodeHighOrder!.bitString.value,
        expectedSgcho.bitString.value,
      );
      expect(
        decoded.newKeyMiddleOrder1!.bitString.toPaddedBinary(),
        expectedNkmo1.bitString.toPaddedBinary(),
      );
      expect(decoded.tokenSubClass!.bitString.value, 0x9);
    });

    test('Full 4-section round-trip rebuilds the 128-bit MISTY1 key', () {
      final currentKey = deriveCurrent(kr: 1, ti: '07');
      final newKey = deriveCurrent(kr: 2, ti: '08');
      final ea = Misty1EncryptionAlgorithm();

      final g1 = Set1stSectionDecoderKeyTokenGenerator(
        decoderKey: currentKey,
        encryptionAlgorithm: ea,
        keyExpiryNumberHighOrder: KeyExpiryNumberHighOrder(
          BitString.fromValue(0xA, 4),
        ),
        keyRevisionNumber: KeyRevisionNumber(2),
        rolloverKeyChange: RolloverKeyChange.fromBool(false),
        keyType: KeyType(2),
        newDecoderKey: newKey,
      );
      final g2 = Set2ndSectionDecoderKeyTokenGenerator(
        decoderKey: currentKey,
        encryptionAlgorithm: ea,
        keyExpiryNumberLowOrder: KeyExpiryNumberLowOrder(
          BitString.fromValue(0xB, 4),
        ),
        tariffIndex: TariffIndex('08'),
        newDecoderKey: newKey,
      );
      final g3 = Set3rdSectionDecoderKeyTokenGenerator(
        decoderKey: currentKey,
        encryptionAlgorithm: ea,
        supplyGroupCode: SupplyGroupCode('123456'),
        newDecoderKey: newKey,
      );
      final g4 = Set4thSectionDecoderKeyTokenGenerator(
        decoderKey: currentKey,
        encryptionAlgorithm: ea,
        supplyGroupCode: SupplyGroupCode('123456'),
        newDecoderKey: newKey,
      );

      final t1 = g1.generateNew('q1');
      final t2 = g2.generateNew('q2');
      final t3 = g3.generateNew('q3');
      final t4 = g4.generateNew('q4');

      final dec = Class2TokenDecoder(currentKey, ea);
      final d1 =
          dec.decodeBinary66('d1', t1.encryptedTokenBitString!)
              as Set1stSectionDecoderKeyToken;
      final d2 =
          dec.decodeBinary66('d2', t2.encryptedTokenBitString!)
              as Set2ndSectionDecoderKeyToken;
      final d3 =
          dec.decodeBinary66('d3', t3.encryptedTokenBitString!)
              as Set3rdSectionDecoderKeyToken;
      final d4 =
          dec.decodeBinary66('d4', t4.encryptedTokenBitString!)
              as Set4thSectionDecoderKeyToken;

      final rebuilt = combineMisty1DecoderKey(
        d1.newKeyHighOrder!,
        d3.newKeyMiddleOrder2!,
        d4.newKeyMiddleOrder1!,
        d2.newKeyLowOrder!,
      );
      expect(_hex(rebuilt.keyData), _hex(newKey.keyData));
    });

    test('Set3rdSection generator rejects STA', () {
      final currentKey = DecoderKey(Uint8List(8));
      expect(
        () => Set3rdSectionDecoderKeyTokenGenerator(
          decoderKey: currentKey,
          encryptionAlgorithm: StandardTransferAlgorithm(),
          supplyGroupCode: SupplyGroupCode('123456'),
          newDecoderKey: DecoderKey(Uint8List(16)),
        ),
        throwsA(isA<NotImplementedException>()),
      );
    });

    test('Set4thSection generator rejects STA', () {
      final currentKey = DecoderKey(Uint8List(8));
      expect(
        () => Set4thSectionDecoderKeyTokenGenerator(
          decoderKey: currentKey,
          encryptionAlgorithm: StandardTransferAlgorithm(),
          supplyGroupCode: SupplyGroupCode('123456'),
          newDecoderKey: DecoderKey(Uint8List(16)),
        ),
        throwsA(isA<NotImplementedException>()),
      );
    });
  });
}
