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
// Class 1 vectors (CTSA02) are exercised below. CTSA11 (Class 1
// extended vectors) is not yet ported.
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
}
