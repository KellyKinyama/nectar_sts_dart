// STS compliance test vectors ported from NectarAPI/tokens-service:
//   src/test/java/ke/co/nectar/token/domain/token/
//     STSComplianceTests_STS_531_1_0_02_CTSA01.java
//   src/test/java/ke/co/nectar/token/generators/tokensgenerator/nativetoken/
//     class0/TransferElectricityCreditTokenGeneratorTest.java
//
// SCOPE:
//   - CTSA01 (DKGA-02 + EA07/STA): only the TransferElectricityCredit
//     steps (step1, step2). Water/gas variants (step3-6) are skipped:
//     this port intentionally implements electricity only.
//   - CTSA01 (DKGA-04 + EA11/MISTY1) is entirely skipped: the upstream
//     test uses `Misty1AlgorithmEncryptionAlgorithm` for both key
//     generation AND token encryption, but EA11 is explicitly out of
//     scope in `lib/src/decoderkey/dkga04.dart` and the encryption
//     layer. Cannot be reproduced without porting MISTY1.
//   - The `KeyExpiryNumber` argument that the Java generators take is
//     not present in our Dart port. Inspection of the Java source shows
//     KEN is stored on the generator but is NOT mixed into the data
//     block (`crc || amount || tid || rnd || sub` — KEN absent) and
//     not used by DKGA-02 key derivation. So omitting KEN in our port
//     produces identical tokens.
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

    // step3..step6 (water/gas variants) intentionally omitted — this
    // Dart port implements electricity only.
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
}
