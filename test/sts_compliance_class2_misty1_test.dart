// STS compliance test vectors ported from NectarAPI/tokens-service:
//   src/test/java/ke/co/nectar/token/domain/token/
//     STSComplianceTests_STS_531_1_0_04_CTSA0{1,3_4,6,7,9,12,13,14}.java
//
// SCOPE:
//   - DKGA-04 + EA11 (MISTY1) Class 0 electricity tokens and Class 2
//     management tokens. All vectors use the standard CTSA*_04 setup:
//       vudk = hex 'abababababababab949494949494949401234567' (20 B)
//       SGC  = '123457'         (note: 123457, *not* 123456)
//       TI   = '01', KRN = 1, KT = 2, KEN = 255
//       PAN  = '600727000000000009' (IIN=600727, IAIN=00000000000)
//       baseDate = 1993, EA = MISTY1
//
//   - Skipped vectors are documented inline:
//       * CTSA01_04 water/gas steps (2/3/6/7/10/11/14/15): electricity-only port.
//       * CTSA09_04 step3 multi-minute series: exercised as independent
//         vectors (matches the CTSA02 STA pattern).
//
// Also intentionally omitted from this batch:
//   * CTSA05_04 (4-section KCT) — deferred to a follow-up file; the
//     generator and round-trip already covered by
//     test/virtual_meter_test.dart.
//   * CTSA10_04 (Class 1) — Dart Class 1 encrypts, Java does not.
//   * CTSA16_04 (exception path) — Dart exception types differ.
//   * CTSA19_04 (mixed scenarios) — deferred.
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

MeterPrimaryAccountNumber _meterPan(String iin, String iain) =>
    MeterPrimaryAccountNumber(
      issuerIdentificationNumber: IssuerIdentificationNumber(iin),
      individualAccountIdentificationNumber:
          IndividualAccountIdentificationNumber(iain),
    );

DecoderKey _dkga04({
  required BaseDate baseDate,
  required KeyType keyType,
  required SupplyGroupCode sgc,
  required TariffIndex ti,
  required KeyRevisionNumber krn,
  required MeterPrimaryAccountNumber pan,
  required VendingUniqueDesKey vudk,
  required EncryptionAlgorithm ea,
}) => DecoderKeyGeneratorAlgorithm04(
  baseDate: baseDate,
  tariffIndex: ti,
  supplyGroupCode: sgc,
  keyType: keyType,
  keyRevisionNumber: krn,
  encryptionAlgorithm: ea,
  meterPan: pan,
  vendingKey: vudk,
).generate();

RandomNo get _rnd5 => RandomNo.fromInt(0x5);

void main() {
  // Shared CTSA*_04 setup matching the upstream @Before blocks.
  final keyType = KeyType(2);
  final sgc = SupplyGroupCode('123457');
  final ti = TariffIndex('01');
  final krn = KeyRevisionNumber(1);
  final vudk = VendingUniqueDesKey(
    _hex('abababababababab949494949494949401234567'),
  );
  final misty1 = Misty1EncryptionAlgorithm();

  final defaultPan = _meterPan('600727', '00000000000');

  // DKGA-04 derived key under the default 1993 baseDate. Reused by
  // every group except the time-shifted CTSA01_04 step9/step13.
  DecoderKey defaultDecoderKey() => _dkga04(
    baseDate: BaseDate.date1993,
    keyType: keyType,
    sgc: sgc,
    ti: ti,
    krn: krn,
    pan: defaultPan,
    vudk: vudk,
    ea: misty1,
  );

  TokenIdentifier tidAt(DateTime issuedAt, [BaseDate base = BaseDate.date1993]) =>
      TokenIdentifier(base, timeOfIssue: issuedAt);

  group('STS_531_1_0_04 CTSA01 (TransferElectricityCredit, MISTY1)', () {
    test('step1: PAN 600727000000000009, 01/03/2004 13:00:00, 0.1 kWh → '
        '59386323472137426967', () {
      final dk = defaultDecoderKey();
      final token = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(0.1)
        ..tokenIdentifier = tidAt(DateTime.utc(2004, 3, 1, 13, 0, 0))
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(dk, misty1).generate(token);
      expect(token.tokenNo, equals('59386323472137426967'));
    });

    test('step5: PAN 000001000000000082, 01/03/2004 13:20:00, 0.1 kWh → '
        '25453597494250138964', () {
      final pan = _meterPan('000001', '00000000008');
      final dk = _dkga04(
        baseDate: BaseDate.date1993,
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: krn,
        pan: pan,
        vudk: vudk,
        ea: misty1,
      );
      final token = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(0.1)
        ..tokenIdentifier = tidAt(DateTime.utc(2004, 3, 1, 13, 20, 0))
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(dk, misty1).generate(token);
      expect(token.tokenNo, equals('25453597494250138964'));
    });

    test('step9: baseDate=2014, KRN=4, 01/01/2014 08:00:00, 0.1 kWh → '
        '13444522537517076834', () {
      final dk = _dkga04(
        baseDate: BaseDate.date2014,
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: KeyRevisionNumber(4),
        pan: defaultPan,
        vudk: vudk,
        ea: misty1,
      );
      final token = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(0.1)
        ..tokenIdentifier =
            tidAt(DateTime.utc(2014, 1, 1, 8, 0, 0), BaseDate.date2014)
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(dk, misty1).generate(token);
      expect(token.tokenNo, equals('13444522537517076834'));
    });

    test('step13: baseDate=2035, KRN=5, 01/01/2035 08:00:00, 0.1 kWh → '
        '11907826947753213480', () {
      final dk = _dkga04(
        baseDate: BaseDate.date2035,
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: KeyRevisionNumber(5),
        pan: defaultPan,
        vudk: vudk,
        ea: misty1,
      );
      final token = TransferElectricityCreditToken('request_id')
        ..amountPurchased = Amount(0.1)
        ..tokenIdentifier =
            tidAt(DateTime.utc(2035, 1, 1, 8, 0, 0), BaseDate.date2035)
        ..randomNo = _rnd5;
      TransferElectricityCreditTokenGenerator(dk, misty1).generate(token);
      expect(token.tokenNo, equals('11907826947753213480'));
    });
  });

  group('STS_531_1_0_04 CTSA03 (SetMaximumPowerLimit, MISTY1)', () {
    test('step1: 28/03/2004 09:01:00, MPL=1000 → 26521936751055502278', () {
      final dk = defaultDecoderKey();
      final token = SetMaximumPowerLimitTokenGenerator(dk, misty1).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: tidAt(DateTime.utc(2004, 3, 28, 9, 1, 0)),
        maximumPowerLimit: MaximumPowerLimit(1000),
      );
      SetMaximumPowerLimitTokenGenerator(dk, misty1).generate(token);
      expect(token.tokenNo, equals('26521936751055502278'));
    });
  });

  group('STS_531_1_0_04 CTSA04 (ClearCredit, MISTY1)', () {
    test('step1: PAN 600727000000000009, 28/03/2004 09:15:00, reg=0xFFFF → '
        '59725289138639529749', () {
      final dk = defaultDecoderKey();
      final token = ClearCreditTokenGenerator(dk, misty1).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: tidAt(DateTime.utc(2004, 3, 28, 9, 15, 0)),
        register: Register(BitString.fromValue(0xFFFF, 16)),
      );
      ClearCreditTokenGenerator(dk, misty1).generate(token);
      expect(token.tokenNo, equals('59725289138639529749'));
    });

    test('step2: PAN 000001000000000082, 28/03/2004 09:16:00, reg=0xFFFF → '
        '43917986274716482997', () {
      final pan = _meterPan('000001', '00000000008');
      final dk = _dkga04(
        baseDate: BaseDate.date1993,
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: krn,
        pan: pan,
        vudk: vudk,
        ea: misty1,
      );
      final token = ClearCreditTokenGenerator(dk, misty1).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: tidAt(DateTime.utc(2004, 3, 28, 9, 16, 0)),
        register: Register(BitString.fromValue(0xFFFF, 16)),
      );
      ClearCreditTokenGenerator(dk, misty1).generate(token);
      expect(token.tokenNo, equals('43917986274716482997'));
    });
  });

  group('STS_531_1_0_04 CTSA06 (ClearTamperCondition, MISTY1)', () {
    test('step1: 28/03/2004 10:00:00, pad=0 → 02455019196514047304', () {
      final dk = defaultDecoderKey();
      final token = ClearTamperConditionTokenGenerator(dk, misty1).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: tidAt(DateTime.utc(2004, 3, 28, 10, 0, 0)),
        pad: Pad(BitString.fromValue(0, 16)),
      );
      ClearTamperConditionTokenGenerator(dk, misty1).generate(token);
      expect(token.tokenNo, equals('02455019196514047304'));
    });
  });

  group('STS_531_1_0_04 CTSA07 (SetMaximumPhasePowerUnbalanceLimit, MISTY1)',
      () {
    test('step1: 28/03/2004 10:20:00, MPPUL=10 → 16135127146988830614', () {
      final dk = defaultDecoderKey();
      final token =
          SetMaximumPhasePowerUnbalanceLimitTokenGenerator(dk, misty1)
              .buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: tidAt(DateTime.utc(2004, 3, 28, 10, 20, 0)),
        maximumPhasePowerUnbalanceLimit:
            MaximumPhasePowerUnbalanceLimit(10),
      );
      SetMaximumPhasePowerUnbalanceLimitTokenGenerator(dk, misty1)
          .generate(token);
      expect(token.tokenNo, equals('16135127146988830614'));
    });
  });

  group('STS_531_1_0_04 CTSA09 (ClearCredit, MISTY1)', () {
    String genCc(DateTime issuedAt) {
      final dk = defaultDecoderKey();
      final token = ClearCreditTokenGenerator(dk, misty1).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: tidAt(issuedAt),
        register: Register(BitString.fromValue(0xFFFF, 16)),
      );
      ClearCreditTokenGenerator(dk, misty1).generate(token);
      return token.tokenNo;
    }

    test('step1: 29/03/2004 00:00:00 → 09791211239166238461', () {
      expect(genCc(DateTime.utc(2004, 3, 29, 0, 0, 0)),
          equals('09791211239166238461'));
    });
    test('step2: 29/03/2004 00:01:00 → 18070818655140104337', () {
      expect(genCc(DateTime.utc(2004, 3, 29, 0, 1, 0)),
          equals('18070818655140104337'));
    });
    test('step3 first-minute: 29/03/2004 00:03:00 → 59463760341829598722',
        () {
      expect(genCc(DateTime.utc(2004, 3, 29, 0, 3, 0)),
          equals('59463760341829598722'));
    });
    test('step3 second-minute: 29/03/2004 00:04:00 → 49512072598296997272',
        () {
      expect(genCc(DateTime.utc(2004, 3, 29, 0, 4, 0)),
          equals('49512072598296997272'));
    });
    test('step3 third-minute: 29/03/2004 00:05:00 → 59135803195278393273',
        () {
      expect(genCc(DateTime.utc(2004, 3, 29, 0, 5, 0)),
          equals('59135803195278393273'));
    });
  });

  group('STS_531_1_0_04 CTSA12 (SetMaximumPowerLimit, MISTY1)', () {
    String genMpl(DateTime issuedAt, int mpl) {
      final dk = defaultDecoderKey();
      final token = SetMaximumPowerLimitTokenGenerator(dk, misty1).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: tidAt(issuedAt),
        maximumPowerLimit: MaximumPowerLimit(mpl),
      );
      SetMaximumPowerLimitTokenGenerator(dk, misty1).generate(token);
      return token.tokenNo;
    }

    test('step1: 01/04/2004 07:00:00, MPL=256 → 58601433826945463485', () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 0, 0), 256),
          equals('58601433826945463485'));
    });
    test('step2: 01/04/2004 07:05:00, MPL=16383 → 13997395479415026219', () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 5, 0), 16383),
          equals('13997395479415026219'));
    });
    test('step3: 01/04/2004 07:10:00, MPL=16384 → 18037738085263294820', () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 10, 0), 16384),
          equals('18037738085263294820'));
    });
    test('step4: 01/04/2004 07:15:00, MPL=20000 → 06738975074638745925', () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 15, 0), 20000),
          equals('06738975074638745925'));
    });
    test('step5: 01/04/2004 07:20:00, MPL=180223 → 66354091567942569601',
        () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 20, 0), 180223),
          equals('66354091567942569601'));
    });
    test('step6: 01/04/2004 07:25:00, MPL=180224 → 62853351521017859877',
        () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 25, 0), 180224),
          equals('62853351521017859877'));
    });
    test('step7: 01/04/2004 07:30:00, MPL=1818623 → 40984149905900332649',
        () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 30, 0), 1818623),
          equals('40984149905900332649'));
    });
    test('step8: 01/04/2004 07:35:00, MPL=1818624 → 26882838654580901052',
        () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 35, 0), 1818624),
          equals('26882838654580901052'));
    });
    test('step9: 01/04/2004 07:40:00, MPL=18201624 → 29255956459122361629',
        () {
      expect(genMpl(DateTime.utc(2004, 4, 1, 7, 40, 0), 18201624),
          equals('29255956459122361629'));
    });
  });

  group('STS_531_1_0_04 CTSA13 (SetMaximumPhasePowerUnbalanceLimit, MISTY1)',
      () {
    String genMppul(DateTime issuedAt, int v) {
      final dk = defaultDecoderKey();
      final token =
          SetMaximumPhasePowerUnbalanceLimitTokenGenerator(dk, misty1)
              .buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: tidAt(issuedAt),
        maximumPhasePowerUnbalanceLimit: MaximumPhasePowerUnbalanceLimit(v),
      );
      SetMaximumPhasePowerUnbalanceLimitTokenGenerator(dk, misty1)
          .generate(token);
      return token.tokenNo;
    }

    test('step1: 01/04/2004 08:00:00, MPPUL=256 → 23509767215559230954', () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 0, 0), 256),
          equals('23509767215559230954'));
    });
    test('step2: 01/04/2004 08:05:00, MPPUL=16383 → 70247784567899484178',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 5, 0), 16383),
          equals('70247784567899484178'));
    });
    test('step3: 01/04/2004 08:10:00, MPPUL=16384 → 36304916073545542570',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 10, 0), 16384),
          equals('36304916073545542570'));
    });
    test('step4: 01/04/2004 08:15:00, MPPUL=20000 → 11066406403853302811',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 15, 0), 20000),
          equals('11066406403853302811'));
    });
    test('step5: 01/04/2004 08:20:00, MPPUL=180223 → 25512033356036953640',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 20, 0), 180223),
          equals('25512033356036953640'));
    });
    test('step6: 01/04/2004 08:25:00, MPPUL=180224 → 13785431682542358258',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 25, 0), 180224),
          equals('13785431682542358258'));
    });
    test('step7: 01/04/2004 08:30:00, MPPUL=1818623 → 06889958680004063872',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 30, 0), 1818623),
          equals('06889958680004063872'));
    });
    test('step8: 01/04/2004 08:35:00, MPPUL=1818624 → 27410125084608663818',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 35, 0), 1818624),
          equals('27410125084608663818'));
    });
    test('step9: 01/04/2004 08:40:00, MPPUL=18201624 → 60786080230724485517',
        () {
      expect(genMppul(DateTime.utc(2004, 4, 1, 8, 40, 0), 18201624),
          equals('60786080230724485517'));
    });
  });

  group('STS_531_1_0_04 CTSA14 (ClearCredit register values, MISTY1)', () {
    String genCc(DateTime issuedAt, int reg) {
      final dk = defaultDecoderKey();
      final token = ClearCreditTokenGenerator(dk, misty1).buildToken(
        'request_id',
        randomNo: _rnd5,
        tokenIdentifier: tidAt(issuedAt),
        register: Register(BitString.fromValue(reg, 16)),
      );
      ClearCreditTokenGenerator(dk, misty1).generate(token);
      return token.tokenNo;
    }

    test('step1: 01/04/2004 09:00:00, reg=0x0000 → 06768431134031257922',
        () {
      expect(genCc(DateTime.utc(2004, 4, 1, 9, 0, 0), 0x0000),
          equals('06768431134031257922'));
    });
    test('step2: 01/04/2004 09:05:00, reg=0xFFFF → 59338638600207707879',
        () {
      expect(genCc(DateTime.utc(2004, 4, 1, 9, 5, 0), 0xFFFF),
          equals('59338638600207707879'));
    });
    test('step3: 01/04/2004 09:10:00, reg=0x0004 → 48872720007959408665',
        () {
      expect(genCc(DateTime.utc(2004, 4, 1, 9, 10, 0), 0x0004),
          equals('48872720007959408665'));
    });
    test('step4: 01/04/2004 09:15:00, reg=0x0005 → 51810809087550125677',
        () {
      expect(genCc(DateTime.utc(2004, 4, 1, 9, 15, 0), 0x0005),
          equals('51810809087550125677'));
    });
    test('step5: 01/04/2004 09:20:00, reg=0x0006 → 13848051316848177124',
        () {
      expect(genCc(DateTime.utc(2004, 4, 1, 9, 20, 0), 0x0006),
          equals('13848051316848177124'));
    });
    test('step6: 01/04/2004 09:25:00, reg=0x0007 → 63506294564247105352',
        () {
      expect(genCc(DateTime.utc(2004, 4, 1, 9, 25, 0), 0x0007),
          equals('63506294564247105352'));
    });
  });
}
