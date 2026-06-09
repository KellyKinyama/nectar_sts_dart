import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

DecoderKey _deriveKey() {
  return DecoderKeyGeneratorAlgorithm02(
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
}

void main() {
  group('TransferElectricityCreditToken round-trip', () {
    test('generate -> 20-digit display -> decode preserves amount + TID', () {
      final decoderKey = _deriveKey();
      final ea07 = StandardTransferAlgorithm();

      final issuedAt = DateTime.utc(2024, 3, 15, 10, 30);
      final tid = TokenIdentifier(BaseDate.date1993, timeOfIssue: issuedAt);
      final amount = Amount(5.5);
      final rnd = RandomNo.fromInt(0xA);

      final token = TransferElectricityCreditToken('req-001')
        ..amountPurchased = amount
        ..tokenIdentifier = tid
        ..randomNo = rnd;

      final generator = TransferElectricityCreditTokenGenerator(
        decoderKey,
        ea07,
      );
      generator.generate(token);

      expect(token.encryptedTokenBitString, isNotNull);
      expect(token.encryptedTokenBitString!.length, 66);
      expect(
        RegExp(r'^[01]{66}$').hasMatch(token.encryptedTokenBitString!),
        isTrue,
      );

      final displayed = token.tokenNo;
      expect(displayed.length, 20);
      expect(RegExp(r'^[0-9]{20}$').hasMatch(displayed), isTrue);

      final decoder = TransferElectricityCreditDecoder(decoderKey, ea07);
      final decoded = decoder.decodeDecimal('req-001-back', displayed);

      expect(decoded.amountPurchased, isNotNull);
      expect(decoded.amountPurchased!.unitsPurchased, closeTo(5.5, 1e-9));
      expect(decoded.tokenIdentifier, isNotNull);
      expect(decoded.tokenIdentifier!.bitString.value, tid.bitString.value);
      expect(decoded.randomNo, isNotNull);
      expect(decoded.randomNo!.bitString.value, 0xA);
      expect(decoded.crc, isNotNull);
      expect(decoded.tokenClass!.bitString.value, 0);
    });

    test('amount 50.0 round-trips exactly', () {
      final decoderKey = _deriveKey();
      final ea07 = StandardTransferAlgorithm();
      final token = TransferElectricityCreditToken('req-002')
        ..amountPurchased = Amount(50.0)
        ..tokenIdentifier = TokenIdentifier(
          BaseDate.date1993,
          timeOfIssue: DateTime.utc(2024, 6, 1, 12, 0),
        )
        ..randomNo = RandomNo.fromInt(5);
      TransferElectricityCreditTokenGenerator(decoderKey, ea07).generate(token);
      final decoded = TransferElectricityCreditDecoder(
        decoderKey,
        ea07,
      ).decodeDecimal('req-002', token.tokenNo);
      expect(decoded.amountPurchased!.unitsPurchased, closeTo(50.0, 1e-9));
    });

    test('tampered token fails CRC / decode', () {
      final decoderKey = _deriveKey();
      final ea07 = StandardTransferAlgorithm();
      final token = TransferElectricityCreditToken('req-003')
        ..amountPurchased = Amount(10.0)
        ..tokenIdentifier = TokenIdentifier(
          BaseDate.date1993,
          timeOfIssue: DateTime.utc(2024, 3, 15, 10, 30),
        )
        ..randomNo = RandomNo.fromInt(3);
      TransferElectricityCreditTokenGenerator(decoderKey, ea07).generate(token);

      final orig = BigInt.parse(token.tokenNo);
      final tampered = (orig + BigInt.one).toString().padLeft(20, '0');
      final decoder = TransferElectricityCreditDecoder(decoderKey, ea07);
      expect(
        () => decoder.decodeDecimal('req-003', tampered),
        throwsA(isA<StsError>()),
      );
    });
  });
}
