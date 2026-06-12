// STS compliance test vectors ported from NectarAPI/tokens-service:
//   src/test/java/ke/co/nectar/token/domain/token/
//     STSComplianceTests_STS_531_1_0_02_CTSA01.java       (DKGA-02 + EA07/STA)
//     STSComplianceTests_STS_531_1_0_04_CTSA01.java       (DKGA-04 + EA11/MISTY1)
//   src/test/java/ke/co/nectar/token/generators/tokensgenerator/nativetoken/
//     class0/TransferElectricityCreditTokenGeneratorTest.java
//
// SCOPE:
//   - CTSA01 (DKGA-02 + EA07/STA): TransferElectricity (step1, step2),
//     TransferWater (step3, step4), TransferGas (step5, step6).
//   - CTSA01 (DKGA-04 + EA11/MISTY1): the water/gas-relevant subset
//     (step2/3/6/7/10/11/14/15) — these are the steps that exercise
//     the new TransferWaterCreditToken / TransferGasCreditToken
//     classes and the Class 0 subclass-nibble dispatch.
//   - The `KeyExpiryNumber` argument that the Java generators take is
//     not present in our Dart port. Inspection of the Java source shows
//     KEN is stored on the generator but is NOT mixed into the data
//     block (`crc || amount || tid || rnd || sub` — KEN absent) and
//     not used by DKGA-02 / DKGA-04 key derivation. So omitting KEN in
//     our port produces identical tokens.
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

String _hexOf(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

String _generateElectricityToken({
  required DecoderKey decoderKey,
  required EncryptionAlgorithm encryptionAlgorithm,
  required DateTime issuedAt,
  required BaseDate baseDate,
  required RandomNo randomNo,
  required Amount amount,
  String requestId = 'request_id',
}) {
  final token = TransferElectricityCreditToken(requestId)
    ..amountPurchased = amount
    ..tokenIdentifier = TokenIdentifier(baseDate, timeOfIssue: issuedAt)
    ..randomNo = randomNo;
  TransferElectricityCreditTokenGenerator(
    decoderKey,
    encryptionAlgorithm,
  ).generate(token);
  return token.tokenNo;
}

String _generateWaterToken({
  required DecoderKey decoderKey,
  required EncryptionAlgorithm encryptionAlgorithm,
  required DateTime issuedAt,
  required BaseDate baseDate,
  required RandomNo randomNo,
  required Amount amount,
  String requestId = 'request_id',
}) {
  final token = TransferWaterCreditToken(requestId)
    ..amountPurchased = amount
    ..tokenIdentifier = TokenIdentifier(baseDate, timeOfIssue: issuedAt)
    ..randomNo = randomNo;
  TransferWaterCreditTokenGenerator(
    decoderKey,
    encryptionAlgorithm,
  ).generate(token);
  return token.tokenNo;
}

String _generateGasToken({
  required DecoderKey decoderKey,
  required EncryptionAlgorithm encryptionAlgorithm,
  required DateTime issuedAt,
  required BaseDate baseDate,
  required RandomNo randomNo,
  required Amount amount,
  String requestId = 'request_id',
}) {
  final token = TransferGasCreditToken(requestId)
    ..amountPurchased = amount
    ..tokenIdentifier = TokenIdentifier(baseDate, timeOfIssue: issuedAt)
    ..randomNo = randomNo;
  TransferGasCreditTokenGenerator(
    decoderKey,
    encryptionAlgorithm,
  ).generate(token);
  return token.tokenNo;
}

DecoderKey _dkga02({
  required KeyType keyType,
  required SupplyGroupCode sgc,
  required TariffIndex ti,
  required KeyRevisionNumber krn,
  required String iinStr,
  required String iainStr,
  required VendingUniqueDesKey vudk,
}) {
  return DecoderKeyGeneratorAlgorithm02(
    keyType: keyType,
    supplyGroupCode: sgc,
    tariffIndex: ti,
    keyRevisionNumber: krn,
    issuerIdentificationNumber: IssuerIdentificationNumber(iinStr),
    individualAccountIdentificationNumber:
        IndividualAccountIdentificationNumber(iainStr),
    vendingKey: vudk,
  ).generate();
}

DecoderKey _dkga04Misty1({
  required BaseDate baseDate,
  required KeyType keyType,
  required SupplyGroupCode sgc,
  required TariffIndex ti,
  required KeyRevisionNumber krn,
  required String iinStr,
  required String iainStr,
  required VendingCommonDesKey vk,
}) {
  return DecoderKeyGeneratorAlgorithm04(
    baseDate: baseDate,
    tariffIndex: ti,
    supplyGroupCode: sgc,
    keyType: keyType,
    keyRevisionNumber: krn,
    encryptionAlgorithm: Misty1EncryptionAlgorithm(),
    meterPan: MeterPrimaryAccountNumber(
      issuerIdentificationNumber: IssuerIdentificationNumber(iinStr),
      individualAccountIdentificationNumber:
          IndividualAccountIdentificationNumber(iainStr),
    ),
    vendingKey: vk,
  ).generate();
}

void main() {
  group('STS_531_1_0_02 CTSA01 (DKGA-02 + EA07 / STA)', () {
    // Common setup from upstream @Before:
    //   keyExpiryNumber = 255  (unused in our port — see file header)
    //   keyType        = KeyType(2)
    //   supplyGroupCode = "123456"
    //   tariffIndex     = "01"
    //   keyRevisionNumber = 1
    //   vudk           = VendingUniqueDESKey(hex "abababababababab")
    final keyType = KeyType(2);
    final sgc = SupplyGroupCode('123456');
    final ti = TariffIndex('01');
    final krn = KeyRevisionNumber(1);
    final vudk = VendingUniqueDesKey(_hex('abababababababab'));
    final ea07 = StandardTransferAlgorithm();

    test('step1: PAN 600727000000000009, 01/03/2004 13:55:00', () {
      // PAN 600727000000000009 → IIN=600727, IAIN=00000000000, check=9.
      final decoderKey = _dkga02(
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: krn,
        iinStr: '600727',
        iainStr: '00000000000',
        vudk: vudk,
      );

      expect(
        _hexOf(decoderKey.keyData),
        equals('6ff35b9d1f3453e6'),
        reason: 'DKGA-02 derived key must match STS6 expected value',
      );

      final tokenNo = _generateElectricityToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea07,
        issuedAt: DateTime.utc(2004, 3, 1, 13, 55, 0),
        baseDate: BaseDate.date1993,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('23716100501183194197'));
    });

    test('step2: PAN 000001000000000082, 01/03/2004 14:00:00', () {
      // PAN 000001000000000082 → IIN=000001, IAIN=00000000008, check=2.
      final decoderKey = _dkga02(
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: krn,
        iinStr: '000001',
        iainStr: '00000000008',
        vudk: vudk,
      );

      final tokenNo = _generateElectricityToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea07,
        issuedAt: DateTime.utc(2004, 3, 1, 14, 0, 0),
        baseDate: BaseDate.date1993,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('67206107716095682372'));
    });

    test('step3 (water): PAN 600727000000000009, 01/03/2004 14:05:00', () {
      final decoderKey = _dkga02(
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: krn,
        iinStr: '600727',
        iainStr: '00000000000',
        vudk: vudk,
      );
      final tokenNo = _generateWaterToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea07,
        issuedAt: DateTime.utc(2004, 3, 1, 14, 5, 0),
        baseDate: BaseDate.date1993,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('42502136492215507402'));
    });

    test('step4 (water): PAN 000001000000000082, 01/03/2004 14:10:00', () {
      final decoderKey = _dkga02(
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: krn,
        iinStr: '000001',
        iainStr: '00000000008',
        vudk: vudk,
      );
      final tokenNo = _generateWaterToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea07,
        issuedAt: DateTime.utc(2004, 3, 1, 14, 10, 0),
        baseDate: BaseDate.date1993,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('09109691696351271646'));
    });

    test('step5 (gas): PAN 600727000000000009, 01/03/2004 14:15:00', () {
      final decoderKey = _dkga02(
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: krn,
        iinStr: '600727',
        iainStr: '00000000000',
        vudk: vudk,
      );
      final tokenNo = _generateGasToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea07,
        issuedAt: DateTime.utc(2004, 3, 1, 14, 15, 0),
        baseDate: BaseDate.date1993,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('67586531586639825066'));
    });

    test('step6 (gas): PAN 000001000000000082, 01/03/2004 14:20:00', () {
      final decoderKey = _dkga02(
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: krn,
        iinStr: '000001',
        iainStr: '00000000008',
        vudk: vudk,
      );
      final tokenNo = _generateGasToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea07,
        issuedAt: DateTime.utc(2004, 3, 1, 14, 20, 0),
        baseDate: BaseDate.date1993,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('35758660990071466853'));
    });
  });

  group('TransferElectricityCreditTokenGenerator (direct decoder key)', () {
    // Upstream:
    //   src/test/java/ke/co/nectar/token/generators/tokensgenerator/
    //   nativetoken/class0/TransferElectricityCreditTokenGeneratorTest.java
    test('decoderKey 8967 45f3 de12 bc0a, 25/03/1996 13:55:22, '
        '25.6 kWh, RND=0xB → 29054347139309851356', () {
      final decoderKey = DecoderKey(_hex('896745f3de12bc0a'));
      final tokenNo = _generateElectricityToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: StandardTransferAlgorithm(),
        issuedAt: DateTime.utc(1996, 3, 25, 13, 55, 22),
        baseDate: BaseDate.date1993,
        randomNo: RandomNo.fromInt(0xB),
        amount: Amount(25.6),
      );
      expect(tokenNo, equals('29054347139309851356'));
    });
  });

  group('STS_531_1_0_04 CTSA01 (DKGA-04 + EA11 / MISTY1)', () {
    // Upstream:
    //   STSComplianceTests_STS_531_1_0_04_CTSA01.java
    //
    // Common @Before:
    //   keyExpiryNumber = 255  (unused in our port — see file header)
    //   keyType         = KeyType(2)
    //   supplyGroupCode = "123457"  (note: differs from STA's 123456)
    //   tariffIndex     = "01"
    //   vudk            = 160-bit VendingKey
    //                     "abababababababab949494949494949401234567"
    //   baseDate        = 1993 (overridden in step9..15)
    //
    // SCOPE: water/gas-relevant steps only
    //   (step2, step3, step6, step7, step10, step11, step14, step15).
    final keyType = KeyType(2);
    final sgc = SupplyGroupCode('123457');
    final ti = TariffIndex('01');
    final vk = VendingCommonDesKey(
      _hex('abababababababab949494949494949401234567'),
    );
    final ea11 = Misty1EncryptionAlgorithm();

    test('step2 (water): PAN 600727000000000009, 01/03/2004 13:05:00', () {
      final decoderKey = _dkga04Misty1(
        baseDate: BaseDate.date1993,
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: KeyRevisionNumber(1),
        iinStr: '600727',
        iainStr: '00000000000',
        vk: vk,
      );
      final tokenNo = _generateWaterToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea11,
        issuedAt: DateTime.utc(2004, 3, 1, 13, 5, 0),
        baseDate: BaseDate.date1993,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('47186281207955155808'));
    });

    test('step3 (gas): PAN 600727000000000009, 01/03/2004 13:10:00', () {
      final decoderKey = _dkga04Misty1(
        baseDate: BaseDate.date1993,
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: KeyRevisionNumber(1),
        iinStr: '600727',
        iainStr: '00000000000',
        vk: vk,
      );
      final tokenNo = _generateGasToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea11,
        issuedAt: DateTime.utc(2004, 3, 1, 13, 10, 0),
        baseDate: BaseDate.date1993,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('52059556253782091701'));
    });

    test('step6 (water): PAN 000001000000000082, 01/03/2004 13:25:00', () {
      final decoderKey = _dkga04Misty1(
        baseDate: BaseDate.date1993,
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: KeyRevisionNumber(1),
        iinStr: '000001',
        iainStr: '00000000008',
        vk: vk,
      );
      final tokenNo = _generateWaterToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea11,
        issuedAt: DateTime.utc(2004, 3, 1, 13, 25, 0),
        baseDate: BaseDate.date1993,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('41136669315054818626'));
    });

    test('step7 (gas): PAN 000001000000000082, 01/03/2004 13:30:00', () {
      final decoderKey = _dkga04Misty1(
        baseDate: BaseDate.date1993,
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: KeyRevisionNumber(1),
        iinStr: '000001',
        iainStr: '00000000008',
        vk: vk,
      );
      final tokenNo = _generateGasToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea11,
        issuedAt: DateTime.utc(2004, 3, 1, 13, 30, 0),
        baseDate: BaseDate.date1993,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('22735221987748758248'));
    });

    test('step10 (water): PAN 600727000000000009, 01/01/2014 08:05:00, '
        'KRN=4, BaseDate=2014', () {
      final decoderKey = _dkga04Misty1(
        baseDate: BaseDate.date2014,
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: KeyRevisionNumber(4),
        iinStr: '600727',
        iainStr: '00000000000',
        vk: vk,
      );
      final tokenNo = _generateWaterToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea11,
        issuedAt: DateTime.utc(2014, 1, 1, 8, 5, 0),
        baseDate: BaseDate.date2014,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('03477912490596695895'));
    });

    test('step11 (gas): PAN 600727000000000009, 01/01/2014 08:10:00, '
        'KRN=4, BaseDate=2014', () {
      final decoderKey = _dkga04Misty1(
        baseDate: BaseDate.date2014,
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: KeyRevisionNumber(4),
        iinStr: '600727',
        iainStr: '00000000000',
        vk: vk,
      );
      final tokenNo = _generateGasToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea11,
        issuedAt: DateTime.utc(2014, 1, 1, 8, 10, 0),
        baseDate: BaseDate.date2014,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('06094571069413075467'));
    });

    test('step14 (water): PAN 600727000000000009, 01/01/2035 08:05:00, '
        'KRN=5, BaseDate=2035', () {
      final decoderKey = _dkga04Misty1(
        baseDate: BaseDate.date2035,
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: KeyRevisionNumber(5),
        iinStr: '600727',
        iainStr: '00000000000',
        vk: vk,
      );
      final tokenNo = _generateWaterToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea11,
        issuedAt: DateTime.utc(2035, 1, 1, 8, 5, 0),
        baseDate: BaseDate.date2035,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('19640099949346431996'));
    });

    test('step15 (gas): PAN 600727000000000009, 01/01/2035 08:10:00, '
        'KRN=5, BaseDate=2035', () {
      final decoderKey = _dkga04Misty1(
        baseDate: BaseDate.date2035,
        keyType: keyType,
        sgc: sgc,
        ti: ti,
        krn: KeyRevisionNumber(5),
        iinStr: '600727',
        iainStr: '00000000000',
        vk: vk,
      );
      final tokenNo = _generateGasToken(
        decoderKey: decoderKey,
        encryptionAlgorithm: ea11,
        issuedAt: DateTime.utc(2035, 1, 1, 8, 10, 0),
        baseDate: BaseDate.date2035,
        randomNo: RandomNo.fromInt(0x5),
        amount: Amount(0.1),
      );
      expect(tokenNo, equals('11741155092330337876'));
    });
  });

  group('STS_531_1_0_04 CTSA10 (DKGA-04 + EA11 / MISTY1) — amount sweep', () {
    // Upstream:
    //   STSComplianceTests_STS_531_1_0_04_CTSA10.java
    //
    // Common @Before:
    //   PAN             = "600727000000000009"
    //   vudk            = 160-bit VendingKey
    //                     "abababababababab949494949494949401234567"
    //   sgc="123457", ti="01", krn=1, kt=2, ken=255, baseDate=1993, RND=5
    //
    // 9 (datetime, amount) rows are exercised for each of the three
    // Class 0 subclasses (electricity, water, gas) — the upstream
    // step1..27 split is reproduced here as a parametric run.
    final keyType = KeyType(2);
    final sgc = SupplyGroupCode('123457');
    final ti = TariffIndex('01');
    final krn = KeyRevisionNumber(1);
    final vk = VendingCommonDesKey(
      _hex('abababababababab949494949494949401234567'),
    );
    final ea11 = Misty1EncryptionAlgorithm();
    final decoderKey = _dkga04Misty1(
      baseDate: BaseDate.date1993,
      keyType: keyType,
      sgc: sgc,
      ti: ti,
      krn: krn,
      iinStr: '600727',
      iainStr: '00000000000',
      vk: vk,
    );

    // 9 rows: hour, minute, amount, elecExpected, waterExpected, gasExpected
    final rows = <List<Object>>[
      [
        0,
        30,
        25.6,
        '63638916334124550935',
        '08844040967758161989',
        '34672027639183365663',
      ],
      [
        0,
        35,
        1638.3,
        '06736163174944595611',
        '41707569065487034639',
        '70087969935165138265',
      ],
      [
        0,
        40,
        1638.4,
        '45798100519745983712',
        '61826851589850099670',
        '60875440664020961982',
      ],
      [
        0,
        45,
        2000.0,
        '08362487434932116862',
        '72478269627942954182',
        '16605563156243942378',
      ],
      [
        0,
        50,
        18022.3,
        '33933484656539803471',
        '12311110365531155223',
        '16614677156798904170',
      ],
      [
        0,
        55,
        18022.4,
        '40075282658655256325',
        '68979561791500831417',
        '49208263727993294856',
      ],
      [
        1,
        44,
        181862.3,
        '00383912203740575049',
        '36130214068866912790',
        '38374198840578367339',
      ],
      [
        1,
        49,
        181862.4,
        '32272089791250978565',
        '49560207524955523897',
        '34384673009506006509',
      ],
      [
        1,
        54,
        1820162.4,
        '44964671935361377806',
        '47575512827888817714',
        '40332503820747813730',
      ],
    ];

    for (final r in rows) {
      final hour = r[0] as int;
      final minute = r[1] as int;
      final amount = r[2] as double;
      final issuedAt = DateTime.utc(2004, 4, 1, hour, minute, 0);
      final hhmm =
          '${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')}';

      test('elec $amount kWh @ 01/04/2004 $hhmm', () {
        final tokenNo = _generateElectricityToken(
          decoderKey: decoderKey,
          encryptionAlgorithm: ea11,
          issuedAt: issuedAt,
          baseDate: BaseDate.date1993,
          randomNo: RandomNo.fromInt(0x5),
          amount: Amount(amount),
        );
        expect(tokenNo, equals(r[3] as String));
      });

      test('water $amount @ 01/04/2004 $hhmm', () {
        final tokenNo = _generateWaterToken(
          decoderKey: decoderKey,
          encryptionAlgorithm: ea11,
          issuedAt: issuedAt,
          baseDate: BaseDate.date1993,
          randomNo: RandomNo.fromInt(0x5),
          amount: Amount(amount),
        );
        expect(tokenNo, equals(r[4] as String));
      });

      test('gas $amount @ 01/04/2004 $hhmm', () {
        final tokenNo = _generateGasToken(
          decoderKey: decoderKey,
          encryptionAlgorithm: ea11,
          issuedAt: issuedAt,
          baseDate: BaseDate.date1993,
          randomNo: RandomNo.fromInt(0x5),
          amount: Amount(amount),
        );
        expect(tokenNo, equals(r[5] as String));
      });
    }
  });
}
