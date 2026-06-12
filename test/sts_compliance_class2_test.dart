// STS compliance test vectors ported from NectarAPI/tokens-service:
//   src/test/java/ke/co/nectar/token/domain/token/
//     STSComplianceTests_STS_531_1_0_02_CTSA0{1,3,4,5,6,7,9,12,13,14}.java
//     STSComplianceTests_STS_531_1_0_02_CTSA25.java
//     STSComplianceTests_Nectar_1.java (vendor extension Amount sweep)
//
// SCOPE:
//   - STA (EA07) Class 0 TransferElectricityCredit and Class 2
//     management tokens / Key Change Tokens (1st/2nd section).
//   - DKGA-02 derived key for CTSA01/03/04/05/06/07/09/12/13/14 and
//     Nectar_1.
//   - DKGA-04 derived key for CTSA25 (DKGA-04 + STA combo: 20-byte
//     vending key, SGC='123457', baseDate sweep 1993/2014/2035).
//
//   - Standard DKGA-02 CTSA setup: vudk=hex 'abababababababab',
//     SGC='123456', TI='01', KRN=1, KT=2, KEN=255,
//     PAN='600727000000000009' unless noted.
//
//   - Skipped vectors are documented inline:
//       * CTSA01/CTSA25 water/gas steps: electricity-only port.
//       * CTSA09 step3 multi-minute series: relies on a vending-side
//         TID rolling counter that the Dart port leaves to callers.
//         The three time-shifted re-issues are exercised as
//         independent vectors instead.
//
//   - The `KeyExpiryNumber` argument that the Java generators take is
//     not present in the Dart port. See `sts_compliance_test.dart`
//     header — KEN is not mixed into the Class 2 data block.
//
// Class 1 vectors (CTSA02, CTSA11) are exercised in
// `class1_and_dispatcher_test.dart` and `sts_compliance_class1_test.dart`.
import 'dart:typed_data';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) {
  if (s.length.isOdd) throw ArgumentError('odd-length hex: $s');
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

DecoderKey _dkga02({
  required KeyType keyType,
  required SupplyGroupCode sgc,
  required TariffIndex ti,
  required KeyRevisionNumber krn,
  required String iinStr,
  required String iainStr,
  required VendingUniqueDesKey vudk,
}) => DecoderKeyGeneratorAlgorithm02(
  keyType: keyType,
  supplyGroupCode: sgc,
  tariffIndex: ti,
  keyRevisionNumber: krn,
  issuerIdentificationNumber: IssuerIdentificationNumber(iinStr),
  individualAccountIdentificationNumber: IndividualAccountIdentificationNumber(
    iainStr,
  ),
  vendingKey: vudk,
).generate();

TokenIdentifier _tid(DateTime issuedAt) =>
    TokenIdentifier(BaseDate.date1993, timeOfIssue: issuedAt);

RandomNo get _rnd5 => RandomNo.fromInt(0x5);

void main() {
  // Shared CTSA setup matching the upstream @Before blocks.
  final keyType = KeyType(2);
  final sgc = SupplyGroupCode('123456');
  final ti = TariffIndex('01');
  final krn = KeyRevisionNumber(1);
  final vudk = VendingUniqueDesKey(_hex('abababababababab'));
  final ea07 = StandardTransferAlgorithm();

  // PAN 600727000000000009 → IIN=600727, IAIN=00000000000.
  DecoderKey defaultDecoderKey() => _dkga02(
    keyType: keyType,
    sgc: sgc,
    ti: ti,
    krn: krn,
    iinStr: '600727',
    iainStr: '00000000000',
    vudk: vudk,
  );

  group('STS_531_1_0_02 CTSA03 (SetMaximumPowerLimit)', () {
    test('step1: 28/03/2004 09:01:00, MPL=1000 → 50901894209860263092', () {
      final dk = defaultDecoderKey();
      final token = SetMaximumPowerLimitTokenGenerator(dk, ea07).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(DateTime.utc(2004, 3, 28, 9, 1, 0)),
        maximumPowerLimit: MaximumPowerLimit(1000),
      );
      SetMaximumPowerLimitTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('50901894209860263092'));
    });
  });

  group('STS_531_1_0_02 CTSA04 (ClearCredit)', () {
    test(
      'step1: 28/03/2004 09:15:00, register=0xFFFF → 29511990995826640868',
      () {
        final dk = defaultDecoderKey();
        final token = ClearCreditTokenGenerator(dk, ea07).buildToken(
          'request_id',
          randomNo: _rnd5,
          tokenIdentifier: _tid(DateTime.utc(2004, 3, 28, 9, 15, 0)),
          register: Register(BitString.fromValue(0xFFFF, 16)),
        );
        ClearCreditTokenGenerator(dk, ea07).generate(token);
        expect(token.tokenNo, equals('29511990995826640868'));
      },
    );

    test('step2: PAN 000001000000000082, 28/03/2004 09:20:00 → '
        '69986678528351463847', () {
      final dk = _dkga02(
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: krn,
        iinStr: '000001',
        iainStr: '00000000008',
        vudk: vudk,
      );
      final token = ClearCreditTokenGenerator(dk, ea07).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(DateTime.utc(2004, 3, 28, 9, 20, 0)),
        register: Register(BitString.fromValue(0xFFFF, 16)),
      );
      ClearCreditTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('69986678528351463847'));
    });
  });

  group('STS_531_1_0_02 CTSA05 (Set1st/2nd Section Decoder Key)', () {
    // The Java upstream changes only the TariffIndex between
    // initial/new decoder keys (initial TI=01, new TI=02). KEN stays
    // 255 for both; KENHO=0xF, KENLO=0xF; RO=0; KRN(new)=1.

    DecoderKey initialKeyFor(
      String tariff, {
      String iin = '600727',
      String iain = '00000000000',
    }) => _dkga02(
      keyType: keyType,
      sgc: sgc,
      ti: TariffIndex(tariff),
      krn: krn,
      iinStr: iin,
      iainStr: iain,
      vudk: vudk,
    );

    test(
      'step1 1st section: initialTI=01 → newTI=02 → 51638423060042734509',
      () {
        final initialKey = initialKeyFor('01');
        final newKey = initialKeyFor('02');
        final tok = Set1stSectionDecoderKeyTokenGenerator(
          decoderKey: initialKey,
          encryptionAlgorithm: ea07,
          keyExpiryNumberHighOrder: KeyExpiryNumberHighOrder(
            BitString.fromValue(0xF, 4),
          ),
          keyRevisionNumber: krn,
          rolloverKeyChange: RolloverKeyChange.fromBool(false),
          keyType: keyType,
          newDecoderKey: newKey,
        ).generateNew('request_id');
        expect(tok.tokenNo, equals('51638423060042734509'));
      },
    );

    test('step1 2nd section: newTI=02, KENLO=0xF → 15361891762113502242', () {
      final initialKey = initialKeyFor('01');
      final newKey = initialKeyFor('02');
      final tok = Set2ndSectionDecoderKeyTokenGenerator(
        decoderKey: initialKey,
        encryptionAlgorithm: ea07,
        keyExpiryNumberLowOrder: KeyExpiryNumberLowOrder(
          BitString.fromValue(0xF, 4),
        ),
        tariffIndex: TariffIndex('02'),
        newDecoderKey: newKey,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('15361891762113502242'));
    });

    test(
      'step2 1st section: initialTI=02 → newTI=01 → 26553210520543055412',
      () {
        // "flipped" — initial generator now uses newTariffIndex=02, new
        // generator uses initialTariffIndex=01.
        final initialKey = initialKeyFor('02');
        final newKey = initialKeyFor('01');
        final tok = Set1stSectionDecoderKeyTokenGenerator(
          decoderKey: initialKey,
          encryptionAlgorithm: ea07,
          keyExpiryNumberHighOrder: KeyExpiryNumberHighOrder(
            BitString.fromValue(0xF, 4),
          ),
          keyRevisionNumber: krn,
          rolloverKeyChange: RolloverKeyChange.fromBool(false),
          keyType: keyType,
          newDecoderKey: newKey,
        ).generateNew('request_id');
        expect(tok.tokenNo, equals('26553210520543055412'));
      },
    );

    test('step2 2nd section: flipped, newTariffIndex=01 → '
        '00943705441908264439', () {
      final initialKey = initialKeyFor('02');
      final newKey = initialKeyFor('01');
      final tok = Set2ndSectionDecoderKeyTokenGenerator(
        decoderKey: initialKey,
        encryptionAlgorithm: ea07,
        keyExpiryNumberLowOrder: KeyExpiryNumberLowOrder(
          BitString.fromValue(0xF, 4),
        ),
        tariffIndex: TariffIndex('01'),
        newDecoderKey: newKey,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('00943705441908264439'));
    });

    test(
      'step3 1st section: PAN=000001000000000082 → 36495265416911568628',
      () {
        final initialKey = initialKeyFor(
          '01',
          iin: '000001',
          iain: '00000000008',
        );
        final newKey = initialKeyFor('02', iin: '000001', iain: '00000000008');
        final tok = Set1stSectionDecoderKeyTokenGenerator(
          decoderKey: initialKey,
          encryptionAlgorithm: ea07,
          keyExpiryNumberHighOrder: KeyExpiryNumberHighOrder(
            BitString.fromValue(0xF, 4),
          ),
          keyRevisionNumber: krn,
          rolloverKeyChange: RolloverKeyChange.fromBool(false),
          keyType: keyType,
          newDecoderKey: newKey,
        ).generateNew('request_id');
        expect(tok.tokenNo, equals('36495265416911568628'));
      },
    );

    test(
      'step3 2nd section: PAN=000001000000000082 → 35908059266238070883',
      () {
        final initialKey = initialKeyFor(
          '01',
          iin: '000001',
          iain: '00000000008',
        );
        final newKey = initialKeyFor('02', iin: '000001', iain: '00000000008');
        final tok = Set2ndSectionDecoderKeyTokenGenerator(
          decoderKey: initialKey,
          encryptionAlgorithm: ea07,
          keyExpiryNumberLowOrder: KeyExpiryNumberLowOrder(
            BitString.fromValue(0xF, 4),
          ),
          tariffIndex: TariffIndex('02'),
          newDecoderKey: newKey,
        ).generateNew('request_id');
        expect(tok.tokenNo, equals('35908059266238070883'));
      },
    );
  });

  group('STS_531_1_0_02 CTSA06 (ClearTamperCondition)', () {
    test('step1: 28/03/2004 10:00:00, pad=0 → 37037300014464855694', () {
      final dk = defaultDecoderKey();
      final token = ClearTamperConditionTokenGenerator(dk, ea07).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(DateTime.utc(2004, 3, 28, 10, 0, 0)),
        pad: Pad(BitString.fromValue(0, 16)),
      );
      ClearTamperConditionTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('37037300014464855694'));
    });
  });

  group('STS_531_1_0_02 CTSA07 (SetMaximumPhasePowerUnbalanceLimit)', () {
    test('step1: 28/03/2004 10:20:00, MPPUL=10 → 30220533115430798647', () {
      final dk = defaultDecoderKey();
      final token = SetMaximumPhasePowerUnbalanceLimitTokenGenerator(dk, ea07)
          .buildToken(
            'request_id',
            randomNo: _rnd5,
            tokenIdentifier: _tid(DateTime.utc(2004, 3, 28, 10, 20, 0)),
            maximumPhasePowerUnbalanceLimit: MaximumPhasePowerUnbalanceLimit(
              10,
            ),
          );
      SetMaximumPhasePowerUnbalanceLimitTokenGenerator(
        dk,
        ea07,
      ).generate(token);
      expect(token.tokenNo, equals('30220533115430798647'));
    });
  });

  group('STS_531_1_0_02 CTSA09 (ClearCredit)', () {
    test('step1: 29/03/2004 00:00:00 → 10208942296089183521', () {
      final dk = defaultDecoderKey();
      final token = ClearCreditTokenGenerator(dk, ea07).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(DateTime.utc(2004, 3, 29, 0, 0, 0)),
        register: Register(BitString.fromValue(0xFFFF, 16)),
      );
      ClearCreditTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('10208942296089183521'));
    });

    test('step2: 29/03/2004 00:01:00 → 20388873191656671689', () {
      final dk = defaultDecoderKey();
      final token = ClearCreditTokenGenerator(dk, ea07).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(DateTime.utc(2004, 3, 29, 0, 1, 0)),
        register: Register(BitString.fromValue(0xFFFF, 16)),
      );
      ClearCreditTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('20388873191656671689'));
    });

    test('step3 single token: 29/03/2004 00:03:00 → 43348834939937913498', () {
      final dk = defaultDecoderKey();
      final token = ClearCreditTokenGenerator(dk, ea07).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(DateTime.utc(2004, 3, 29, 0, 3, 0)),
        register: Register(BitString.fromValue(0xFFFF, 16)),
      );
      ClearCreditTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('43348834939937913498'));
    });

    test('step3 second-minute simulation: 29/03/2004 00:04:00 → '
        '51681104150374451564', () {
      final dk = defaultDecoderKey();
      final token = ClearCreditTokenGenerator(dk, ea07).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(DateTime.utc(2004, 3, 29, 0, 4, 0)),
        register: Register(BitString.fromValue(0xFFFF, 16)),
      );
      ClearCreditTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('51681104150374451564'));
    });

    test('step3 third-minute simulation: 29/03/2004 00:05:00 → '
        '50526247723864280405', () {
      final dk = defaultDecoderKey();
      final token = ClearCreditTokenGenerator(dk, ea07).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(DateTime.utc(2004, 3, 29, 0, 5, 0)),
        register: Register(BitString.fromValue(0xFFFF, 16)),
      );
      ClearCreditTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('50526247723864280405'));
    });
  });

  group('STS_531_1_0_02 CTSA12 (SetMaximumPowerLimit)', () {
    DecoderKey dk() => defaultDecoderKey();

    String genMpl(DateTime issuedAt, int mpl) {
      final token = SetMaximumPowerLimitTokenGenerator(dk(), ea07).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(issuedAt),
        maximumPowerLimit: MaximumPowerLimit(mpl),
      );
      SetMaximumPowerLimitTokenGenerator(dk(), ea07).generate(token);
      return token.tokenNo;
    }

    test('step1: 01/04/2004 07:00:00, MPL=256 → 41932934023937597177', () {
      expect(
        genMpl(DateTime.utc(2004, 4, 1, 7, 0, 0), 256),
        equals('41932934023937597177'),
      );
    });
    test('step2: 01/04/2004 07:05:00, MPL=16383 → 39962525051716972228', () {
      expect(
        genMpl(DateTime.utc(2004, 4, 1, 7, 5, 0), 16383),
        equals('39962525051716972228'),
      );
    });
    test('step3: 01/04/2004 07:10:00, MPL=16384 → 49726922948713857933', () {
      expect(
        genMpl(DateTime.utc(2004, 4, 1, 7, 10, 0), 16384),
        equals('49726922948713857933'),
      );
    });
    test('step4: 01/04/2004 07:15:00, MPL=20000 → 49240429350369491663', () {
      expect(
        genMpl(DateTime.utc(2004, 4, 1, 7, 15, 0), 20000),
        equals('49240429350369491663'),
      );
    });
    test('step5: 01/04/2004 07:20:00, MPL=180223 → 59901462710025767433', () {
      expect(
        genMpl(DateTime.utc(2004, 4, 1, 7, 20, 0), 180223),
        equals('59901462710025767433'),
      );
    });
    test('step6: 01/04/2004 07:25:00, MPL=180224 → 19230023168014606006', () {
      expect(
        genMpl(DateTime.utc(2004, 4, 1, 7, 25, 0), 180224),
        equals('19230023168014606006'),
      );
    });
    test('step7: 01/04/2004 07:30:00, MPL=1818623 → 15202793104399278539', () {
      expect(
        genMpl(DateTime.utc(2004, 4, 1, 7, 30, 0), 1818623),
        equals('15202793104399278539'),
      );
    });
    test('step8: 01/04/2004 07:35:00, MPL=1818624 → 39289527337368539951', () {
      expect(
        genMpl(DateTime.utc(2004, 4, 1, 7, 35, 0), 1818624),
        equals('39289527337368539951'),
      );
    });
    test('step9: 01/04/2004 07:40:00, MPL=18201624 → 64902502692705103624', () {
      expect(
        genMpl(DateTime.utc(2004, 4, 1, 7, 40, 0), 18201624),
        equals('64902502692705103624'),
      );
    });
  });

  group('STS_531_1_0_02 CTSA13 (SetMaximumPhasePowerUnbalanceLimit)', () {
    DecoderKey dk() => defaultDecoderKey();

    String genMppul(DateTime issuedAt, int v) {
      final token = SetMaximumPhasePowerUnbalanceLimitTokenGenerator(dk(), ea07)
          .buildToken(
            'request_id',
            randomNo: _rnd5,
            tokenIdentifier: _tid(issuedAt),
            maximumPhasePowerUnbalanceLimit: MaximumPhasePowerUnbalanceLimit(v),
          );
      SetMaximumPhasePowerUnbalanceLimitTokenGenerator(
        dk(),
        ea07,
      ).generate(token);
      return token.tokenNo;
    }

    test('step1: 01/04/2004 08:00:00, MPPUL=256 → 31529222328157245680', () {
      expect(
        genMppul(DateTime.utc(2004, 4, 1, 8, 0, 0), 256),
        equals('31529222328157245680'),
      );
    });
    test('step2: 01/04/2004 08:05:00, MPPUL=16383 → 73693330413053816261', () {
      expect(
        genMppul(DateTime.utc(2004, 4, 1, 8, 5, 0), 16383),
        equals('73693330413053816261'),
      );
    });
    test('step3: 01/04/2004 08:10:00, MPPUL=16384 → 54550534704168942701', () {
      expect(
        genMppul(DateTime.utc(2004, 4, 1, 8, 10, 0), 16384),
        equals('54550534704168942701'),
      );
    });
    test('step4: 01/04/2004 08:15:00, MPPUL=20000 → 59764600311380323340', () {
      expect(
        genMppul(DateTime.utc(2004, 4, 1, 8, 15, 0), 20000),
        equals('59764600311380323340'),
      );
    });
    test('step5: 01/04/2004 08:20:00, MPPUL=180223 → 40345762458084906193', () {
      expect(
        genMppul(DateTime.utc(2004, 4, 1, 8, 20, 0), 180223),
        equals('40345762458084906193'),
      );
    });
    test('step6: 01/04/2004 08:25:00, MPPUL=180224 → 66940669945224810632', () {
      expect(
        genMppul(DateTime.utc(2004, 4, 1, 8, 25, 0), 180224),
        equals('66940669945224810632'),
      );
    });
    test(
      'step7: 01/04/2004 08:30:00, MPPUL=1818623 → 39456295247583474882',
      () {
        expect(
          genMppul(DateTime.utc(2004, 4, 1, 8, 30, 0), 1818623),
          equals('39456295247583474882'),
        );
      },
    );
    test(
      'step8: 01/04/2004 08:35:00, MPPUL=1818624 → 71498975780521030688',
      () {
        expect(
          genMppul(DateTime.utc(2004, 4, 1, 8, 35, 0), 1818624),
          equals('71498975780521030688'),
        );
      },
    );
    test(
      'step9: 01/04/2004 08:40:00, MPPUL=18201624 → 57078032150370797843',
      () {
        expect(
          genMppul(DateTime.utc(2004, 4, 1, 8, 40, 0), 18201624),
          equals('57078032150370797843'),
        );
      },
    );
  });

  group('STS_531_1_0_02 CTSA14 (ClearCredit register values)', () {
    DecoderKey dk() => defaultDecoderKey();

    String genCc(DateTime issuedAt, int reg) {
      final token = ClearCreditTokenGenerator(dk(), ea07).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(issuedAt),
        register: Register(BitString.fromValue(reg, 16)),
      );
      ClearCreditTokenGenerator(dk(), ea07).generate(token);
      return token.tokenNo;
    }

    test('step1: 01/04/2004 09:00:00, reg=0x0000 → 24406351748405762287', () {
      expect(
        genCc(DateTime.utc(2004, 4, 1, 9, 0, 0), 0x0000),
        equals('24406351748405762287'),
      );
    });
    test('step2: 01/04/2004 09:05:00, reg=0xFFFF → 48263195037886996694', () {
      expect(
        genCc(DateTime.utc(2004, 4, 1, 9, 5, 0), 0xFFFF),
        equals('48263195037886996694'),
      );
    });
    test('step3: 01/04/2004 09:10:00, reg=0x0004 → 17696673116286267663', () {
      expect(
        genCc(DateTime.utc(2004, 4, 1, 9, 10, 0), 0x0004),
        equals('17696673116286267663'),
      );
    });
    test('step4: 01/04/2004 09:15:00, reg=0x0005 → 47739859634763202644', () {
      expect(
        genCc(DateTime.utc(2004, 4, 1, 9, 15, 0), 0x0005),
        equals('47739859634763202644'),
      );
    });
    test('step5: 01/04/2004 09:20:00, reg=0x0006 → 23456948011089526127', () {
      expect(
        genCc(DateTime.utc(2004, 4, 1, 9, 20, 0), 0x0006),
        equals('23456948011089526127'),
      );
    });
    test('step6: 01/04/2004 09:25:00, reg=0x0007 → 51867282903899304686', () {
      expect(
        genCc(DateTime.utc(2004, 4, 1, 9, 25, 0), 0x0007),
        equals('51867282903899304686'),
      );
    });
  });

  group('STS_531_1_0_02 CTSA01 (TransferElectricityCredit, STA)', () {
    // Class 0 electricity credit tokens under DKGA-02 + STA. Water/gas
    // steps (3/4/5/6) intentionally skipped per the Class 0 SubClass
    // scope.
    test('step1: PAN 600727000000000009, 01/03/2004 13:55:00, 0.1 kWh → '
        '23716100501183194197', () {
      final dk = defaultDecoderKey();
      final token = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(0.1)
        ..tokenIdentifier = _tid(DateTime.utc(2004, 3, 1, 13, 55, 0))
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('23716100501183194197'));
    });

    test('step2: PAN 000001000000000082, 01/03/2004 14:00:00, 0.1 kWh → '
        '67206107716095682372', () {
      final dk = _dkga02(
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: krn,
        iinStr: '000001',
        iainStr: '00000000008',
        vudk: vudk,
      );
      final token = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(0.1)
        ..tokenIdentifier = _tid(DateTime.utc(2004, 3, 1, 14, 0, 0))
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('67206107716095682372'));
    });
  });

  group('STS_531_1_0_02 CTSA25 (TransferElectricityCredit, DKGA-04 + STA)', () {
    // DKGA-04 key derivation but STA encryption. 20-byte vending key,
    // SGC=123457. Electricity-only steps (1/5/9); water/gas steps
    // skipped.
    final vudk04 = VendingUniqueDesKey(
      _hex('abababababababab949494949494949401234567'),
    );
    final sgc04 = SupplyGroupCode('123457');
    final defaultPan = MeterPrimaryAccountNumber(
      issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
      individualAccountIdentificationNumber:
          IndividualAccountIdentificationNumber('00000000000'),
    );

    DecoderKey dkga04({
      required BaseDate baseDate,
      required KeyRevisionNumber krn,
    }) => DecoderKeyGeneratorAlgorithm04(
      baseDate: baseDate,
      tariffIndex: ti,
      supplyGroupCode: sgc04,
      keyType: keyType,
      keyRevisionNumber: krn,
      encryptionAlgorithm: ea07,
      meterPan: defaultPan,
      vendingKey: vudk04,
    ).generate();

    test('step1: baseDate=1993, KRN=1, 01/01/2009 08:00:00, 0.1 kWh → '
        '15697331168573253829', () {
      final dk = dkga04(baseDate: BaseDate.date1993, krn: KeyRevisionNumber(1));
      final token = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(0.1)
        ..tokenIdentifier = _tid(DateTime.utc(2009, 1, 1, 8, 0, 0))
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('15697331168573253829'));
    });

    test('step5: baseDate=2014, KRN=4, 01/01/2014 08:00:00, 0.1 kWh → '
        '20324881626382980759', () {
      final dk = dkga04(baseDate: BaseDate.date2014, krn: KeyRevisionNumber(4));
      final token = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(0.1)
        ..tokenIdentifier = TokenIdentifier(
          BaseDate.date2014,
          timeOfIssue: DateTime.utc(2014, 1, 1, 8, 0, 0),
        )
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('20324881626382980759'));
    });

    test('step9: baseDate=2035, KRN=5, 01/01/2035 08:00:00, 0.1 kWh → '
        '09239624803025986815', () {
      final dk = dkga04(baseDate: BaseDate.date2035, krn: KeyRevisionNumber(5));
      final token = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(0.1)
        ..tokenIdentifier = TokenIdentifier(
          BaseDate.date2035,
          timeOfIssue: DateTime.utc(2035, 1, 1, 8, 0, 0),
        )
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('09239624803025986815'));
    });
  });

  group('Nectar_1 (TransferElectricityCredit Amount sweep, STA)', () {
    // Vendor extension suite: same DKGA-02 + STA setup as CTSA01_02
    // (PAN=600727000000000009, baseDate=1993) but with 15 amount
    // steps spanning the full STS exponent/mantissa range, including
    // sub-1 and fractional values. Water/gas variants of each step
    // are intentionally skipped per the Class 0 SubClass scope.
    String genTec(DateTime issuedAt, double amount) {
      final dk = defaultDecoderKey();
      final token = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(amount)
        ..tokenIdentifier = _tid(issuedAt)
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(dk, ea07).generate(token);
      return token.tokenNo;
    }

    test('step1: 21/04/2004 10:01:00, 1 kWh → 66475648316756821785', () {
      expect(
        genTec(DateTime.utc(2004, 4, 21, 10, 1, 0), 1),
        equals('66475648316756821785'),
      );
    });
    test('step2A: 21/05/2004 10:02:00, 16383 kWh → 36924780240841024731', () {
      expect(
        genTec(DateTime.utc(2004, 5, 21, 10, 2, 0), 16383),
        equals('36924780240841024731'),
      );
    });
    test('step3A: 21/04/2005 10:03:00, 16384 kWh → 65724708343212635258', () {
      expect(
        genTec(DateTime.utc(2005, 4, 21, 10, 3, 0), 16384),
        equals('65724708343212635258'),
      );
    });
    test('step4: 22/04/2005 10:04:00, 180224 kWh → 42371551666535254341', () {
      expect(
        genTec(DateTime.utc(2005, 4, 22, 10, 4, 0), 180224),
        equals('42371551666535254341'),
      );
    });
    test('step5B: 22/04/2005 11:00:00, 1818624 kWh → '
        '18009632033176370418', () {
      expect(
        genTec(DateTime.utc(2005, 4, 22, 11, 0, 0), 1818624),
        equals('18009632033176370418'),
      );
    });
    test('step6A: 22/04/2005 11:01:00, 1820162 kWh → '
        '12805131357955755939', () {
      expect(
        genTec(DateTime.utc(2005, 4, 22, 11, 1, 0), 1820162),
        equals('12805131357955755939'),
      );
    });
    test('step7: 22/04/2005 11:02:00, 182042 kWh → 57144000167239742426', () {
      expect(
        genTec(DateTime.utc(2005, 4, 22, 11, 2, 0), 182042),
        equals('57144000167239742426'),
      );
    });
    test('step8B: 22/04/2005 11:03:00, 123546 kWh → '
        '37909354224671858723', () {
      expect(
        genTec(DateTime.utc(2005, 4, 22, 11, 3, 0), 123546),
        equals('37909354224671858723'),
      );
    });
    test('step9B: 22/04/2005 11:04:00, 1763427 kWh → '
        '71777743993390229056', () {
      expect(
        genTec(DateTime.utc(2005, 4, 22, 11, 4, 0), 1763427),
        equals('71777743993390229056'),
      );
    });
    test('step10: 22/04/2005 11:05:00, 14782 kWh → 73561917813841338074', () {
      expect(
        genTec(DateTime.utc(2005, 4, 22, 11, 5, 0), 14782),
        equals('73561917813841338074'),
      );
    });
    test('step11B: 22/04/2005 20:10:00, 1.82 kWh → 55160880109952893498', () {
      expect(
        genTec(DateTime.utc(2005, 4, 22, 20, 10, 0), 1.82),
        equals('55160880109952893498'),
      );
    });
    test('step12A: 22/04/2005 11:00:00, 18981.349 kWh → '
        '43183161221229495584', () {
      expect(
        genTec(DateTime.utc(2005, 4, 22, 11, 0, 0), 18981.349),
        equals('43183161221229495584'),
      );
    });
    test('step13: 22/04/2005 20:12:00, 1897.345 kWh → '
        '62624214800861085936', () {
      expect(
        genTec(DateTime.utc(2005, 4, 22, 20, 12, 0), 1897.345),
        equals('62624214800861085936'),
      );
    });
    test('step14A: 22/04/2005 20:14:00, 10897.345 kWh → '
        '08032634883920046224', () {
      expect(
        genTec(DateTime.utc(2005, 4, 22, 20, 14, 0), 10897.345),
        equals('08032634883920046224'),
      );
    });
    test('step15B: 12/05/2005 20:15:00, 0.4712 kWh → '
        '05983059757600918504', () {
      expect(
        genTec(DateTime.utc(2005, 5, 12, 20, 15, 0), 0.4712),
        equals('05983059757600918504'),
      );
    });
  });

  // CTSA02 — InitiateMeterTestOrDisplay 1 & 2 (Class 1 unencrypted).
  //
  // Java vectors port from STSComplianceTests_STS_531_1_0_02_CTSA02.java.
  // No DKGA / EA mixing: the data block is just
  // `crc || manufacturerCode || control || subClass`, transposed to 66
  // bits and emitted in the clear. We still pass a derived key and EA
  // to satisfy the constructor signature — they are no-ops for Class 1.
  group('STS_531_1_0_02 CTSA02 (Class 1 InitiateMeterTestOrDisplay)', () {
    test('step1: PAN=600727000000000009, mfg=0x00 (8-bit), control=36×1 '
        '→ 56493153725450313471', () {
      final dk = defaultDecoderKey();
      final mfg = ManufacturerCode.fromInt(0, widthBits: 8);
      final ctrl = Control(BitString.fromBinary('1' * 36), mfg);
      final token = InitiateMeterTestOrDisplay1Token('request_id')
        ..manufacturerCode = mfg
        ..control = ctrl;
      InitiateMeterTestOrDisplay1TokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('56493153725450313471'));
    });
    test('step2: PAN=000001000000000082, mfg=ManufacturerCode("0000") '
        '(16-bit 0x0000), control=28×1 → 02305843005052951967', () {
      // DK / EA are unused by Class 1 (the data block is emitted in
      // the clear). Reuse `defaultDecoderKey()` to satisfy the ctor.
      final dk = defaultDecoderKey();
      final mfg = ManufacturerCode.fromInt(0, widthBits: 16);
      final ctrl = Control(BitString.fromBinary('1' * 28), mfg);
      final token = InitiateMeterTestOrDisplay2Token('request_id')
        ..manufacturerCode = mfg
        ..control = ctrl;
      InitiateMeterTestOrDisplay2TokenGenerator(dk, ea07).generate(token);
      expect(token.tokenNo, equals('02305843005052951967'));
    });
  });

  // CTSA10 — TransferElectricityCredit amount + date sweep using the
  // standard CTSA setup (DKGA-02, defaultDecoderKey, EA07). KEN=255 on
  // the Java side but Dart's Class 0 generator does not mix KEN into
  // the data block (only Class 2 key-change tokens consume it), so the
  // vectors are byte-identical to a defaultDecoderKey + amount-sweep.
  // Water/gas steps in the Java suite are skipped per the Class 0
  // SubClass 0 scope.
  group('STS_531_1_0_02 CTSA10 (TransferElectricityCredit amount sweep)', () {
    String genTec(DateTime issuedAt, double amount) {
      final dk = defaultDecoderKey();
      final token = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(amount)
        ..tokenIdentifier = _tid(issuedAt)
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(dk, ea07).generate(token);
      return token.tokenNo;
    }

    test('step1: 01/04/2004 00:30:00, 25.6 → 26456622012185850752', () {
      expect(
        genTec(DateTime.utc(2004, 4, 1, 0, 30, 0), 25.6),
        equals('26456622012185850752'),
      );
    });
    test('step2: 01/04/2004 00:35:00, 1638.3 → 02194538019157867319', () {
      expect(
        genTec(DateTime.utc(2004, 4, 1, 0, 35, 0), 1638.3),
        equals('02194538019157867319'),
      );
    });
    test('step3: 01/04/2004 00:40:00, 1638.4 → 49848950875249585071', () {
      expect(
        genTec(DateTime.utc(2004, 4, 1, 0, 40, 0), 1638.4),
        equals('49848950875249585071'),
      );
    });
    test('step4: 01/04/2004 00:45:00, 2000.0 → 71997443697501228179', () {
      expect(
        genTec(DateTime.utc(2004, 4, 1, 0, 45, 0), 2000.0),
        equals('71997443697501228179'),
      );
    });
    test('step5: 01/04/2004 00:50:00, 18022.3 → 58589277912776864555', () {
      expect(
        genTec(DateTime.utc(2004, 4, 1, 0, 50, 0), 18022.3),
        equals('58589277912776864555'),
      );
    });
    test('step6: 01/04/2004 00:55:00, 18022.4 → 16328229234437142451', () {
      expect(
        genTec(DateTime.utc(2004, 4, 1, 0, 55, 0), 18022.4),
        equals('16328229234437142451'),
      );
    });
    test('step7: 01/04/2004 01:44:00, 181862.3 → 45001756646344378677', () {
      expect(
        genTec(DateTime.utc(2004, 4, 1, 1, 44, 0), 181862.3),
        equals('45001756646344378677'),
      );
    });
    test('step8: 01/04/2004 01:49:00, 181862.4 → 15810488151857362998', () {
      expect(
        genTec(DateTime.utc(2004, 4, 1, 1, 49, 0), 181862.4),
        equals('15810488151857362998'),
      );
    });
    test('step9: 01/04/2004 01:54:00, 1820162.4 → 42222423067848970276', () {
      expect(
        genTec(DateTime.utc(2004, 4, 1, 1, 54, 0), 1820162.4),
        equals('42222423067848970276'),
      );
    });
  });

  // CTSA11 — Class 1 InitiateMeterTestOrDisplay control-bit sweep (16
  // steps). Same pattern as CTSA02 but with non-zero control values
  // walking the bit positions 0..10 then 13..17. mfg=0 (8-bit) for
  // the 2-digit variant and mfg=0x0000 (16-bit) for the 4-digit
  // variant; no DK/EA dependency (Class 1 emits the data block in the
  // clear).
  group('STS_531_1_0_02 CTSA11 (Class 1 control-bit sweep)', () {
    final dk = defaultDecoderKey();
    final mfg2 = ManufacturerCode.fromInt(0, widthBits: 8);
    final mfg4 = ManufacturerCode.fromInt(0, widthBits: 16);

    String gen1(int ctrl) {
      final c = Control(BitString.fromValue(ctrl, 36), mfg2);
      final token = InitiateMeterTestOrDisplay1Token('request_id')
        ..manufacturerCode = mfg2
        ..control = c;
      InitiateMeterTestOrDisplay1TokenGenerator(dk, ea07).generate(token);
      return token.tokenNo;
    }

    String gen2(int ctrl) {
      final c = Control(BitString.fromValue(ctrl, 28), mfg4);
      final token = InitiateMeterTestOrDisplay2Token('request_id')
        ..manufacturerCode = mfg4
        ..control = c;
      InitiateMeterTestOrDisplay2TokenGenerator(dk, ea07).generate(token);
      return token.tokenNo;
    }

    const cases = <List<Object>>[
      [0x00001, '00000000000150997584', '01152921509036054672'],
      [0x00002, '00000000000167774880', '01152921513331042448'],
      [0x00004, '00000000000201328896', '01152921521920952465'],
      [0x00008, '18446744073843772416', '01152921539100838034'],
      [0x00010, '36893488147553322496', '01152921573460543637'],
      [0x00020, '00000000000671093248', '01152921642180020378'],
      [0x00040, '00000000001207974400', '01152921779618973828'],
      [0x00080, '00000000002281728512', '01152922054496880824'],
      [0x00100, '00000000004429208064', '01152922604252694700'],
      [0x00200, '00000000008724195840', '01152923703764322536'],
      [0x00400, '00000000017314105857', '01152925902787577952'],
      [0x02000, '00000000137573173770', '01152956689113154192'],
      [0x04000, '00000000275012127252', '01152991873485249680'],
      [0x08000, '00000000549890034216', '01153062242229428368'],
      [0x10000, '00000001099645848124', '01153202979717788816'],
      [0x20000, '00000002199157475960', '01153484454694514832'],
    ];

    for (final c in cases) {
      final ctrl = c[0] as int;
      final tok1 = c[1] as String;
      final tok2 = c[2] as String;
      test('control=0x${ctrl.toRadixString(16)} → mfg2=$tok1, mfg4=$tok2', () {
        expect(gen1(ctrl), equals(tok1));
        expect(gen2(ctrl), equals(tok2));
      });
    }
  });

  // CTSA16 — InvalidVendingOrDecoderKeyException negative path. The
  // Java upstream throws inside TransferElectricityCreditTokenGenerator
  // when KT=1 + a malformed-Luhn PAN ("600727111111111153") + KEN=85
  // are combined. The Dart Class 0 generator does not replicate that
  // (KEN is metadata only and PAN Luhn is consumer-side validated via
  // MeterPrimaryAccountNumber.fromString(..., validate: validate)), so
  // the round-trip succeeds in Dart. Documented as a known parity
  // skip pending an explicit `VendingUniqueDesKey`-aware DKGA-02
  // validator in the generator.

  // CTSA19 — KCT pair (Set1stSection + Set2ndSection) followed by a
  // TransferElectricityCredit, exercising DKGA-02 + STA across 4
  // (KRN, TI, KEN, SGC, vudk) parameter combinations. The Java
  // upstream calls the KCT generators with `decoderKey == newDecoderKey`
  // (no actual rollover — just exercises the wire-format encoding).
  group('STS_531_1_0_02 CTSA19 (KCT + TransferElectricityCredit sweep)', () {
    final vudkDefault = vudk;
    final vudk94 = VendingUniqueDesKey(_hex('9494949494949494'));
    final sgcDefault = sgc;
    final sgc888 = SupplyGroupCode('888888');
    const iinStr = '600727';
    const iainStr = '00000000000';

    DecoderKey derive({
      required TariffIndex ti,
      required KeyRevisionNumber krn,
      required SupplyGroupCode sgcArg,
      required VendingUniqueDesKey vudkArg,
    }) => _dkga02(
      keyType: keyType,
      sgc: sgcArg,
      ti: ti,
      krn: krn,
      iinStr: iinStr,
      iainStr: iainStr,
      vudk: vudkArg,
    );

    Map<String, String> genStep({
      required DateTime issuedAt,
      required KeyRevisionNumber krn,
      required TariffIndex ti,
      required int ken,
      required SupplyGroupCode sgcArg,
      required VendingUniqueDesKey vudkArg,
    }) {
      final dk = derive(ti: ti, krn: krn, sgcArg: sgcArg, vudkArg: vudkArg);
      final kenho = KeyExpiryNumberHighOrder(
        BitString.fromValue((ken >> 4) & 0xF, 4),
      );
      final kenlo = KeyExpiryNumberLowOrder(BitString.fromValue(ken & 0xF, 4));
      final tok1 = Set1stSectionDecoderKeyTokenGenerator(
        decoderKey: dk,
        encryptionAlgorithm: ea07,
        keyExpiryNumberHighOrder: kenho,
        keyRevisionNumber: krn,
        rolloverKeyChange: RolloverKeyChange.fromBool(false),
        keyType: keyType,
        newDecoderKey: dk,
      ).generateNew('request_id');
      final tok2 = Set2ndSectionDecoderKeyTokenGenerator(
        decoderKey: dk,
        encryptionAlgorithm: ea07,
        keyExpiryNumberLowOrder: kenlo,
        tariffIndex: ti,
        newDecoderKey: dk,
      ).generateNew('request_id');
      final tec = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(0.1)
        ..tokenIdentifier = _tid(issuedAt)
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(dk, ea07).generate(tec);
      return {'set1': tok1.tokenNo, 'set2': tok2.tokenNo, 'tec': tec.tokenNo};
    }

    test(
      'step1: KRN=1, TI=02, KEN=85, default SGC/vudk, 01/04/2002 10:05:00',
      () {
        final r = genStep(
          issuedAt: DateTime.utc(2002, 4, 1, 10, 5, 0),
          krn: KeyRevisionNumber(1),
          ti: TariffIndex('02'),
          ken: 85,
          sgcArg: sgcDefault,
          vudkArg: vudkDefault,
        );
        expect(r['set1'], equals('31337250623187821174'));
        expect(r['set2'], equals('25365690080149305690'));
        expect(r['tec'], equals('40823728429161791369'));
      },
    );

    // Java upstream JUnit `@Before` resets `tariffIndex` to "01"
    // before EACH @Test, so step2 / step3 inherit TI=01 even though
    // step1 (run in isolation) had set it to "02". Only step1
    // explicitly reassigns to "02".
    test('step2: KRN=2, TI=01, KEN=85, 01/04/2002 10:10:00', () {
      final r = genStep(
        issuedAt: DateTime.utc(2002, 4, 1, 10, 10, 0),
        krn: KeyRevisionNumber(2),
        ti: TariffIndex('01'),
        ken: 85,
        sgcArg: sgcDefault,
        vudkArg: vudkDefault,
      );
      expect(r['set1'], equals('44144630105464684572'));
      expect(r['set2'], equals('31162823148845145254'));
      expect(r['tec'], equals('07731698895042112630'));
    });

    test('step3: KRN=2, TI=01, KEN=255, 01/04/2002 10:15:00', () {
      final r = genStep(
        issuedAt: DateTime.utc(2002, 4, 1, 10, 15, 0),
        krn: KeyRevisionNumber(2),
        ti: TariffIndex('01'),
        ken: 255,
        sgcArg: sgcDefault,
        vudkArg: vudkDefault,
      );
      expect(r['set1'], equals('27767097093580610394'));
      expect(r['set2'], equals('37287781995519266010'));
      expect(r['tec'], equals('02838142732283753296'));
    });

    test('step4: KRN=1, TI=01, KEN=85, SGC=888888, vudk=9494…, '
        '01/04/2002 10:20:00', () {
      final r = genStep(
        issuedAt: DateTime.utc(2002, 4, 1, 10, 20, 0),
        krn: KeyRevisionNumber(1),
        ti: TariffIndex('01'),
        ken: 85,
        sgcArg: sgc888,
        vudkArg: vudk94,
      );
      expect(r['set1'], equals('54413905164151863438'));
      expect(r['set2'], equals('70335822849409372395'));
      expect(r['tec'], equals('17352963892501043261'));
    });
  });

  // CTSA24 — ClearCredit token via DKGA-04 + STA. 20-byte vending key,
  // SGC=123457, KT=2, KRN=1, KEN=255, baseDate=1993.
  group('STS_531_1_0_02 CTSA24 (ClearCredit via DKGA-04+STA)', () {
    final vudk04 = VendingUniqueDesKey(
      _hex('abababababababab949494949494949401234567'),
    );
    final sgc04 = SupplyGroupCode('123457');
    final pan = MeterPrimaryAccountNumber.fromString(
      '600727000000000009',
      validate: MeterPanValidation.skip,
    );

    test(
      'step1: 26/05/2008 08:00:00, register=0xFFFF → 08144275084202187413',
      () {
        final dk = DecoderKeyGeneratorAlgorithm04(
          baseDate: BaseDate.date1993,
          tariffIndex: ti,
          supplyGroupCode: sgc04,
          keyType: keyType,
          keyRevisionNumber: KeyRevisionNumber(1),
          encryptionAlgorithm: ea07,
          meterPan: pan,
          vendingKey: vudk04,
        ).generate();
        final token = ClearCreditTokenGenerator(dk, ea07).buildToken(
          'request_id',
          randomNo: _rnd5,
          tokenIdentifier: _tid(DateTime.utc(2008, 5, 26, 8, 0, 0)),
          register: Register(BitString.fromValue(0xFFFF, 16)),
        );
        ClearCreditTokenGenerator(dk, ea07).generate(token);
        expect(token.tokenNo, equals('08144275084202187413'));
      },
    );
  });

  // CTSA26 — KCT pair via DKGA-04 + STA with a base-date rotation
  // (1993→2014→2035 family). decoderKey derived from
  // (baseDate=2014, KRN=4); newDecoderKey derived from
  // (newBaseDate=2035, newKRN=5). KCT delivers the new KRN=5 +
  // rolloverKeyChange="1".
  group('STS_531_1_0_02 CTSA26 (KCT via DKGA-04 + new base date)', () {
    final vudk04 = VendingUniqueDesKey(
      _hex('abababababababab949494949494949401234567'),
    );
    final sgc04 = SupplyGroupCode('123457');
    final keyRevisionNumber = KeyRevisionNumber(4);
    final newKeyRevisionNumber = KeyRevisionNumber(5);
    final ken = 255;
    final kenho = KeyExpiryNumberHighOrder(
      BitString.fromValue((ken >> 4) & 0xF, 4),
    );
    final kenlo = KeyExpiryNumberLowOrder(BitString.fromValue(ken & 0xF, 4));
    final newRolloverKeyChange = RolloverKeyChange.fromBool(true);

    Map<String, String> genStep(MeterPrimaryAccountNumber pan) {
      final dk = DecoderKeyGeneratorAlgorithm04(
        baseDate: BaseDate.date2014,
        tariffIndex: ti,
        supplyGroupCode: sgc04,
        keyType: keyType,
        keyRevisionNumber: keyRevisionNumber,
        encryptionAlgorithm: ea07,
        meterPan: pan,
        vendingKey: vudk04,
      ).generate();
      final newDk = DecoderKeyGeneratorAlgorithm04(
        baseDate: BaseDate.date2035,
        tariffIndex: ti,
        supplyGroupCode: sgc04,
        keyType: keyType,
        keyRevisionNumber: newKeyRevisionNumber,
        encryptionAlgorithm: ea07,
        meterPan: pan,
        vendingKey: vudk04,
      ).generate();
      final tok1 = Set1stSectionDecoderKeyTokenGenerator(
        decoderKey: dk,
        encryptionAlgorithm: ea07,
        keyExpiryNumberHighOrder: kenho,
        keyRevisionNumber: newKeyRevisionNumber,
        rolloverKeyChange: newRolloverKeyChange,
        keyType: keyType,
        newDecoderKey: newDk,
      ).generateNew('request_id');
      final tok2 = Set2ndSectionDecoderKeyTokenGenerator(
        decoderKey: dk,
        encryptionAlgorithm: ea07,
        keyExpiryNumberLowOrder: kenlo,
        tariffIndex: ti,
        newDecoderKey: newDk,
      ).generateNew('request_id');
      return {'set1': tok1.tokenNo, 'set2': tok2.tokenNo};
    }

    test('step1: PAN=600727000000000009 → '
        'Set1st=44163577485799480640, Set2nd=26556810679164981397', () {
      final pan = MeterPrimaryAccountNumber.fromString(
        '600727000000000009',
        validate: MeterPanValidation.skip,
      );
      final r = genStep(pan);
      expect(r['set1'], equals('44163577485799480640'));
      expect(r['set2'], equals('26556810679164981397'));
    });

    test('step2: PAN=000001000000000082 → '
        'Set1st=09658886361133612086, Set2nd=22434017728466234784', () {
      final pan = MeterPrimaryAccountNumber.fromString(
        '000001000000000082',
        validate: MeterPanValidation.skip,
      );
      final r = genStep(pan);
      expect(r['set1'], equals('09658886361133612086'));
      expect(r['set2'], equals('22434017728466234784'));
    });
  });

  // CTSA21 (water credit) and CTSA22 (gas credit) are not portable:
  // the Dart implementation only ships the Class 0 electricity-credit
  // path. Water/gas TransferCreditToken generators are intentionally
  // out of scope (the VirtualHsm dispatcher already rejects subclass
  // 1 and 2 — see virtual_hsm_dispatch_test.dart). Documented here
  // for parity-suite completeness.
  group('STS_531_1_0_02 CTSA21/CTSA22 (water/gas Class 0)', () {
    test(
      'parity-skip: water/gas Class 0 not ported in Dart',
      () {
        // No-op marker — the rejection path is asserted in
        // virtual_hsm_dispatch_test.dart.
        expect(true, isTrue);
      },
      skip: 'Class 0 subclass 1 (water) / 2 (gas) intentionally out of scope.',
    );
  });

  // ===========================================================
  // STS 531-1 v1.0.04 — DKGA-04 + MISTY1 (EA-11) coverage
  // ===========================================================
  //
  // The 1.0.04 revision exercises the MISTY1 block cipher (EA-11)
  // with DKGA-04 (HMAC-SHA-256 key derivation). The Dart port ships
  // both primitives; below we mirror the most algorithmically
  // distinctive vectors:
  //
  //   - 1.0.04 CTSA09 — ClearCredit (Class 2) via DKGA-04+MISTY1
  //   - 1.0.04 CTSA12 — SetMaximumPowerLimit (Class 2) sweep
  //                     across the MPL exponent/mantissa boundaries
  //                     (256, 16383, 16384, 20000, 180223, 180224,
  //                      1818623, 1818624, 18201624)
  //
  // Shared setup (matches both Java @Before blocks):
  //   - vudk = hex 'abababababababab949494949494949401234567' (20 B)
  //   - SGC = '123457', TI = '01', KRN = 1, KT = 2
  //   - PAN = '600727000000000009' (skip validation)
  //   - baseDate = 1993, randomNo = 0x5
  //
  final vudk04 = VendingUniqueDesKey(
    _hex('abababababababab949494949494949401234567'),
  );
  final sgc04 = SupplyGroupCode('123457');
  final pan04 = MeterPrimaryAccountNumber.fromString(
    '600727000000000009',
    validate: MeterPanValidation.skip,
  );
  final ea11 = Misty1EncryptionAlgorithm();

  DecoderKey dkga04Misty1({KeyRevisionNumber? krn}) =>
      DecoderKeyGeneratorAlgorithm04(
        baseDate: BaseDate.date1993,
        tariffIndex: ti,
        supplyGroupCode: sgc04,
        keyType: keyType,
        keyRevisionNumber: krn ?? KeyRevisionNumber(1),
        encryptionAlgorithm: ea11,
        meterPan: pan04,
        vendingKey: vudk04,
      ).generate();

  group('STS_531_1_0_04 CTSA09 (ClearCredit via DKGA-04 + MISTY1)', () {
    // Each step rebuilds the decoder key the same way (matches the
    // Java pattern of re-deriving inside every @Test).
    final cases = <List<dynamic>>[
      [DateTime.utc(2004, 3, 29, 0, 0, 0), '09791211239166238461'],
      [DateTime.utc(2004, 3, 29, 0, 1, 0), '18070818655140104337'],
      // CTSA09 step3 in Java is a multi-minute series that exercises
      // the same generator at 00:03/00:04/00:05 with the TID rolled
      // forward. Each minute is exercised here as an independent
      // vector (the rolling TID counter is a vending-side concern,
      // left to the caller in the Dart port).
      [DateTime.utc(2004, 3, 29, 0, 3, 0), '59463760341829598722'],
      [DateTime.utc(2004, 3, 29, 0, 4, 0), '49512072598296997272'],
      [DateTime.utc(2004, 3, 29, 0, 5, 0), '59135803195278393273'],
    ];

    for (var i = 0; i < cases.length; i++) {
      final issuedAt = cases[i][0] as DateTime;
      final expected = cases[i][1] as String;
      test('step${i + 1}: $issuedAt → $expected', () {
        final dk = dkga04Misty1();
        final token = ClearCreditTokenGenerator(dk, ea11).buildToken(
          'request_id',
          randomNo: _rnd5,
          tokenIdentifier: _tid(issuedAt),
          register: Register(BitString.fromValue(0xFFFF, 16)),
        );
        ClearCreditTokenGenerator(dk, ea11).generate(token);
        expect(token.tokenNo, equals(expected));
      });
    }
  });

  group(
    'STS_531_1_0_04 CTSA12 (SetMaximumPowerLimit via DKGA-04 + MISTY1)',
    () {
      // All 9 steps issued on 01/04/2004 at minute boundaries with
      // increasing MPL values that span the STS exponent/mantissa
      // representation boundaries.
      final cases = <List<dynamic>>[
        [DateTime.utc(2004, 4, 1, 7, 0, 0), 256, '58601433826945463485'],
        [DateTime.utc(2004, 4, 1, 7, 5, 0), 16383, '13997395479415026219'],
        [DateTime.utc(2004, 4, 1, 7, 10, 0), 16384, '18037738085263294820'],
        [DateTime.utc(2004, 4, 1, 7, 15, 0), 20000, '06738975074638745925'],
        [DateTime.utc(2004, 4, 1, 7, 20, 0), 180223, '66354091567942569601'],
        [DateTime.utc(2004, 4, 1, 7, 25, 0), 180224, '62853351521017859877'],
        [DateTime.utc(2004, 4, 1, 7, 30, 0), 1818623, '40984149905900332649'],
        [DateTime.utc(2004, 4, 1, 7, 35, 0), 1818624, '26882838654580901052'],
        [DateTime.utc(2004, 4, 1, 7, 40, 0), 18201624, '29255956459122361629'],
      ];

      for (var i = 0; i < cases.length; i++) {
        final issuedAt = cases[i][0] as DateTime;
        final mpl = cases[i][1] as int;
        final expected = cases[i][2] as String;
        test('step${i + 1}: MPL=$mpl @ $issuedAt → $expected', () {
          final dk = dkga04Misty1();
          final token = SetMaximumPowerLimitTokenGenerator(dk, ea11).buildToken(
            'request_id',
            randomNo: _rnd5,
            tokenIdentifier: _tid(issuedAt),
            maximumPowerLimit: MaximumPowerLimit(mpl),
          );
          SetMaximumPowerLimitTokenGenerator(dk, ea11).generate(token);
          expect(token.tokenNo, equals(expected));
        });
      }
    },
  );

  // ===========================================================
  // STS 531-1 v1.0.04 — remaining electricity vectors
  // ===========================================================
  //
  // Same shared setup as CTSA09/CTSA12 (DKGA-04 + MISTY1, vudk04,
  // SGC=123457, TI=01, KRN=1, KT=2, PAN=600727…). Helpers reused.
  //
  // Skipped from each Java suite:
  //   - CTSA01 steps 2/3 (water/gas, 1993), 6/7 (water/gas, alt PAN),
  //     10/11 (water/gas, 2014), 14/15 (water/gas, 2035): electricity
  //     steps 1, 5, 9, 13 are ported here.
  //   - CTSA10 steps 10..27 (water/gas amount sweep): only the 9
  //     electricity vectors are ported.
  //   - CTSA16 (negative test for InvalidVendingOrDecoderKeyException
  //     on bad-Luhn PAN under DKGA-04): same parity skip as 1.0.02
  //     CTSA16 — the matching exception is not raised in Dart.

  group(
    'STS_531_1_0_04 CTSA01 (TransferElectricityCredit, electricity-only)',
    () {
      String genTec({
        required MeterPrimaryAccountNumber pan,
        required BaseDate baseDate,
        required KeyRevisionNumber krn,
        required DateTime issuedAt,
        required double amount,
      }) {
        final dk = DecoderKeyGeneratorAlgorithm04(
          baseDate: baseDate,
          tariffIndex: ti,
          supplyGroupCode: sgc04,
          keyType: keyType,
          keyRevisionNumber: krn,
          encryptionAlgorithm: ea11,
          meterPan: pan,
          vendingKey: vudk04,
        ).generate();
        final token = TransferElectricityCreditToken('request_id')
          ..amountPurchased = Amount(amount)
          ..tokenIdentifier = TokenIdentifier(baseDate, timeOfIssue: issuedAt)
          ..randomNo = _rnd5;
        TransferElectricityCreditTokenGenerator(dk, ea11).generate(token);
        return token.tokenNo;
      }

      final altPan = MeterPrimaryAccountNumber.fromString(
        '000001000000000082',
        validate: MeterPanValidation.skip,
      );

      test('step1: 01/03/2004 13:00:00, PAN 600727, KRN=1, 1993 → '
          '59386323472137426967', () {
        expect(
          genTec(
            pan: pan04,
            baseDate: BaseDate.date1993,
            krn: KeyRevisionNumber(1),
            issuedAt: DateTime.utc(2004, 3, 1, 13, 0, 0),
            amount: 0.1,
          ),
          equals('59386323472137426967'),
        );
      });

      test('step5: 01/03/2004 13:20:00, PAN 000001…0082, KRN=1, 1993 → '
          '25453597494250138964', () {
        expect(
          genTec(
            pan: altPan,
            baseDate: BaseDate.date1993,
            krn: KeyRevisionNumber(1),
            issuedAt: DateTime.utc(2004, 3, 1, 13, 20, 0),
            amount: 0.1,
          ),
          equals('25453597494250138964'),
        );
      });

      test('step9: 01/01/2014 08:00:00, PAN 600727, KRN=4, 2014 → '
          '13444522537517076834', () {
        expect(
          genTec(
            pan: pan04,
            baseDate: BaseDate.date2014,
            krn: KeyRevisionNumber(4),
            issuedAt: DateTime.utc(2014, 1, 1, 8, 0, 0),
            amount: 0.1,
          ),
          equals('13444522537517076834'),
        );
      });

      test('step13: 01/01/2035 08:00:00, PAN 600727, KRN=5, 2035 → '
          '11907826947753213480', () {
        expect(
          genTec(
            pan: pan04,
            baseDate: BaseDate.date2035,
            krn: KeyRevisionNumber(5),
            issuedAt: DateTime.utc(2035, 1, 1, 8, 0, 0),
            amount: 0.1,
          ),
          equals('11907826947753213480'),
        );
      });
    },
  );

  group(
    'STS_531_1_0_04 CTSA03 (SetMaximumPowerLimit single via DKGA-04 + MISTY1)',
    () {
      test('step1: 28/03/2004 09:01:00, MPL=1000 → 26521936751055502278', () {
        final dk = dkga04Misty1();
        final token = SetMaximumPowerLimitTokenGenerator(dk, ea11).buildToken(
          'request_id',
          randomNo: _rnd5,
          tokenIdentifier: _tid(DateTime.utc(2004, 3, 28, 9, 1, 0)),
          maximumPowerLimit: MaximumPowerLimit(1000),
        );
        SetMaximumPowerLimitTokenGenerator(dk, ea11).generate(token);
        expect(token.tokenNo, equals('26521936751055502278'));
      });
    },
  );

  group('STS_531_1_0_04 CTSA04 (ClearCredit via DKGA-04 + MISTY1)', () {
    test('step1: 28/03/2004 09:15:00, PAN 600727, reg=0xFFFF → '
        '59725289138639529749', () {
      final dk = dkga04Misty1();
      final token = ClearCreditTokenGenerator(dk, ea11).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(DateTime.utc(2004, 3, 28, 9, 15, 0)),
        register: Register(BitString.fromValue(0xFFFF, 16)),
      );
      ClearCreditTokenGenerator(dk, ea11).generate(token);
      expect(token.tokenNo, equals('59725289138639529749'));
    });

    test('step2: 28/03/2004 09:16:00, PAN 000001…0082, reg=0xFFFF → '
        '43917986274716482997', () {
      final altPan = MeterPrimaryAccountNumber.fromString(
        '000001000000000082',
        validate: MeterPanValidation.skip,
      );
      final dk = DecoderKeyGeneratorAlgorithm04(
        baseDate: BaseDate.date1993,
        tariffIndex: ti,
        supplyGroupCode: sgc04,
        keyType: keyType,
        keyRevisionNumber: KeyRevisionNumber(1),
        encryptionAlgorithm: ea11,
        meterPan: altPan,
        vendingKey: vudk04,
      ).generate();
      final token = ClearCreditTokenGenerator(dk, ea11).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(DateTime.utc(2004, 3, 28, 9, 16, 0)),
        register: Register(BitString.fromValue(0xFFFF, 16)),
      );
      ClearCreditTokenGenerator(dk, ea11).generate(token);
      expect(token.tokenNo, equals('43917986274716482997'));
    });
  });

  group(
    'STS_531_1_0_04 CTSA06 (ClearTamperCondition via DKGA-04 + MISTY1)',
    () {
      test('step1: 28/03/2004 10:00:00, pad=0x0000 → 02455019196514047304', () {
        final dk = dkga04Misty1();
        final token = ClearTamperConditionTokenGenerator(dk, ea11).buildToken(
          'request_id',
          randomNo: _rnd5,
          tokenIdentifier: _tid(DateTime.utc(2004, 3, 28, 10, 0, 0)),
          pad: Pad(BitString.fromValue(0x0000, 16)),
        );
        ClearTamperConditionTokenGenerator(dk, ea11).generate(token);
        expect(token.tokenNo, equals('02455019196514047304'));
      });
    },
  );

  group(
    'STS_531_1_0_04 CTSA07 (SetMaximumPhasePowerUnbalanceLimit single)',
    () {
      test('step1: 28/03/2004 10:20:00, MPPUL=10 → 16135127146988830614', () {
        final dk = dkga04Misty1();
        final token = SetMaximumPhasePowerUnbalanceLimitTokenGenerator(dk, ea11)
            .buildToken(
              'request_id',
              randomNo: _rnd5,
              tokenIdentifier: _tid(DateTime.utc(2004, 3, 28, 10, 20, 0)),
              maximumPhasePowerUnbalanceLimit: MaximumPhasePowerUnbalanceLimit(
                10,
              ),
            );
        SetMaximumPhasePowerUnbalanceLimitTokenGenerator(
          dk,
          ea11,
        ).generate(token);
        expect(token.tokenNo, equals('16135127146988830614'));
      });
    },
  );

  group('STS_531_1_0_04 CTSA10 (TransferElectricityCredit amount sweep, '
      'electricity-only)', () {
    final cases = <List<dynamic>>[
      [DateTime.utc(2004, 4, 1, 0, 30, 0), 25.6, '63638916334124550935'],
      [DateTime.utc(2004, 4, 1, 0, 35, 0), 1638.3, '06736163174944595611'],
      [DateTime.utc(2004, 4, 1, 0, 40, 0), 1638.4, '45798100519745983712'],
      [DateTime.utc(2004, 4, 1, 0, 45, 0), 2000.0, '08362487434932116862'],
      [DateTime.utc(2004, 4, 1, 0, 50, 0), 18022.3, '33933484656539803471'],
      [DateTime.utc(2004, 4, 1, 0, 55, 0), 18022.4, '40075282658655256325'],
      [DateTime.utc(2004, 4, 1, 1, 44, 0), 181862.3, '00383912203740575049'],
      [DateTime.utc(2004, 4, 1, 1, 49, 0), 181862.4, '32272089791250978565'],
      [DateTime.utc(2004, 4, 1, 1, 54, 0), 1820162.4, '44964671935361377806'],
    ];

    for (var i = 0; i < cases.length; i++) {
      final issuedAt = cases[i][0] as DateTime;
      final amount = cases[i][1] as double;
      final expected = cases[i][2] as String;
      test('step${i + 1}: $amount kWh @ $issuedAt → $expected', () {
        final dk = dkga04Misty1();
        final token = TransferElectricityCreditToken('request_id')
          ..amountPurchased = Amount(amount)
          ..tokenIdentifier = _tid(issuedAt)
          ..randomNo = _rnd5;
        TransferElectricityCreditTokenGenerator(dk, ea11).generate(token);
        expect(token.tokenNo, equals(expected));
      });
    }
  });

  group('STS_531_1_0_04 CTSA13 (SetMaximumPhasePowerUnbalanceLimit sweep)', () {
    final cases = <List<dynamic>>[
      [DateTime.utc(2004, 4, 1, 8, 0, 0), 256, '23509767215559230954'],
      [DateTime.utc(2004, 4, 1, 8, 5, 0), 16383, '70247784567899484178'],
      [DateTime.utc(2004, 4, 1, 8, 10, 0), 16384, '36304916073545542570'],
      [DateTime.utc(2004, 4, 1, 8, 15, 0), 20000, '11066406403853302811'],
      [DateTime.utc(2004, 4, 1, 8, 20, 0), 180223, '25512033356036953640'],
      [DateTime.utc(2004, 4, 1, 8, 25, 0), 180224, '13785431682542358258'],
      [DateTime.utc(2004, 4, 1, 8, 30, 0), 1818623, '06889958680004063872'],
      [DateTime.utc(2004, 4, 1, 8, 35, 0), 1818624, '27410125084608663818'],
      [DateTime.utc(2004, 4, 1, 8, 40, 0), 18201624, '60786080230724485517'],
    ];

    for (var i = 0; i < cases.length; i++) {
      final issuedAt = cases[i][0] as DateTime;
      final mppul = cases[i][1] as int;
      final expected = cases[i][2] as String;
      test('step${i + 1}: MPPUL=$mppul @ $issuedAt → $expected', () {
        final dk = dkga04Misty1();
        final token = SetMaximumPhasePowerUnbalanceLimitTokenGenerator(dk, ea11)
            .buildToken(
              'request_id',
              randomNo: _rnd5,
              tokenIdentifier: _tid(issuedAt),
              maximumPhasePowerUnbalanceLimit: MaximumPhasePowerUnbalanceLimit(
                mppul,
              ),
            );
        SetMaximumPhasePowerUnbalanceLimitTokenGenerator(
          dk,
          ea11,
        ).generate(token);
        expect(token.tokenNo, equals(expected));
      });
    }
  });

  group('STS_531_1_0_04 CTSA14 (ClearCredit register sweep)', () {
    final cases = <List<dynamic>>[
      [DateTime.utc(2004, 4, 1, 9, 0, 0), 0x0, '06768431134031257922'],
      [DateTime.utc(2004, 4, 1, 9, 5, 0), 0xFFFF, '59338638600207707879'],
      [DateTime.utc(2004, 4, 1, 9, 10, 0), 0x4, '48872720007959408665'],
      [DateTime.utc(2004, 4, 1, 9, 15, 0), 0x5, '51810809087550125677'],
      [DateTime.utc(2004, 4, 1, 9, 20, 0), 0x6, '13848051316848177124'],
      [DateTime.utc(2004, 4, 1, 9, 25, 0), 0x7, '63506294564247105352'],
    ];

    for (var i = 0; i < cases.length; i++) {
      final issuedAt = cases[i][0] as DateTime;
      final reg = cases[i][1] as int;
      final expected = cases[i][2] as String;
      test('step${i + 1}: register=0x${reg.toRadixString(16)} @ $issuedAt → '
          '$expected', () {
        final dk = dkga04Misty1();
        final token = ClearCreditTokenGenerator(dk, ea11).buildToken(
          'request_id',
          randomNo: _rnd5,
          tokenIdentifier: _tid(issuedAt),
          register: Register(BitString.fromValue(reg, 16)),
        );
        ClearCreditTokenGenerator(dk, ea11).generate(token);
        expect(token.tokenNo, equals(expected));
      });
    }
  });

  group('STS_531_1_0_04 CTSA05 (4-section KCT via DKGA-04 + MISTY1)', () {
    DecoderKey mkDk({
      required BaseDate baseDate,
      required String ti,
      required KeyRevisionNumber krn,
      MeterPrimaryAccountNumber? pan,
    }) {
      return DecoderKeyGeneratorAlgorithm04(
        baseDate: baseDate,
        tariffIndex: TariffIndex(ti),
        supplyGroupCode: sgc04,
        keyType: keyType,
        keyRevisionNumber: krn,
        encryptionAlgorithm: ea11,
        meterPan: pan ?? pan04,
        vendingKey: vudk04,
      ).generate();
    }

    final kenhoFF = KeyExpiryNumberHighOrder(BitString.fromValue(0xF, 4));
    final kenloFF = KeyExpiryNumberLowOrder(BitString.fromValue(0xF, 4));

    // -------- step 1: initial TI=01/KRN=1, new TI=02/KRN=1, rollover=false
    test('step1 Set1st: initTI=01 → newTI=02 → 34812744915211133004', () {
      final initDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '01',
        krn: KeyRevisionNumber(1),
      );
      final newDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '02',
        krn: KeyRevisionNumber(1),
      );
      final tok = Set1stSectionDecoderKeyTokenGenerator(
        decoderKey: initDk,
        encryptionAlgorithm: ea11,
        keyExpiryNumberHighOrder: kenhoFF,
        keyRevisionNumber: KeyRevisionNumber(1),
        rolloverKeyChange: RolloverKeyChange.fromBool(false),
        keyType: keyType,
        newDecoderKey: newDk,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('34812744915211133004'));
    });

    test('step1 Set2nd: newTI=02 → 46903925208523674737', () {
      final initDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '01',
        krn: KeyRevisionNumber(1),
      );
      final newDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '02',
        krn: KeyRevisionNumber(1),
      );
      final tok = Set2ndSectionDecoderKeyTokenGenerator(
        decoderKey: initDk,
        encryptionAlgorithm: ea11,
        keyExpiryNumberLowOrder: kenloFF,
        tariffIndex: TariffIndex('02'),
        newDecoderKey: newDk,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('46903925208523674737'));
    });

    test('step1 Set3rd: SGC=123457 → 71464563847088610152', () {
      final initDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '01',
        krn: KeyRevisionNumber(1),
      );
      final newDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '02',
        krn: KeyRevisionNumber(1),
      );
      final tok = Set3rdSectionDecoderKeyTokenGenerator(
        decoderKey: initDk,
        encryptionAlgorithm: ea11,
        supplyGroupCode: sgc04,
        newDecoderKey: newDk,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('71464563847088610152'));
    });

    test('step1 Set4th: SGC=123457 → 67904239402617643990', () {
      final initDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '01',
        krn: KeyRevisionNumber(1),
      );
      final newDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '02',
        krn: KeyRevisionNumber(1),
      );
      final tok = Set4thSectionDecoderKeyTokenGenerator(
        decoderKey: initDk,
        encryptionAlgorithm: ea11,
        supplyGroupCode: sgc04,
        newDecoderKey: newDk,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('67904239402617643990'));
    });

    // -------- step 2: rollover=true, newKRN=4, newBaseDate=2014
    // initialKey stays 1993/01/KRN=1 (JUnit @Before reset)
    test('step2 Set1st (rollover=true, newKRN=4, 2014) → '
        '56493341861242437581', () {
      final initDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '01',
        krn: KeyRevisionNumber(1),
      );
      final newDk = mkDk(
        baseDate: BaseDate.date2014,
        ti: '02',
        krn: KeyRevisionNumber(4),
      );
      final tok = Set1stSectionDecoderKeyTokenGenerator(
        decoderKey: initDk,
        encryptionAlgorithm: ea11,
        keyExpiryNumberHighOrder: kenhoFF,
        keyRevisionNumber: KeyRevisionNumber(4),
        rolloverKeyChange: RolloverKeyChange.fromBool(true),
        keyType: keyType,
        newDecoderKey: newDk,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('56493341861242437581'));
    });

    test('step2 Set2nd (newKRN=4, 2014) → 51757380361191578258', () {
      final initDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '01',
        krn: KeyRevisionNumber(1),
      );
      final newDk = mkDk(
        baseDate: BaseDate.date2014,
        ti: '02',
        krn: KeyRevisionNumber(4),
      );
      final tok = Set2ndSectionDecoderKeyTokenGenerator(
        decoderKey: initDk,
        encryptionAlgorithm: ea11,
        keyExpiryNumberLowOrder: kenloFF,
        tariffIndex: TariffIndex('02'),
        newDecoderKey: newDk,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('51757380361191578258'));
    });

    // -------- step 3: alt PAN 000001…0082 (changeMeterPANValue), baseDate
    // reset to 1993 by @Before, newKRN reset to 1, newTI='02'
    test('step3 Set1st (altPan, TI=02, KRN=1) → 29594465524699505864', () {
      final altPan = MeterPrimaryAccountNumber.fromString(
        '000001000000000082',
        validate: MeterPanValidation.skip,
      );
      final initDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '01',
        krn: KeyRevisionNumber(1),
        pan: altPan,
      );
      final newDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '02',
        krn: KeyRevisionNumber(1),
        pan: altPan,
      );
      final tok = Set1stSectionDecoderKeyTokenGenerator(
        decoderKey: initDk,
        encryptionAlgorithm: ea11,
        keyExpiryNumberHighOrder: kenhoFF,
        keyRevisionNumber: KeyRevisionNumber(1),
        rolloverKeyChange: RolloverKeyChange.fromBool(false),
        keyType: keyType,
        newDecoderKey: newDk,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('29594465524699505864'));
    });

    test('step3 Set2nd (altPan, TI=02) → 09506536067814156547', () {
      final altPan = MeterPrimaryAccountNumber.fromString(
        '000001000000000082',
        validate: MeterPanValidation.skip,
      );
      final initDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '01',
        krn: KeyRevisionNumber(1),
        pan: altPan,
      );
      final newDk = mkDk(
        baseDate: BaseDate.date1993,
        ti: '02',
        krn: KeyRevisionNumber(1),
        pan: altPan,
      );
      final tok = Set2ndSectionDecoderKeyTokenGenerator(
        decoderKey: initDk,
        encryptionAlgorithm: ea11,
        keyExpiryNumberLowOrder: kenloFF,
        tariffIndex: TariffIndex('02'),
        newDecoderKey: newDk,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('09506536067814156547'));
    });
  });

  group('STS_531_1_0_04 CTSA19 (4-section KCT + TEC via DKGA-04 + MISTY1)', () {
    DecoderKey mkDk({
      required String ti,
      required KeyRevisionNumber krn,
      SupplyGroupCode? sgc,
    }) {
      return DecoderKeyGeneratorAlgorithm04(
        baseDate: BaseDate.date1993,
        tariffIndex: TariffIndex(ti),
        supplyGroupCode: sgc ?? sgc04,
        keyType: keyType,
        keyRevisionNumber: krn,
        encryptionAlgorithm: ea11,
        meterPan: pan04,
        vendingKey: vudk04,
      ).generate();
    }

    final kenhoFF = KeyExpiryNumberHighOrder(BitString.fromValue(0xF, 4));
    final kenloFF = KeyExpiryNumberLowOrder(BitString.fromValue(0xF, 4));

    void assertFiveSections({
      required DecoderKey initDk,
      required DecoderKey newDk,
      required KeyRevisionNumber newKrnForFirstSection,
      required TariffIndex tiForSecondSection,
      required SupplyGroupCode sgcForThirdSection,
      required SupplyGroupCode sgcForFourthSection,
      required KeyExpiryNumberHighOrder kenho,
      required KeyExpiryNumberLowOrder kenlo,
      required DateTime issuedAt,
      required String expected1st,
      required String expected2nd,
      required String expected3rd,
      required String expected4th,
      required String expectedTec,
    }) {
      final t1 = Set1stSectionDecoderKeyTokenGenerator(
        decoderKey: initDk,
        encryptionAlgorithm: ea11,
        keyExpiryNumberHighOrder: kenho,
        keyRevisionNumber: newKrnForFirstSection,
        rolloverKeyChange: RolloverKeyChange.fromBool(false),
        keyType: keyType,
        newDecoderKey: newDk,
      ).generateNew('request_id');
      expect(t1.tokenNo, equals(expected1st), reason: 'Set1st');

      final t2 = Set2ndSectionDecoderKeyTokenGenerator(
        decoderKey: initDk,
        encryptionAlgorithm: ea11,
        keyExpiryNumberLowOrder: kenlo,
        tariffIndex: tiForSecondSection,
        newDecoderKey: newDk,
      ).generateNew('request_id');
      expect(t2.tokenNo, equals(expected2nd), reason: 'Set2nd');

      final t3 = Set3rdSectionDecoderKeyTokenGenerator(
        decoderKey: initDk,
        encryptionAlgorithm: ea11,
        supplyGroupCode: sgcForThirdSection,
        newDecoderKey: newDk,
      ).generateNew('request_id');
      expect(t3.tokenNo, equals(expected3rd), reason: 'Set3rd');

      final t4 = Set4thSectionDecoderKeyTokenGenerator(
        decoderKey: initDk,
        encryptionAlgorithm: ea11,
        supplyGroupCode: sgcForFourthSection,
        newDecoderKey: newDk,
      ).generateNew('request_id');
      expect(t4.tokenNo, equals(expected4th), reason: 'Set4th');

      // TEC uses the NEW decoder key.
      final tecToken = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(0.1)
        ..tokenIdentifier = TokenIdentifier(
          BaseDate.date1993,
          timeOfIssue: issuedAt,
        )
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(newDk, ea11).generate(tecToken);
      expect(tecToken.tokenNo, equals(expectedTec), reason: 'TEC');
    }

    test('step1: initTI=01, newTI=02, KRN=1, KEN=255 @ 01/04/2004 10:00', () {
      final initDk = mkDk(ti: '01', krn: KeyRevisionNumber(1));
      final newDk = mkDk(ti: '02', krn: KeyRevisionNumber(1));
      assertFiveSections(
        initDk: initDk,
        newDk: newDk,
        newKrnForFirstSection: KeyRevisionNumber(1),
        tiForSecondSection: TariffIndex('02'),
        sgcForThirdSection: sgc04,
        sgcForFourthSection: sgc04,
        kenho: kenhoFF,
        kenlo: kenloFF,
        issuedAt: DateTime.utc(2004, 4, 1, 10, 0, 0),
        expected1st: '34812744915211133004',
        expected2nd: '46903925208523674737',
        expected3rd: '71464563847088610152',
        expected4th: '67904239402617643990',
        expectedTec: '52522044994700766563',
      );
    });

    test('step2: initTI=01/KRN=1, newTI=01/newKRN=2 @ 01/04/2004 10:10', () {
      final initDk = mkDk(ti: '01', krn: KeyRevisionNumber(1));
      final newDk = mkDk(ti: '01', krn: KeyRevisionNumber(2));
      assertFiveSections(
        initDk: initDk,
        newDk: newDk,
        newKrnForFirstSection: KeyRevisionNumber(2),
        tiForSecondSection: TariffIndex('01'),
        sgcForThirdSection: sgc04,
        sgcForFourthSection: sgc04,
        kenho: kenhoFF,
        kenlo: kenloFF,
        issuedAt: DateTime.utc(2004, 4, 1, 10, 10, 0),
        expected1st: '40937788669556693706',
        expected2nd: '55900126766830063715',
        expected3rd: '70168064023104948668',
        expected4th: '31051353433275215300',
        expectedTec: '10334212364124071208',
      );
    });

    test('step3: initKRN=2, newKRN=7, KEN=170 @ 01/04/2004 10:15', () {
      final initDk = mkDk(ti: '01', krn: KeyRevisionNumber(2));
      final newDk = mkDk(ti: '01', krn: KeyRevisionNumber(7));
      final kenho170 = KeyExpiryNumberHighOrder(BitString.fromValue(0xA, 4));
      final kenlo170 = KeyExpiryNumberLowOrder(BitString.fromValue(0xA, 4));
      assertFiveSections(
        initDk: initDk,
        newDk: newDk,
        newKrnForFirstSection: KeyRevisionNumber(7),
        tiForSecondSection: TariffIndex('01'),
        sgcForThirdSection: sgc04,
        sgcForFourthSection: sgc04,
        kenho: kenho170,
        kenlo: kenlo170,
        issuedAt: DateTime.utc(2004, 4, 1, 10, 15, 0),
        expected1st: '65626097193581652906',
        expected2nd: '45273086784967754458',
        expected3rd: '60343449063848563711',
        expected4th: '62570694794795906368',
        expectedTec: '06390659512322397973',
      );
    });

    test('step4: initSGC=123457, newSGC=123461, KRN=1 @ 01/04/2004 10:20', () {
      final newSgc = SupplyGroupCode('123461');
      final initDk = mkDk(ti: '01', krn: KeyRevisionNumber(1));
      final newDk = mkDk(ti: '01', krn: KeyRevisionNumber(1), sgc: newSgc);
      assertFiveSections(
        initDk: initDk,
        newDk: newDk,
        newKrnForFirstSection: KeyRevisionNumber(1),
        tiForSecondSection: TariffIndex('01'),
        sgcForThirdSection: newSgc,
        sgcForFourthSection: newSgc,
        kenho: kenhoFF,
        kenlo: kenloFF,
        issuedAt: DateTime.utc(2004, 4, 1, 10, 20, 0),
        expected1st: '14459740122691785207',
        expected2nd: '16084994560056931733',
        expected3rd: '38603700611597183668',
        expected4th: '07926972461094669048',
        expectedTec: '22571219105476013350',
      );
    });
  });
}
