// STS compliance test vectors ported from NectarAPI/tokens-service:
//   src/test/java/ke/co/nectar/token/domain/token/
//     STSComplianceTests_STS_531_1_0_02_CTSA0{3,4,5,6,7,9,12,13,14}.java
//
// SCOPE:
//   - DKGA-02 + EA07 (STA) Class 2 management tokens and Key Change
//     Tokens (1st/2nd section). All vectors use the standard CTSA
//     setup: vudk=hex 'abababababababab', SGC='123456', TI='01',
//     KRN=1, KT=2, KEN=255, PAN='600727000000000009' unless noted.
//
//   - Skipped vectors are documented inline:
//       * CTSA09 step3 multi-minute series: relies on a vending-side
//         TID rolling counter that the Dart port leaves to callers.
//         The three time-shifted re-issues are exercised as
//         independent vectors instead.
//
//   - The `KeyExpiryNumber` argument that the Java generators take is
//     not present in the Dart port. See `sts_compliance_test.dart`
//     header — KEN is not mixed into the Class 2 data block.
//
// Class 1 vectors (CTSA02, CTSA11) are intentionally omitted: the
// Dart Class 1 generator encrypts the data block while the Java
// upstream emits it in the clear.
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
  individualAccountIdentificationNumber:
      IndividualAccountIdentificationNumber(iainStr),
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
    test('step1: 28/03/2004 09:15:00, register=0xFFFF → 29511990995826640868',
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
    });

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

    DecoderKey initialKeyFor(String tariff, {String iin = '600727',
        String iain = '00000000000'}) =>
        _dkga02(
          keyType: keyType,
          sgc: sgc,
          ti: TariffIndex(tariff),
          krn: krn,
          iinStr: iin,
          iainStr: iain,
          vudk: vudk,
        );

    test('step1 1st section: initialTI=01 → newTI=02 → 51638423060042734509',
        () {
      final initialKey = initialKeyFor('01');
      final newKey = initialKeyFor('02');
      final tok = Set1stSectionDecoderKeyTokenGenerator(
        decoderKey: initialKey,
        encryptionAlgorithm: ea07,
        keyExpiryNumberHighOrder:
            KeyExpiryNumberHighOrder(BitString.fromValue(0xF, 4)),
        keyRevisionNumber: krn,
        rolloverKeyChange: RolloverKeyChange.fromBool(false),
        keyType: keyType,
        newDecoderKey: newKey,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('51638423060042734509'));
    });

    test('step1 2nd section: newTI=02, KENLO=0xF → 15361891762113502242', () {
      final initialKey = initialKeyFor('01');
      final newKey = initialKeyFor('02');
      final tok = Set2ndSectionDecoderKeyTokenGenerator(
        decoderKey: initialKey,
        encryptionAlgorithm: ea07,
        keyExpiryNumberLowOrder:
            KeyExpiryNumberLowOrder(BitString.fromValue(0xF, 4)),
        tariffIndex: TariffIndex('02'),
        newDecoderKey: newKey,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('15361891762113502242'));
    });

    test('step2 1st section: initialTI=02 → newTI=01 → 26553210520543055412',
        () {
      // "flipped" — initial generator now uses newTariffIndex=02, new
      // generator uses initialTariffIndex=01.
      final initialKey = initialKeyFor('02');
      final newKey = initialKeyFor('01');
      final tok = Set1stSectionDecoderKeyTokenGenerator(
        decoderKey: initialKey,
        encryptionAlgorithm: ea07,
        keyExpiryNumberHighOrder:
            KeyExpiryNumberHighOrder(BitString.fromValue(0xF, 4)),
        keyRevisionNumber: krn,
        rolloverKeyChange: RolloverKeyChange.fromBool(false),
        keyType: keyType,
        newDecoderKey: newKey,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('26553210520543055412'));
    });

    test('step2 2nd section: flipped, newTariffIndex=01 → '
        '00943705441908264439', () {
      final initialKey = initialKeyFor('02');
      final newKey = initialKeyFor('01');
      final tok = Set2ndSectionDecoderKeyTokenGenerator(
        decoderKey: initialKey,
        encryptionAlgorithm: ea07,
        keyExpiryNumberLowOrder:
            KeyExpiryNumberLowOrder(BitString.fromValue(0xF, 4)),
        tariffIndex: TariffIndex('01'),
        newDecoderKey: newKey,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('00943705441908264439'));
    });

    test('step3 1st section: PAN=000001000000000082 → 36495265416911568628',
        () {
      final initialKey = initialKeyFor('01',
          iin: '000001', iain: '00000000008');
      final newKey = initialKeyFor('02',
          iin: '000001', iain: '00000000008');
      final tok = Set1stSectionDecoderKeyTokenGenerator(
        decoderKey: initialKey,
        encryptionAlgorithm: ea07,
        keyExpiryNumberHighOrder:
            KeyExpiryNumberHighOrder(BitString.fromValue(0xF, 4)),
        keyRevisionNumber: krn,
        rolloverKeyChange: RolloverKeyChange.fromBool(false),
        keyType: keyType,
        newDecoderKey: newKey,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('36495265416911568628'));
    });

    test('step3 2nd section: PAN=000001000000000082 → 35908059266238070883',
        () {
      final initialKey = initialKeyFor('01',
          iin: '000001', iain: '00000000008');
      final newKey = initialKeyFor('02',
          iin: '000001', iain: '00000000008');
      final tok = Set2ndSectionDecoderKeyTokenGenerator(
        decoderKey: initialKey,
        encryptionAlgorithm: ea07,
        keyExpiryNumberLowOrder:
            KeyExpiryNumberLowOrder(BitString.fromValue(0xF, 4)),
        tariffIndex: TariffIndex('02'),
        newDecoderKey: newKey,
      ).generateNew('request_id');
      expect(tok.tokenNo, equals('35908059266238070883'));
    });
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
        maximumPhasePowerUnbalanceLimit:
            MaximumPhasePowerUnbalanceLimit(10),
      );
      SetMaximumPhasePowerUnbalanceLimitTokenGenerator(dk, ea07)
          .generate(token);
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

    test('step3 single token: 29/03/2004 00:03:00 → 43348834939937913498',
        () {
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
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 0, 0), 256),
          equals('41932934023937597177'));
    });
    test('step2: 01/04/2004 07:05:00, MPL=16383 → 39962525051716972228', () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 5, 0), 16383),
          equals('39962525051716972228'));
    });
    test('step3: 01/04/2004 07:10:00, MPL=16384 → 49726922948713857933', () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 10, 0), 16384),
          equals('49726922948713857933'));
    });
    test('step4: 01/04/2004 07:15:00, MPL=20000 → 49240429350369491663', () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 15, 0), 20000),
          equals('49240429350369491663'));
    });
    test('step5: 01/04/2004 07:20:00, MPL=180223 → 59901462710025767433', () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 20, 0), 180223),
          equals('59901462710025767433'));
    });
    test('step6: 01/04/2004 07:25:00, MPL=180224 → 19230023168014606006', () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 25, 0), 180224),
          equals('19230023168014606006'));
    });
    test('step7: 01/04/2004 07:30:00, MPL=1818623 → 15202793104399278539',
        () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 30, 0), 1818623),
          equals('15202793104399278539'));
    });
    test('step8: 01/04/2004 07:35:00, MPL=1818624 → 39289527337368539951',
        () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 35, 0), 1818624),
          equals('39289527337368539951'));
    });
    test('step9: 01/04/2004 07:40:00, MPL=18201624 → 64902502692705103624',
        () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 40, 0), 18201624),
          equals('64902502692705103624'));
    });
  });

  group('STS_531_1_0_02 CTSA13 (SetMaximumPhasePowerUnbalanceLimit)', () {
    DecoderKey dk() => defaultDecoderKey();

    String genMppul(DateTime issuedAt, int v) {
      final token = SetMaximumPhasePowerUnbalanceLimitTokenGenerator(
        dk(),
        ea07,
      ).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: _tid(issuedAt),
        maximumPhasePowerUnbalanceLimit: MaximumPhasePowerUnbalanceLimit(v),
      );
      SetMaximumPhasePowerUnbalanceLimitTokenGenerator(dk(), ea07)
          .generate(token);
      return token.tokenNo;
    }

    test('step1: 01/04/2004 08:00:00, MPPUL=256 → 31529222328157245680', () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 0, 0), 256),
          equals('31529222328157245680'));
    });
    test('step2: 01/04/2004 08:05:00, MPPUL=16383 → 73693330413053816261',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 5, 0), 16383),
          equals('73693330413053816261'));
    });
    test('step3: 01/04/2004 08:10:00, MPPUL=16384 → 54550534704168942701',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 10, 0), 16384),
          equals('54550534704168942701'));
    });
    test('step4: 01/04/2004 08:15:00, MPPUL=20000 → 59764600311380323340',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 15, 0), 20000),
          equals('59764600311380323340'));
    });
    test('step5: 01/04/2004 08:20:00, MPPUL=180223 → 40345762458084906193',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 20, 0), 180223),
          equals('40345762458084906193'));
    });
    test('step6: 01/04/2004 08:25:00, MPPUL=180224 → 66940669945224810632',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 25, 0), 180224),
          equals('66940669945224810632'));
    });
    test('step7: 01/04/2004 08:30:00, MPPUL=1818623 → 39456295247583474882',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 30, 0), 1818623),
          equals('39456295247583474882'));
    });
    test('step8: 01/04/2004 08:35:00, MPPUL=1818624 → 71498975780521030688',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 35, 0), 1818624),
          equals('71498975780521030688'));
    });
    test('step9: 01/04/2004 08:40:00, MPPUL=18201624 → 57078032150370797843',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 40, 0), 18201624),
          equals('57078032150370797843'));
    });
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

    test('step1: 01/04/2004 09:00:00, reg=0x0000 → 24406351748405762287',
        () {
      expect(genCc(DateTime.utc(2004, 4, 1, 9, 0, 0), 0x0000),
          equals('24406351748405762287'));
    });
    test('step2: 01/04/2004 09:05:00, reg=0xFFFF → 48263195037886996694',
        () {
      expect(genCc(DateTime.utc(2004, 4, 1, 9, 5, 0), 0xFFFF),
          equals('48263195037886996694'));
    });
    test('step3: 01/04/2004 09:10:00, reg=0x0004 → 17696673116286267663',
        () {
      expect(genCc(DateTime.utc(2004, 4, 1, 9, 10, 0), 0x0004),
          equals('17696673116286267663'));
    });
    test('step4: 01/04/2004 09:15:00, reg=0x0005 → 47739859634763202644',
        () {
      expect(genCc(DateTime.utc(2004, 4, 1, 9, 15, 0), 0x0005),
          equals('47739859634763202644'));
    });
    test('step5: 01/04/2004 09:20:00, reg=0x0006 → 23456948011089526127',
        () {
      expect(genCc(DateTime.utc(2004, 4, 1, 9, 20, 0), 0x0006),
          equals('23456948011089526127'));
    });
    test('step6: 01/04/2004 09:25:00, reg=0x0007 → 51867282903899304686',
        () {
      expect(genCc(DateTime.utc(2004, 4, 1, 9, 25, 0), 0x0007),
          equals('51867282903899304686'));
    });
  });
}
