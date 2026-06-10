import 'dart:typed_data';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('DKGA-04 + MISTY1 integration', () {
    // 160-bit vending key required by DKGA-04 (per the Java upstream).
    final vendingKey = VendingCommonDesKey(
      parseHexKey('0123456789ABCDEF0123456789ABCDEF01234567'),
    );

    test('DKGA-04 derives a 16-byte decoder key for EA11 (MISTY1)', () {
      final dk = DecoderKeyGeneratorAlgorithm04(
        baseDate: BaseDate.date1993,
        tariffIndex: TariffIndex('07'),
        supplyGroupCode: SupplyGroupCode('123456'),
        keyType: KeyType(2),
        keyRevisionNumber: KeyRevisionNumber(1),
        encryptionAlgorithm: Misty1EncryptionAlgorithm(),
        meterPan: MeterPrimaryAccountNumber(
          issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
          individualAccountIdentificationNumber:
              IndividualAccountIdentificationNumber('12345678901'),
        ),
        vendingKey: vendingKey,
      ).generate();

      expect(dk.keyData, hasLength(16));
    });

    test('MISTY1 EA encrypt/decrypt round-trip via DecoderKey', () {
      final dk = DecoderKeyGeneratorAlgorithm04(
        baseDate: BaseDate.date1993,
        tariffIndex: TariffIndex('07'),
        supplyGroupCode: SupplyGroupCode('123456'),
        keyType: KeyType(2),
        keyRevisionNumber: KeyRevisionNumber(1),
        encryptionAlgorithm: Misty1EncryptionAlgorithm(),
        meterPan: MeterPrimaryAccountNumber(
          issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
          individualAccountIdentificationNumber:
              IndividualAccountIdentificationNumber('12345678901'),
        ),
        vendingKey: vendingKey,
      ).generate();

      final ea = Misty1EncryptionAlgorithm();
      final pt = BitString.fromValue(0x0123456789ABCDEF, 64);
      final ct = ea.encrypt(dk, pt);
      final pt2 = ea.decrypt(dk, ct);
      expect(pt2.toPaddedBinary(), pt.toPaddedBinary());
    });

    test('Misty1EncryptionAlgorithm rejects an 8-byte DecoderKey', () {
      final shortKey = DecoderKey(Uint8List(8));
      expect(
        () => Misty1EncryptionAlgorithm().encrypt(
          shortKey,
          BitString.fromValue(0, 64),
        ),
        throwsA(isA<InvalidKeyDataException>()),
      );
    });

    test(
      'Two derivations with the same params produce the same MISTY1 key',
      () {
        DecoderKey derive() => DecoderKeyGeneratorAlgorithm04(
          baseDate: BaseDate.date2014,
          tariffIndex: TariffIndex('11'),
          supplyGroupCode: SupplyGroupCode('999000'),
          keyType: KeyType(2),
          keyRevisionNumber: KeyRevisionNumber(3),
          encryptionAlgorithm: Misty1EncryptionAlgorithm(),
          meterPan: MeterPrimaryAccountNumber(
            issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
            individualAccountIdentificationNumber:
                IndividualAccountIdentificationNumber('98765432109'),
          ),
          vendingKey: vendingKey,
        ).generate();

        expect(_hex(derive().keyData), _hex(derive().keyData));
      },
    );
  });
}
