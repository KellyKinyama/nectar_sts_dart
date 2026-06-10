import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

VirtualHsm _hsm() => VirtualHsm(
  VendingCommonDesKey([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]),
);

Map<String, dynamic> _dkga02Native() => {
  VirtualHsmParams.decoderKeyGenerationAlgorithm: '02',
  VirtualHsmParams.encryptionAlgorithm: 'sta',
  VirtualHsmParams.keyType: 2,
  VirtualHsmParams.supplyGroupCode: '123456',
  VirtualHsmParams.tariffIndex: '07',
  VirtualHsmParams.keyRevisionNo: 1,
  VirtualHsmParams.issuerIdentificationNo: '600727',
  VirtualHsmParams.decoderReferenceNumber: '12345678901',
};

void main() {
  group('VirtualHsm params dispatch', () {
    test('Class 0/0 electricity credit round-trips via params API', () {
      final hsm = _hsm();
      final params = {
        ..._dkga02Native(),
        VirtualHsmParams.tokenClass: '0',
        VirtualHsmParams.tokenSubclass: '0',
        VirtualHsmParams.amount: 25.5,
        VirtualHsmParams.tokenId: '2024-06-01T12:00:00Z',
        VirtualHsmParams.randomNo: 7,
        VirtualHsmParams.baseDate: '1993',
      };
      final generated = hsm.generateToken('req-A1', params);
      expect(generated, isA<TransferElectricityCreditToken>());
      expect(generated.tokenNo, hasLength(20));

      final decoded = hsm.decodeToken(
        'req-A1.decode',
        generated.tokenNo,
        params,
      );
      expect(decoded, isA<TransferElectricityCreditToken>());
      final t = decoded as TransferElectricityCreditToken;
      expect(t.amountPurchased!.unitsPurchased, closeTo(25.5, 1e-9));
      expect(t.randomNo!.bitString.value, 7);
    });

    test(
      'Class 1/0 InitiateMeterTestOrDisplay1 round-trips via params API',
      () {
        final hsm = _hsm();
        final params = {
          ..._dkga02Native(),
          VirtualHsmParams.tokenClass: '1',
          VirtualHsmParams.tokenSubclass: '0',
          VirtualHsmParams.manufacturerCode: 0xA5,
          VirtualHsmParams.control: 0x123456789,
        };
        final generated = hsm.generateToken('req-B1', params);
        expect(generated, isA<InitiateMeterTestOrDisplay1Token>());
        final decoded =
            hsm.decodeToken('req-B1.dec', generated.tokenNo, params)
                as InitiateMeterTestOrDisplay1Token;
        expect(decoded.manufacturerCode!.value, 0xA5);
        expect(decoded.control!.value, 0x123456789);
      },
    );

    test(
      'Class 1/1 InitiateMeterTestOrDisplay2 round-trips via params API',
      () {
        final hsm = _hsm();
        final params = {
          ..._dkga02Native(),
          VirtualHsmParams.tokenClass: '1',
          VirtualHsmParams.tokenSubclass: '1',
          VirtualHsmParams.manufacturerCode: 0xBEEF,
          VirtualHsmParams.control: 0xABCDEF1,
        };
        final generated = hsm.generateToken('req-C1', params);
        final decoded =
            hsm.decodeToken('req-C1.dec', generated.tokenNo, params)
                as InitiateMeterTestOrDisplay2Token;
        expect(decoded.manufacturerCode!.value, 0xBEEF);
        expect(decoded.control!.value, 0xABCDEF1);
      },
    );

    test('string-typed param values are accepted (mirrors JSON body)', () {
      final hsm = _hsm();
      final params = <String, dynamic>{
        VirtualHsmParams.decoderKeyGenerationAlgorithm: '02',
        VirtualHsmParams.encryptionAlgorithm: 'sta',
        VirtualHsmParams.keyType: '2',
        VirtualHsmParams.supplyGroupCode: '123456',
        VirtualHsmParams.tariffIndex: '07',
        VirtualHsmParams.keyRevisionNo: '1',
        VirtualHsmParams.issuerIdentificationNo: '600727',
        VirtualHsmParams.decoderReferenceNumber: '12345678901',
        VirtualHsmParams.tokenClass: '0',
        VirtualHsmParams.tokenSubclass: '0',
        VirtualHsmParams.amount: '10.0',
        VirtualHsmParams.tokenId: '2024-06-01T12:00:00Z',
      };
      final generated = hsm.generateToken('req-D', params);
      final decoded =
          hsm.decodeToken('req-D.dec', generated.tokenNo, params)
              as TransferElectricityCreditToken;
      expect(decoded.amountPurchased!.unitsPurchased, closeTo(10.0, 1e-9));
    });

    test('type=prism-thrift is rejected', () {
      final hsm = _hsm();
      expect(
        () => hsm.generateToken('r', {
          ..._dkga02Native(),
          VirtualHsmParams.type: 'prism-thrift',
          VirtualHsmParams.tokenClass: '0',
          VirtualHsmParams.tokenSubclass: '0',
          VirtualHsmParams.amount: 1.0,
          VirtualHsmParams.tokenId: '2024-06-01T12:00:00Z',
        }),
        throwsA(isA<NotImplementedException>()),
      );
    });

    test('DKGA-01 / DKGA-03 are rejected as not-ported', () {
      final hsm = _hsm();
      for (final dkga in ['01', '03']) {
        expect(
          () => hsm.generateToken('r', {
            ..._dkga02Native(),
            VirtualHsmParams.decoderKeyGenerationAlgorithm: dkga,
            VirtualHsmParams.tokenClass: '0',
            VirtualHsmParams.tokenSubclass: '0',
            VirtualHsmParams.amount: 1.0,
            VirtualHsmParams.tokenId: '2024-06-01T12:00:00Z',
          }),
          throwsA(isA<NotImplementedException>()),
          reason: 'DKGA-$dkga should not be implemented',
        );
      }
    });

    test(
      'Class 2 subclass 7 (water meter factor) is rejected as not-ported',
      () {
        final hsm = _hsm();
        expect(
          () => hsm.generateToken('r', {
            ..._dkga02Native(),
            VirtualHsmParams.tokenClass: '2',
            VirtualHsmParams.tokenSubclass: '7',
          }),
          throwsA(isA<NotImplementedException>()),
        );
      },
    );

    test('MISTY1 encryption_algorithm needs a 16-byte decoder key '
        '(DKGA-02 derives only 8 bytes)', () {
      final hsm = _hsm();
      expect(
        () => hsm.generateToken('r', {
          ..._dkga02Native(),
          VirtualHsmParams.encryptionAlgorithm: 'misty1',
          VirtualHsmParams.tokenClass: '0',
          VirtualHsmParams.tokenSubclass: '0',
          VirtualHsmParams.amount: 1.0,
          VirtualHsmParams.tokenId: '2024-06-01T12:00:00Z',
        }),
        throwsA(isA<InvalidKeyDataException>()),
      );
    });

    test('parseHexKey helper round-trips common cases', () {
      expect(parseHexKey('0123456789ABCDEF'), [
        0x01,
        0x23,
        0x45,
        0x67,
        0x89,
        0xAB,
        0xCD,
        0xEF,
      ]);
      expect(parseHexKey('0x00ff'), [0x00, 0xFF]);
      expect(() => parseHexKey('abc'), throwsA(isA<InvalidTokenException>()));
    });
  });
}
