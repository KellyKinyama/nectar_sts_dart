import 'dart:convert';
import 'dart:io';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

VirtualHsm _hsm() => VirtualHsm(
  VendingCommonDesKey([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]),
);

MeterIdentity _identity() => const MeterIdentity(
  issuerIdentificationNumber: '600727',
  individualAccountIdentificationNumber: '12345678901',
  keyType: 2,
  supplyGroupCode: '123456',
  tariffIndex: '07',
  keyRevisionNumber: 1,
);

VirtualMeter _meter({double balance = 0.0}) => VirtualMeter.setup(
  identity: _identity(),
  vendingKeyBytes: parseHexKey('0123456789ABCDEF'),
  initialBalanceKwh: balance,
);

/// Generate a Class 0/0 token via the same VirtualHsm a real utility
/// would use, so the meter has something to chew on.
String _issueToken({
  required double amountKwh,
  DateTime? tidTime,
  int? randomNo,
}) {
  final params = {
    VirtualHsmParams.decoderKeyGenerationAlgorithm: '02',
    VirtualHsmParams.encryptionAlgorithm: 'sta',
    VirtualHsmParams.keyType: 2,
    VirtualHsmParams.supplyGroupCode: '123456',
    VirtualHsmParams.tariffIndex: '07',
    VirtualHsmParams.keyRevisionNo: 1,
    VirtualHsmParams.issuerIdentificationNo: '600727',
    VirtualHsmParams.decoderReferenceNumber: '12345678901',
    VirtualHsmParams.tokenClass: '0',
    VirtualHsmParams.tokenSubclass: '0',
    VirtualHsmParams.amount: amountKwh,
    VirtualHsmParams.tokenId: (tidTime ?? DateTime.utc(2024, 6, 1, 12, 0))
        .toIso8601String(),
    if (randomNo != null) VirtualHsmParams.randomNo: randomNo,
    VirtualHsmParams.baseDate: '1993',
  };
  return _hsm().generateToken('issue', params).tokenNo;
}

void main() {
  group('VirtualMeter', () {
    test('setup derives the same decoder key VirtualHsm would', () {
      final meter = _meter();
      final expected = _hsm().deriveDecoderKeyDkga02(
        issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
        individualAccountIdentificationNumber:
            IndividualAccountIdentificationNumber('12345678901'),
        keyType: KeyType(2),
        supplyGroupCode: SupplyGroupCode('123456'),
        tariffIndex: TariffIndex('07'),
        keyRevisionNumber: KeyRevisionNumber(1),
      );
      expect(meter.decoderKeyBytes, equals(expected.keyData));
    });

    test('applyToken credits a valid Class 0/0 token', () {
      final meter = _meter(balance: 10.0);
      final token = _issueToken(amountKwh: 25.5, randomNo: 7);

      final r = meter.applyToken(token);
      expect(r, isA<ApplyAccepted>());
      final ok = r as ApplyAccepted;
      expect(ok.amountKwh, closeTo(25.5, 1e-9));
      expect(ok.newBalanceKwh, closeTo(35.5, 1e-9));
      expect(meter.balanceKwh, closeTo(35.5, 1e-9));
      expect(meter.appliedTokens, hasLength(1));
    });

    test('replay of the same token is rejected, balance unchanged', () {
      final meter = _meter();
      final token = _issueToken(amountKwh: 5.0, randomNo: 3);

      expect(meter.applyToken(token), isA<ApplyAccepted>());
      final second = meter.applyToken(token);
      expect(second, isA<ApplyReplay>());
      expect(meter.balanceKwh, closeTo(5.0, 1e-9));
      expect(meter.appliedTokens, hasLength(1));
    });

    test('two tokens with different TIDs both credit', () {
      final meter = _meter();
      final t1 = _issueToken(
        amountKwh: 5.0,
        tidTime: DateTime.utc(2024, 6, 1, 12, 0),
        randomNo: 1,
      );
      final t2 = _issueToken(
        amountKwh: 7.5,
        tidTime: DateTime.utc(2024, 6, 1, 13, 0),
        randomNo: 2,
      );

      expect(meter.applyToken(t1), isA<ApplyAccepted>());
      expect(meter.applyToken(t2), isA<ApplyAccepted>());
      expect(meter.balanceKwh, closeTo(12.5, 1e-9));
      expect(meter.appliedTokens, hasLength(2));
    });

    test('a corrupted token is rejected without changing balance', () {
      final meter = _meter(balance: 2.5);
      final token = _issueToken(amountKwh: 5.0, randomNo: 4);
      // Flip a digit somewhere in the middle to corrupt the CRC.
      final corrupted =
          token.substring(0, 10) +
          ((int.parse(token[10]) + 1) % 10).toString() +
          token.substring(11);

      final r = meter.applyToken(corrupted);
      expect(r, isA<ApplyRejected>());
      expect(meter.balanceKwh, closeTo(2.5, 1e-9));
      expect(meter.appliedTokens, isEmpty);
    });

    test('save -> load round-trip preserves balance + applied log', () async {
      final dir = await Directory.systemTemp.createTemp('vmeter');
      try {
        final path = '${dir.path}\\m.json';
        final meter = _meter(balance: 1.0)..filePath = path;
        meter.applyToken(_issueToken(amountKwh: 8.0, randomNo: 9));
        meter.save();

        final reloaded = VirtualMeter.load(path);
        expect(reloaded.balanceKwh, closeTo(9.0, 1e-9));
        expect(reloaded.appliedTokens, hasLength(1));
        expect(reloaded.appliedTokens.first.amountKwh, closeTo(8.0, 1e-9));
        expect(reloaded.decoderKeyBytes, equals(meter.decoderKeyBytes));

        // The on-disk JSON is human-inspectable and well-formed.
        final raw = await File(path).readAsString();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        expect(decoded['schema'], 'nectar_sts_dart.virtual_meter/v2');
        expect(decoded['balance_kwh'], closeTo(9.0, 1e-9));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('reloaded meter still detects replays across restarts', () async {
      final dir = await Directory.systemTemp.createTemp('vmeter');
      try {
        final path = '${dir.path}\\m.json';
        final m1 = _meter()..filePath = path;
        final token = _issueToken(amountKwh: 3.0, randomNo: 5);
        expect(m1.applyToken(token), isA<ApplyAccepted>());
        m1.save();

        final m2 = VirtualMeter.load(path);
        expect(m2.applyToken(token), isA<ApplyReplay>());
        expect(m2.balanceKwh, closeTo(3.0, 1e-9));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
