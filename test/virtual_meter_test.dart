import 'dart:convert';
import 'dart:io';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:nectar_sts_dart/src/server/api_server.dart';
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
        expect(decoded['schema'], 'nectar_sts_dart.virtual_meter/v4');
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

  group('VirtualMeter MISTY1 4-section KCT', () {
    const identity = MeterIdentity(
      issuerIdentificationNumber: '600727',
      individualAccountIdentificationNumber: '12345678901',
      keyType: 2,
      supplyGroupCode: '123456',
      tariffIndex: '07',
      keyRevisionNumber: 1,
      decoderKeyGenerationAlgorithm: '04',
      baseDate: '1993',
    );

    VirtualMeter setupMisty1() => VirtualMeter.setup(
      identity: identity,
      vendingKeyBytes: parseHexKey('0123456789ABCDEF0123456789ABCDEF01234567'),
      encryptionAlgorithm: 'misty1',
    );

    VirtualHsm misty1Hsm() => VirtualHsm(
      VendingCommonDesKey(
        parseHexKey('0123456789ABCDEF0123456789ABCDEF01234567'),
      ),
    );

    Map<String, dynamic> baseParams() => {
      VirtualHsmParams.decoderKeyGenerationAlgorithm: '04',
      VirtualHsmParams.encryptionAlgorithm: 'misty1',
      VirtualHsmParams.keyType: 2,
      VirtualHsmParams.supplyGroupCode: '123456',
      VirtualHsmParams.tariffIndex: '07',
      VirtualHsmParams.keyRevisionNo: 1,
      VirtualHsmParams.issuerIdentificationNo: '600727',
      VirtualHsmParams.decoderReferenceNumber: '12345678901',
      VirtualHsmParams.baseDate: '1993',
    };

    test('rotates only after all 4 sections, in any order', () {
      final meter = setupMisty1();
      final hsm = misty1Hsm();

      // New key + new SGC the rotation should converge to.
      const newKeyHex = '00112233445566778899AABBCCDDEEFF';
      const newSgc = '654321';

      String kct(String sub, Map<String, dynamic> extra) {
        final p = {
          ...baseParams(),
          VirtualHsmParams.tokenClass: '2',
          VirtualHsmParams.tokenSubclass: sub,
          VirtualHsmParams.newDecoderKey: newKeyHex,
          VirtualHsmParams.newSupplyGroupCode: newSgc,
          ...extra,
        };
        return hsm.generateToken('kct-$sub', p).tokenNo;
      }

      final t1 = kct('3', {
        VirtualHsmParams.keyExpiryNumberHighOrder: 0xA,
        VirtualHsmParams.newKeyRevisionNumber: 2,
        VirtualHsmParams.newKeyType: 2,
        VirtualHsmParams.rollOverKeyChange: 0,
      });
      final t2 = kct('4', {
        VirtualHsmParams.keyExpiryNumberLowOrder: 0x5,
        VirtualHsmParams.newTariffIndex: '08',
      });
      final t3 = kct('8', const {});
      final t4 = kct('9', const {});

      // Apply 3rd, then 1st, then 4th — still no rotation yet.
      expect(meter.applyToken(t3), isA<ApplyKeyChange3rdStaged>());
      expect(meter.applyToken(t1), isA<ApplyKeyChange1stStaged>());
      expect(meter.applyToken(t4), isA<ApplyKeyChange4thStaged>());
      // 2nd arrives last -> rotation fires.
      final rotated = meter.applyToken(t2);
      expect(rotated, isA<ApplyKeyRotated>());
      final r = rotated as ApplyKeyRotated;
      expect(r.newKeyRevisionNumber, 2);
      expect(r.keyExpiryNumber, (0xA << 4) | 0x5);
      expect(r.newTariffIndex, '08');
      expect(r.newSupplyGroupCode, newSgc);

      // Decoder key + identity actually rotated.
      final actualHex = meter.decoderKeyBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join();
      expect(actualHex, newKeyHex);
      expect(meter.identity.supplyGroupCode, newSgc);
      expect(meter.identity.tariffIndex, '08');
      expect(meter.identity.keyRevisionNumber, 2);
      // All staging slots cleared.
      expect(meter.pending1stSection, isNull);
      expect(meter.pending2ndSection, isNull);
      expect(meter.pending3rdSection, isNull);
      expect(meter.pending4thSection, isNull);
    });

    test('partial sections persist across save/load', () async {
      final dir = await Directory.systemTemp.createTemp('vmeter-misty1');
      try {
        final path = '${dir.path}\\m.json';
        final meter = setupMisty1()..filePath = path;
        final hsm = misty1Hsm();

        final t3 = hsm.generateToken('kct-3', {
          ...baseParams(),
          VirtualHsmParams.tokenClass: '2',
          VirtualHsmParams.tokenSubclass: '8',
          VirtualHsmParams.newDecoderKey: '00112233445566778899AABBCCDDEEFF',
          VirtualHsmParams.newSupplyGroupCode: '654321',
        }).tokenNo;
        expect(meter.applyToken(t3), isA<ApplyKeyChange3rdStaged>());
        meter.save();

        final reloaded = VirtualMeter.load(path);
        expect(reloaded.pending3rdSection, isNotNull);
        // Decimal SGC 654321 splits into SGCHO=159, SGCLO=3057.
        expect(reloaded.pending3rdSection!.supplyGroupCodeLowOrder, 3057);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('VirtualMeter register tokens', () {
    test('ClearTamperCondition clears a latched tamper flag', () {
      final meter = _meter()..tripTamper();
      expect(meter.tamperLatched, isTrue);

      final hsm = _hsm();
      final tok = hsm.generateToken('clear-tamper', {
        VirtualHsmParams.decoderKeyGenerationAlgorithm: '02',
        VirtualHsmParams.encryptionAlgorithm: 'sta',
        VirtualHsmParams.keyType: 2,
        VirtualHsmParams.supplyGroupCode: '123456',
        VirtualHsmParams.tariffIndex: '07',
        VirtualHsmParams.keyRevisionNo: 1,
        VirtualHsmParams.issuerIdentificationNo: '600727',
        VirtualHsmParams.decoderReferenceNumber: '12345678901',
        VirtualHsmParams.tokenClass: '2',
        VirtualHsmParams.tokenSubclass: '5',
        VirtualHsmParams.tokenId: DateTime.utc(
          2024,
          7,
          1,
          9,
          0,
        ).toIso8601String(),
        VirtualHsmParams.baseDate: '1993',
      }).tokenNo;

      expect(meter.applyToken(tok), isA<ApplyTamperConditionCleared>());
      expect(meter.tamperLatched, isFalse);
      expect(meter.tamperConditionClearedAt, isNotNull);
    });

    test('tamper-latched flag survives save/load', () async {
      final dir = await Directory.systemTemp.createTemp('vmeter-tamper');
      try {
        final path = '${dir.path}\\m.json';
        final meter = _meter()
          ..filePath = path
          ..tripTamper()
          ..save();
        final reloaded = VirtualMeter.load(path);
        expect(reloaded.tamperLatched, isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('ClearCredit zeroes the balance', () {
      final meter = _meter(balance: 42.0);
      final hsm = _hsm();
      final tok = hsm.generateToken('clear-credit', {
        VirtualHsmParams.decoderKeyGenerationAlgorithm: '02',
        VirtualHsmParams.encryptionAlgorithm: 'sta',
        VirtualHsmParams.keyType: 2,
        VirtualHsmParams.supplyGroupCode: '123456',
        VirtualHsmParams.tariffIndex: '07',
        VirtualHsmParams.keyRevisionNo: 1,
        VirtualHsmParams.issuerIdentificationNo: '600727',
        VirtualHsmParams.decoderReferenceNumber: '12345678901',
        VirtualHsmParams.tokenClass: '2',
        VirtualHsmParams.tokenSubclass: '1',
        VirtualHsmParams.register: 1,
        VirtualHsmParams.tokenId: DateTime.utc(
          2024,
          7,
          2,
          10,
          0,
        ).toIso8601String(),
        VirtualHsmParams.baseDate: '1993',
      }).tokenNo;

      final res = meter.applyToken(tok);
      expect(res, isA<ApplyCreditCleared>());
      expect(
        (res as ApplyCreditCleared).previousBalanceKwh,
        closeTo(42.0, 1e-9),
      );
      expect(meter.balanceKwh, 0.0);
    });
  });

  group('VirtualMeter water/gas commodities', () {
    String issueCommodityToken({
      required String subclass,
      required double amount,
      required int randomNo,
      DateTime? tidTime,
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
        VirtualHsmParams.tokenSubclass: subclass,
        VirtualHsmParams.amount: amount,
        VirtualHsmParams.tokenId: (tidTime ?? DateTime.utc(2024, 6, 1, 12, 0))
            .toIso8601String(),
        VirtualHsmParams.randomNo: randomNo,
        VirtualHsmParams.baseDate: '1993',
      };
      return _hsm().generateToken('issue', params).tokenNo;
    }

    test('water token credits balanceWater, not balanceKwh', () {
      final meter = _meter(balance: 10.0);
      final tok = issueCommodityToken(subclass: '1', amount: 7.0, randomNo: 1);
      final r = meter.applyToken(tok);
      expect(r, isA<ApplyAccepted>());
      final ok = r as ApplyAccepted;
      expect(ok.commodity, 'water');
      expect(ok.amountKwh, closeTo(7.0, 1e-9));
      expect(ok.newBalanceKwh, closeTo(7.0, 1e-9));
      expect(meter.balanceWater, closeTo(7.0, 1e-9));
      expect(meter.balanceGas, 0.0);
      expect(meter.balanceKwh, closeTo(10.0, 1e-9));
    });

    test('gas token credits balanceGas, not balanceKwh', () {
      final meter = _meter(balance: 10.0);
      final tok = issueCommodityToken(subclass: '2', amount: 3.0, randomNo: 2);
      final r = meter.applyToken(tok);
      expect(r, isA<ApplyAccepted>());
      final ok = r as ApplyAccepted;
      expect(ok.commodity, 'gas');
      expect(meter.balanceGas, closeTo(3.0, 1e-9));
      expect(meter.balanceWater, 0.0);
      expect(meter.balanceKwh, closeTo(10.0, 1e-9));
    });

    test(
      'replay is scoped per commodity (same TID across commodities allowed)',
      () {
        final meter = _meter();
        final t = DateTime.utc(2024, 6, 1, 12, 0);
        final water = issueCommodityToken(
          subclass: '1',
          amount: 1.0,
          randomNo: 5,
          tidTime: t,
        );
        final gas = issueCommodityToken(
          subclass: '2',
          amount: 2.0,
          randomNo: 6,
          tidTime: t,
        );
        expect(meter.applyToken(water), isA<ApplyAccepted>());
        expect(meter.applyToken(gas), isA<ApplyAccepted>());
        // Re-applying the water token must be a replay.
        expect(meter.applyToken(water), isA<ApplyReplay>());
        expect(meter.balanceWater, closeTo(1.0, 1e-9));
        expect(meter.balanceGas, closeTo(2.0, 1e-9));
      },
    );

    test('balances round-trip through save/load', () async {
      final dir = await Directory.systemTemp.createTemp('vmeter-comm');
      try {
        final path = '${dir.path}\\m.json';
        final meter = _meter()..filePath = path;
        meter.applyToken(
          issueCommodityToken(subclass: '1', amount: 4.0, randomNo: 7),
        );
        meter.applyToken(
          issueCommodityToken(
            subclass: '2',
            amount: 6.0,
            randomNo: 8,
            tidTime: DateTime.utc(2024, 6, 1, 13, 0),
          ),
        );
        meter.save();
        final reloaded = VirtualMeter.load(path);
        expect(reloaded.balanceWater, closeTo(4.0, 1e-9));
        expect(reloaded.balanceGas, closeTo(6.0, 1e-9));
        expect(reloaded.appliedTokens.map((r) => r.commodity).toSet(), {
          'water',
          'gas',
        });
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('VirtualHsmIssuer convenience methods', () {
    Map<String, dynamic> meterParams() => {
      VirtualHsmParams.decoderKeyGenerationAlgorithm: '02',
      VirtualHsmParams.encryptionAlgorithm: 'sta',
      VirtualHsmParams.keyType: 2,
      VirtualHsmParams.supplyGroupCode: '123456',
      VirtualHsmParams.tariffIndex: '07',
      VirtualHsmParams.keyRevisionNo: 1,
      VirtualHsmParams.issuerIdentificationNo: '600727',
      VirtualHsmParams.decoderReferenceNumber: '12345678901',
      VirtualHsmParams.tokenId: DateTime.utc(
        2024,
        6,
        1,
        12,
        0,
      ).toIso8601String(),
      VirtualHsmParams.randomNo: 1,
      VirtualHsmParams.baseDate: '1993',
    };

    test('issueElectricityToken mints a TransferElectricityCreditToken', () {
      final issuer = VirtualHsmIssuer(_hsm());
      final tok = issuer.issueElectricityToken(
        requestId: 'e',
        amountKwh: 5.0,
        meterParams: meterParams(),
      );
      expect(tok, isA<TransferElectricityCreditToken>());
      expect(tok.tokenNo, hasLength(20));
    });

    test('issueWaterToken mints a TransferWaterCreditToken', () {
      final issuer = VirtualHsmIssuer(_hsm());
      final tok = issuer.issueWaterToken(
        requestId: 'w',
        amount: 5.0,
        meterParams: meterParams(),
      );
      expect(tok, isA<TransferWaterCreditToken>());
      expect(tok.tokenNo, hasLength(20));
    });

    test('issueGasToken mints a TransferGasCreditToken', () {
      final issuer = VirtualHsmIssuer(_hsm());
      final tok = issuer.issueGasToken(
        requestId: 'g',
        amount: 5.0,
        meterParams: meterParams(),
      );
      expect(tok, isA<TransferGasCreditToken>());
      expect(tok.tokenNo, hasLength(20));
    });
  });
}
