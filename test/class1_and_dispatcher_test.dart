import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

DecoderKey _deriveKey() {
  final hsm = VirtualHsm(
    VendingCommonDesKey([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]),
  );
  return hsm.deriveDecoderKeyDkga02(
    keyType: KeyType(2),
    supplyGroupCode: SupplyGroupCode('123456'),
    tariffIndex: TariffIndex('07'),
    keyRevisionNumber: KeyRevisionNumber(1),
    issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
    individualAccountIdentificationNumber:
        IndividualAccountIdentificationNumber('12345678901'),
  );
}

void main() {
  group('Class 1 InitiateMeterTestOrDisplay round-trip', () {
    test('subclass 0 (8-bit mfg + 36-bit control) round-trips', () {
      final decoderKey = _deriveKey();
      final ea07 = StandardTransferAlgorithm();

      final token = InitiateMeterTestOrDisplay1Token('req-100')
        ..manufacturerCode = ManufacturerCode.fromInt(0xA5, widthBits: 8)
        ..control = Control(
          BitString.fromValue(0x123456789, 36),
          ManufacturerCode.fromInt(0xA5, widthBits: 8),
        );

      InitiateMeterTestOrDisplay1TokenGenerator(
        decoderKey,
        ea07,
      ).generate(token);

      expect(token.encryptedTokenBitString, isNotNull);
      expect(token.encryptedTokenBitString!.length, 66);

      final dispatcher = TokenDecoderDispatcher(decoderKey, ea07);
      final result = dispatcher.decodeDecimal('req-100', token.tokenNo);

      expect(result, isA<DecodeAccepted>());
      final decoded = (result as DecodeAccepted).token;
      expect(decoded, isA<InitiateMeterTestOrDisplay1Token>());
      final c1 = decoded as InitiateMeterTestOrDisplay1Token;
      expect(c1.manufacturerCode!.value, 0xA5);
      expect(c1.control!.value, 0x123456789);
      expect(c1.tokenClass!.bitString.value, 1);
      expect(c1.tokenSubClass!.bitString.value, 0);
    });

    test('subclass 1 (16-bit mfg + 28-bit control) round-trips', () {
      final decoderKey = _deriveKey();
      final ea07 = StandardTransferAlgorithm();

      final token = InitiateMeterTestOrDisplay2Token('req-101')
        ..manufacturerCode = ManufacturerCode.fromInt(0xBEEF, widthBits: 16)
        ..control = Control(
          BitString.fromValue(0xABCDEF1, 28),
          ManufacturerCode.fromInt(0xBEEF, widthBits: 16),
        );

      InitiateMeterTestOrDisplay2TokenGenerator(
        decoderKey,
        ea07,
      ).generate(token);

      final dispatcher = TokenDecoderDispatcher(decoderKey, ea07);
      final decoded = dispatcher.decodeOrThrow('req-101', token.tokenNo);
      expect(decoded, isA<InitiateMeterTestOrDisplay2Token>());
      final c2 = decoded as InitiateMeterTestOrDisplay2Token;
      expect(c2.manufacturerCode!.value, 0xBEEF);
      expect(c2.control!.value, 0xABCDEF1);
      expect(c2.tokenSubClass!.bitString.value, 1);
    });
  });

  group('TokenDecoderDispatcher', () {
    test('returns DecodeFailure on garbage input rather than throwing', () {
      final decoderKey = _deriveKey();
      final ea07 = StandardTransferAlgorithm();
      final dispatcher = TokenDecoderDispatcher(decoderKey, ea07);

      final result = dispatcher.decodeDecimal('req-bad', 'not-a-token');
      expect(result, isA<DecodeFailure>());
      expect((result as DecodeFailure).reason, isNotEmpty);
    });

    test('routes Class 0 tokens to TransferElectricityCreditToken', () {
      final decoderKey = _deriveKey();
      final ea07 = StandardTransferAlgorithm();

      final token = TransferElectricityCreditToken('req-class0')
        ..amountPurchased = Amount(25.0)
        ..tokenIdentifier = TokenIdentifier(
          BaseDate.date1993,
          timeOfIssue: DateTime.utc(2024, 6, 1, 12, 0),
        )
        ..randomNo = RandomNo.fromInt(7);
      TransferElectricityCreditTokenGenerator(decoderKey, ea07).generate(token);

      final dispatcher = TokenDecoderDispatcher(decoderKey, ea07);
      final decoded = dispatcher.decodeOrThrow('req-class0', token.tokenNo);
      expect(decoded, isA<TransferElectricityCreditToken>());
      expect(
        (decoded as TransferElectricityCreditToken)
            .amountPurchased!
            .unitsPurchased,
        closeTo(25.0, 1e-9),
      );
    });
  });
}
