import 'dart:typed_data';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

VirtualHsm _hsm() => VirtualHsm(
  VendingCommonDesKey([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]),
);

// DKGA-04 + STA needs a 160-bit (20-byte) vending key. Reuse the
// CTSA24/25/26 test vector key for byte-identical compatibility.
VirtualHsm _hsm04() => VirtualHsm(
  VendingUniqueDesKey(
    Uint8List.fromList([
      0xab,
      0xab,
      0xab,
      0xab,
      0xab,
      0xab,
      0xab,
      0xab,
      0x94,
      0x94,
      0x94,
      0x94,
      0x94,
      0x94,
      0x94,
      0x94,
      0x01,
      0x23,
      0x45,
      0x67,
    ]),
  ),
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
      'Class 0/4 electricity-currency credit round-trips via params API',
      () {
        final hsm = _hsm();
        final params = {
          ..._dkga02Native(),
          VirtualHsmParams.tokenClass: '0',
          VirtualHsmParams.tokenSubclass: '4',
          VirtualHsmParams.amount: 42.0,
          VirtualHsmParams.tokenId: '2024-06-01T12:00:00Z',
          VirtualHsmParams.randomNo: 3,
          VirtualHsmParams.baseDate: '1993',
        };
        final generated = hsm.generateToken('req-A4', params);
        expect(generated, isA<ElectricityCurrencyCreditToken>());
        expect(generated.tokenNo, hasLength(20));
        expect(generated.tokenSubClass?.bitString.value, 4);

        final decoded = hsm.decodeToken(
          'req-A4.decode',
          generated.tokenNo,
          params,
        );
        expect(
          decoded,
          isA<ElectricityCurrencyCreditToken>(),
          reason: 'wire bytes must carry subclass 4',
        );
        final t = decoded as ElectricityCurrencyCreditToken;
        expect(t.tokenSubClass?.bitString.value, 4);
        expect(t.amountPurchased!.unitsPurchased, closeTo(42.0, 1e-9));
        expect(t.randomNo!.bitString.value, 3);
      },
    );

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

  group('VirtualHsm extended coverage', () {
    // Helper: param map for a DKGA-04 + STA derivation matching the
    // CTSA25 vector configuration (20-byte vending key wired via the
    // VirtualHsm constructor's common-key slot is irrelevant for
    // DKGA-04, which receives the full vending key out-of-band — here
    // we use the same Common key for both, since DKGA-04 only reads
    // the meter PAN + (baseDate, ti, sgc, kt, krn) and uses the
    // VirtualHsm's vending-key store at HMAC time).
    Map<String, dynamic> dkga04Native({
      required String baseDate,
      required int krn,
    }) => {
      VirtualHsmParams.decoderKeyGenerationAlgorithm: '04',
      VirtualHsmParams.encryptionAlgorithm: 'sta',
      VirtualHsmParams.keyType: 2,
      VirtualHsmParams.supplyGroupCode: '123457',
      VirtualHsmParams.tariffIndex: '01',
      VirtualHsmParams.keyRevisionNo: krn,
      VirtualHsmParams.issuerIdentificationNo: '600727',
      VirtualHsmParams.decoderReferenceNumber: '00000000000',
      VirtualHsmParams.baseDate: baseDate,
    };

    test('DKGA-04 + STA Class 0 round-trips', () {
      final hsm = _hsm04();
      final params = {
        ...dkga04Native(baseDate: '1993', krn: 1),
        VirtualHsmParams.tokenClass: '0',
        VirtualHsmParams.tokenSubclass: '0',
        VirtualHsmParams.amount: 12.5,
        VirtualHsmParams.tokenId: '2009-01-01T08:00:00Z',
        VirtualHsmParams.randomNo: 5,
      };
      final generated = hsm.generateToken('req-DKGA04', params);
      expect(generated, isA<TransferElectricityCreditToken>());
      final decoded =
          hsm.decodeToken('req-DKGA04.dec', generated.tokenNo, params)
              as TransferElectricityCreditToken;
      expect(decoded.amountPurchased!.unitsPurchased, closeTo(12.5, 1e-9));
    });

    test('DKGA-04 + STA across baseDate sweep (1993/2014/2035)', () {
      final hsm = _hsm04();
      for (final (bd, krn) in [('1993', 1), ('2014', 4), ('2035', 5)]) {
        final params = {
          ...dkga04Native(baseDate: bd, krn: krn),
          VirtualHsmParams.tokenClass: '0',
          VirtualHsmParams.tokenSubclass: '0',
          VirtualHsmParams.amount: 1.0,
          VirtualHsmParams.tokenId: bd == '2035'
              ? '2035-06-01T09:00:00Z'
              : (bd == '2014'
                    ? '2014-06-01T09:00:00Z'
                    : '2008-06-01T09:00:00Z'),
        };
        final t = hsm.generateToken('req-bd-$bd', params);
        final d =
            hsm.decodeToken('req-bd-$bd.dec', t.tokenNo, params)
                as TransferElectricityCreditToken;
        expect(d.amountPurchased!.unitsPurchased, closeTo(1.0, 1e-9));
      }
    });

    Map<String, dynamic> dkga02Native() => {
      VirtualHsmParams.decoderKeyGenerationAlgorithm: '02',
      VirtualHsmParams.encryptionAlgorithm: 'sta',
      VirtualHsmParams.keyType: 2,
      VirtualHsmParams.supplyGroupCode: '123456',
      VirtualHsmParams.tariffIndex: '01',
      VirtualHsmParams.keyRevisionNo: 1,
      VirtualHsmParams.issuerIdentificationNo: '600727',
      VirtualHsmParams.decoderReferenceNumber: '00000000000',
      VirtualHsmParams.baseDate: '1993',
      VirtualHsmParams.tokenId: '2024-06-01T12:00:00Z',
      VirtualHsmParams.randomNo: 5,
    };

    test('Class 2/0 SetMaximumPowerLimit round-trips', () {
      final hsm = _hsm();
      final params = {
        ...dkga02Native(),
        VirtualHsmParams.tokenClass: '2',
        VirtualHsmParams.tokenSubclass: '0',
        VirtualHsmParams.maximumPowerLimit: 16384,
      };
      final generated = hsm.generateToken('mpl', params);
      expect(generated, isA<SetMaximumPowerLimitToken>());
      final decoded =
          hsm.decodeToken('mpl.dec', generated.tokenNo, params)
              as SetMaximumPowerLimitToken;
      expect(decoded.maximumPowerLimit!.value, 16384);
    });

    test('Class 2/1 ClearCredit round-trips', () {
      final hsm = _hsm();
      final params = {
        ...dkga02Native(),
        VirtualHsmParams.tokenClass: '2',
        VirtualHsmParams.tokenSubclass: '1',
        VirtualHsmParams.register: 0xFFFF,
      };
      final generated = hsm.generateToken('cc', params);
      expect(generated, isA<ClearCreditToken>());
      final decoded =
          hsm.decodeToken('cc.dec', generated.tokenNo, params)
              as ClearCreditToken;
      expect(decoded.register!.bitString.value, 0xFFFF);
    });

    test('Class 2/2 SetTariffRate round-trips', () {
      final hsm = _hsm();
      final params = {
        ...dkga02Native(),
        VirtualHsmParams.tokenClass: '2',
        VirtualHsmParams.tokenSubclass: '2',
        VirtualHsmParams.tariffRate: 12345,
      };
      final generated = hsm.generateToken('tr', params);
      expect(generated, isA<SetTariffRateToken>());
      final decoded =
          hsm.decodeToken('tr.dec', generated.tokenNo, params)
              as SetTariffRateToken;
      expect(decoded.rate!.value, 12345);
    });

    test('Class 2/5 ClearTamperCondition round-trips', () {
      final hsm = _hsm();
      final params = {
        ...dkga02Native(),
        VirtualHsmParams.tokenClass: '2',
        VirtualHsmParams.tokenSubclass: '5',
        VirtualHsmParams.pad: 0x1234,
      };
      final generated = hsm.generateToken('ctc', params);
      expect(generated, isA<ClearTamperConditionToken>());
      final decoded =
          hsm.decodeToken('ctc.dec', generated.tokenNo, params)
              as ClearTamperConditionToken;
      expect(decoded.pad!.bitString.value, 0x1234);
    });

    test('Class 2/6 SetMaximumPhasePowerUnbalanceLimit round-trips', () {
      final hsm = _hsm();
      // STS exponent/mantissa encoding is non-lossy only for small
      // integers in the mantissa range; the `value` getter returns
      // the raw 16-bit bitstring (not the decoded scalar), so we
      // compare bitstrings to verify the round-trip.
      final mppul = MaximumPhasePowerUnbalanceLimit(20000);
      final params = {
        ...dkga02Native(),
        VirtualHsmParams.tokenClass: '2',
        VirtualHsmParams.tokenSubclass: '6',
        VirtualHsmParams.maximumPhasePowerUnbalanceLimit: 20000,
      };
      final generated = hsm.generateToken('mppul', params);
      expect(generated, isA<SetMaximumPhasePowerUnbalanceLimitToken>());
      final decoded =
          hsm.decodeToken('mppul.dec', generated.tokenNo, params)
              as SetMaximumPhasePowerUnbalanceLimitToken;
      expect(
        decoded.maximumPhasePowerUnbalanceLimit!.bitString.value,
        equals(mppul.bitString.value),
      );
    });

    test('Class 2/3 + 2/4 KCT pair generate (Set1st + Set2nd)', () {
      final hsm = _hsm();
      // New 64-bit decoder key hex.
      const newKeyHex = 'fedcba9876543210';
      final p1 = {
        ...dkga02Native(),
        VirtualHsmParams.tokenClass: '2',
        VirtualHsmParams.tokenSubclass: '3',
        VirtualHsmParams.newDecoderKey: newKeyHex,
        VirtualHsmParams.keyExpiryNumberHighOrder: 0xF,
        VirtualHsmParams.newKeyRevisionNumber: 2,
        VirtualHsmParams.rollOverKeyChange: 0,
        VirtualHsmParams.newKeyType: 2,
      };
      final tok1 = hsm.generateToken('kct1', p1);
      expect(tok1, isA<Set1stSectionDecoderKeyToken>());
      expect(tok1.tokenNo, hasLength(20));

      final p2 = {
        ...dkga02Native(),
        VirtualHsmParams.tokenClass: '2',
        VirtualHsmParams.tokenSubclass: '4',
        VirtualHsmParams.newDecoderKey: newKeyHex,
        VirtualHsmParams.keyExpiryNumberLowOrder: 0xF,
        VirtualHsmParams.newTariffIndex: '02',
      };
      final tok2 = hsm.generateToken('kct2', p2);
      expect(tok2, isA<Set2ndSectionDecoderKeyToken>());
      expect(tok2.tokenNo, hasLength(20));
    });

    test('Class 0/1 (water) issues a TransferWaterCreditToken', () {
      final hsm = _hsm();
      final tok = hsm.generateToken('w', {
        ...dkga02Native(),
        VirtualHsmParams.tokenClass: '0',
        VirtualHsmParams.tokenSubclass: '1',
        VirtualHsmParams.amount: 1.0,
      });
      expect(tok, isA<TransferWaterCreditToken>());
      expect(tok.tokenNo, hasLength(20));
    });

    test('Class 0/2 (gas) issues a TransferGasCreditToken', () {
      final hsm = _hsm();
      final tok = hsm.generateToken('g', {
        ...dkga02Native(),
        VirtualHsmParams.tokenClass: '0',
        VirtualHsmParams.tokenSubclass: '2',
        VirtualHsmParams.amount: 1.0,
      });
      expect(tok, isA<TransferGasCreditToken>());
      expect(tok.tokenNo, hasLength(20));
    });

    test('unknown class/subclass is rejected with InvalidTokenException', () {
      final hsm = _hsm();
      expect(
        () => hsm.generateToken('x', {
          ...dkga02Native(),
          VirtualHsmParams.tokenClass: '9',
          VirtualHsmParams.tokenSubclass: '9',
        }),
        throwsA(isA<InvalidTokenException>()),
      );
    });

    test('unknown base_date is rejected', () {
      final hsm = _hsm();
      expect(
        () => hsm.generateToken('bad-bd', {
          ...dkga02Native(),
          VirtualHsmParams.baseDate: '1980',
          VirtualHsmParams.tokenClass: '0',
          VirtualHsmParams.tokenSubclass: '0',
          VirtualHsmParams.amount: 1.0,
        }),
        throwsA(isA<InvalidBaseDateException>()),
      );
    });

    test('missing required param raises InvalidTokenException', () {
      final hsm = _hsm();
      expect(
        () => hsm.generateToken(
          'miss',
          {
            ...dkga02Native(),
            VirtualHsmParams.tokenClass: '0',
            VirtualHsmParams.tokenSubclass: '0',
            // intentionally omit amount + tokenId
          }..remove(VirtualHsmParams.tokenId),
        ),
        throwsA(isA<InvalidTokenException>()),
      );
    });

    test('decode reads back tokenIdentifier minute granularity', () {
      final hsm = _hsm();
      final issuedAt = DateTime.utc(2024, 6, 1, 12, 34, 0);
      final params = {
        ...dkga02Native(),
        VirtualHsmParams.tokenClass: '0',
        VirtualHsmParams.tokenSubclass: '0',
        VirtualHsmParams.amount: 50.0,
        VirtualHsmParams.tokenId: issuedAt.toIso8601String(),
      };
      final t = hsm.generateToken('tid', params);
      final d =
          hsm.decodeToken('tid.dec', t.tokenNo, params)
              as TransferElectricityCreditToken;
      // STS encodes minute precision; seconds get truncated.
      expect(d.tokenIdentifier!.timeOfIssue.year, 2024);
      expect(d.tokenIdentifier!.timeOfIssue.month, 6);
      expect(d.tokenIdentifier!.timeOfIssue.day, 1);
      expect(d.tokenIdentifier!.timeOfIssue.hour, 12);
      expect(d.tokenIdentifier!.timeOfIssue.minute, 34);
    });
  });
}
