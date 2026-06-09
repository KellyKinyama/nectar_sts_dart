import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Domain primitives', () {
    test('IssuerIdentificationNumber accepts 6-digit and "0000"', () {
      expect(IssuerIdentificationNumber('600727').value, '600727');
      expect(IssuerIdentificationNumber('0000').value, '0000');
      expect(
        () => IssuerIdentificationNumber('12345'),
        throwsA(isA<InvalidIssuerIdentificationNumberException>()),
      );
    });

    test('ControlBlock value layout: KT + SGC + TI + KRN + FFFFFF', () {
      final cb = ControlBlock(
        keyType: KeyType(2),
        supplyGroupCode: SupplyGroupCode('123456'),
        tariffIndex: TariffIndex('07'),
        keyRevisionNumber: KeyRevisionNumber(1),
      );
      expect(cb.value, '2123456071FFFFFF');
      // 1 + 6 + 2 + 1 + 6 = 16 chars = 8 bytes
      expect(cb.value.length, 16);
    });

    test(
      'PrimaryAccountNumberBlock for 6-digit IIN keeps last 5 + last 11 of IAIN',
      () {
        final iin = IssuerIdentificationNumber('600727');
        final iain = IndividualAccountIdentificationNumber('12345678901');
        final pan = PrimaryAccountNumberBlock(
          issuerIdentificationNumber: iin,
          individualAccountIdentificationNumber: iain,
          keyType: KeyType(2),
        );
        expect(pan.value, '0072712345678901');
        expect(pan.value.length, 16);
      },
    );

    test('PrimaryAccountNumberBlock for KT=3 zeros out the IAIN portion', () {
      final iin = IssuerIdentificationNumber('600727');
      final iain = IndividualAccountIdentificationNumber('12345678901');
      final pan = PrimaryAccountNumberBlock(
        issuerIdentificationNumber: iin,
        individualAccountIdentificationNumber: iain,
        keyType: KeyType(3),
      );
      expect(pan.value, '0072700000000000');
    });

    test(
      'MeterPrimaryAccountNumber builds 18-digit PAN with Nectar Luhn check',
      () {
        final iin = IssuerIdentificationNumber('600727');
        final iain = IndividualAccountIdentificationNumber('12345678901');
        final mpan = MeterPrimaryAccountNumber(
          issuerIdentificationNumber: iin,
          individualAccountIdentificationNumber: iain,
        );
        expect(mpan.meterPanValue.length, 18);
        expect(mpan.meterPanValue.startsWith('60072712345678901'), isTrue);
      },
    );
  });

  group('DKGA-02', () {
    test('produces an 8-byte decoder key', () {
      final dkga = DecoderKeyGeneratorAlgorithm02(
        keyType: KeyType(2),
        supplyGroupCode: SupplyGroupCode('123456'),
        tariffIndex: TariffIndex('07'),
        keyRevisionNumber: KeyRevisionNumber(1),
        issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
        individualAccountIdentificationNumber:
            IndividualAccountIdentificationNumber('12345678901'),
        vendingKey: VendingCommonDesKey([
          0x01,
          0x23,
          0x45,
          0x67,
          0x89,
          0xAB,
          0xCD,
          0xEF,
        ]),
      );
      final dk = dkga.generate();
      expect(dk.keyData.length, 8);
    });

    test('is deterministic for fixed inputs', () {
      DecoderKey gen() => DecoderKeyGeneratorAlgorithm02(
        keyType: KeyType(2),
        supplyGroupCode: SupplyGroupCode('123456'),
        tariffIndex: TariffIndex('07'),
        keyRevisionNumber: KeyRevisionNumber(1),
        issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
        individualAccountIdentificationNumber:
            IndividualAccountIdentificationNumber('12345678901'),
        vendingKey: VendingCommonDesKey([
          0x01,
          0x23,
          0x45,
          0x67,
          0x89,
          0xAB,
          0xCD,
          0xEF,
        ]),
      ).generate();
      expect(gen().keyData, gen().keyData);
    });

    test('changing the KRN changes the derived key', () {
      DecoderKey gen(int krn) => DecoderKeyGeneratorAlgorithm02(
        keyType: KeyType(2),
        supplyGroupCode: SupplyGroupCode('123456'),
        tariffIndex: TariffIndex('07'),
        keyRevisionNumber: KeyRevisionNumber(krn),
        issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
        individualAccountIdentificationNumber:
            IndividualAccountIdentificationNumber('12345678901'),
        vendingKey: VendingCommonDesKey([
          0x01,
          0x23,
          0x45,
          0x67,
          0x89,
          0xAB,
          0xCD,
          0xEF,
        ]),
      ).generate();
      expect(gen(1).keyData, isNot(gen(2).keyData));
    });
  });

  group('DKGA-04 + EA07 end-to-end', () {
    test(
      'derives an 8-byte STA decoder key and round-trips a 64-bit block',
      () {
        final dkga = DecoderKeyGeneratorAlgorithm04(
          baseDate: BaseDate.date2014,
          tariffIndex: TariffIndex('07'),
          supplyGroupCode: SupplyGroupCode('123456'),
          keyType: KeyType(2),
          keyRevisionNumber: KeyRevisionNumber(1),
          encryptionAlgorithm: StandardTransferAlgorithm(),
          meterPan: MeterPrimaryAccountNumber(
            issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
            individualAccountIdentificationNumber:
                IndividualAccountIdentificationNumber('12345678901'),
          ),
          // 20-byte (160-bit) HMAC vending key.
          vendingKey: VendingUniqueDesKey(List<int>.generate(20, (i) => i + 1)),
        );
        final dk = dkga.generate();
        expect(dk.keyData.length, 8);

        // Round-trip a token block through EA07 under the derived key.
        final ea07 = StandardTransferAlgorithm();
        final pt = BitString.fromValue(0xDEADBEEFCAFEBABE, 64);
        final ct = ea07.encrypt(dk, pt);
        final back = ea07.decrypt(dk, ct);
        expect(back.value, pt.value);
      },
    );

    test('throws on vending-key length mismatch', () {
      expect(
        () => DecoderKeyGeneratorAlgorithm04(
          baseDate: BaseDate.date2014,
          tariffIndex: TariffIndex('07'),
          supplyGroupCode: SupplyGroupCode('123456'),
          keyType: KeyType(2),
          keyRevisionNumber: KeyRevisionNumber(1),
          encryptionAlgorithm: StandardTransferAlgorithm(),
          meterPan: MeterPrimaryAccountNumber(
            issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
            individualAccountIdentificationNumber:
                IndividualAccountIdentificationNumber('12345678901'),
          ),
          // Wrong length: 8 bytes instead of 20.
          vendingKey: VendingUniqueDesKey([1, 2, 3, 4, 5, 6, 7, 8]),
        ).generate(),
        throwsA(isA<EncryptionAlgorithmVendingKeyLengthMismatchException>()),
      );
    });
  });
}
