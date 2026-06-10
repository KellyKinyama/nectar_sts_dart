import 'dart:typed_data';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

final _vendingKeyHex = '0123456789ABCDEF';
final _iin = '600727';
final _drn = '12345678901';
final _sgc = '123456';

VirtualHsm _hsm() =>
    VirtualHsm(VendingCommonDesKey(parseHexKey(_vendingKeyHex)));

DecoderKey _deriveKey({
  required int keyRevisionNumber,
  required String tariffIndex,
  int keyType = 2,
}) => _hsm().deriveDecoderKeyDkga02(
  issuerIdentificationNumber: IssuerIdentificationNumber(_iin),
  individualAccountIdentificationNumber: IndividualAccountIdentificationNumber(
    _drn,
  ),
  keyType: KeyType(keyType),
  supplyGroupCode: SupplyGroupCode(_sgc),
  tariffIndex: TariffIndex(tariffIndex),
  keyRevisionNumber: KeyRevisionNumber(keyRevisionNumber),
);

Map<String, dynamic> _baseHsmParams({
  required String tokenClass,
  required String tokenSubclass,
  int keyRevisionNo = 1,
  String tariffIndex = '07',
  int keyType = 2,
  DateTime? tokenId,
}) => {
  VirtualHsmParams.decoderKeyGenerationAlgorithm: '02',
  VirtualHsmParams.encryptionAlgorithm: 'sta',
  VirtualHsmParams.keyType: keyType,
  VirtualHsmParams.supplyGroupCode: _sgc,
  VirtualHsmParams.tariffIndex: tariffIndex,
  VirtualHsmParams.keyRevisionNo: keyRevisionNo,
  VirtualHsmParams.issuerIdentificationNo: _iin,
  VirtualHsmParams.decoderReferenceNumber: _drn,
  VirtualHsmParams.tokenClass: tokenClass,
  VirtualHsmParams.tokenSubclass: tokenSubclass,
  VirtualHsmParams.baseDate: '1993',
  VirtualHsmParams.tokenId: (tokenId ?? DateTime.utc(2024, 6, 15, 10, 0))
      .toIso8601String(),
};

MeterIdentity _meterIdentity() => const MeterIdentity(
  issuerIdentificationNumber: '600727',
  individualAccountIdentificationNumber: '12345678901',
  keyType: 2,
  supplyGroupCode: '123456',
  tariffIndex: '07',
  keyRevisionNumber: 1,
);

void main() {
  group('Class 2 register-payload tokens — round-trip', () {
    test('SetMaximumPowerLimit (0x0) decodes the issued value', () {
      final tokenNo = _hsm().generateToken('mpl-rt', {
        ..._baseHsmParams(tokenClass: '2', tokenSubclass: '0'),
        VirtualHsmParams.maximumPowerLimit: 4321,
      }).tokenNo;

      final key = _deriveKey(keyRevisionNumber: 1, tariffIndex: '07');
      final dec = TokenDecoderDispatcher(
        key,
        StandardTransferAlgorithm(),
      ).decodeDecimal('mpl-rt-dec', tokenNo);

      expect(dec, isA<DecodeAccepted>());
      final t = (dec as DecodeAccepted).token as SetMaximumPowerLimitToken;
      expect(t.maximumPowerLimit!.value, 4321);
      expect(t.tokenSubClass!.bitString.value, 0x0);
    });

    test('ClearCredit (0x1) carries the register value and decodes', () {
      final tokenNo = _hsm().generateToken('cc-rt', {
        ..._baseHsmParams(tokenClass: '2', tokenSubclass: '1'),
        VirtualHsmParams.register: 0,
      }).tokenNo;

      final key = _deriveKey(keyRevisionNumber: 1, tariffIndex: '07');
      final dec = TokenDecoderDispatcher(
        key,
        StandardTransferAlgorithm(),
      ).decodeDecimal('cc-rt-dec', tokenNo);

      expect(dec, isA<DecodeAccepted>());
      final t = (dec as DecodeAccepted).token as ClearCreditToken;
      expect(t.register!.value, 0);
      expect(t.tokenSubClass!.bitString.value, 0x1);
    });

    test('SetTariffRate (0x2) decodes the issued rate', () {
      final tokenNo = _hsm().generateToken('rate-rt', {
        ..._baseHsmParams(tokenClass: '2', tokenSubclass: '2'),
        VirtualHsmParams.tariffRate: 137,
      }).tokenNo;

      final key = _deriveKey(keyRevisionNumber: 1, tariffIndex: '07');
      final dec = TokenDecoderDispatcher(
        key,
        StandardTransferAlgorithm(),
      ).decodeDecimal('rate-rt-dec', tokenNo);

      expect(dec, isA<DecodeAccepted>());
      final t = (dec as DecodeAccepted).token as SetTariffRateToken;
      expect(t.rate!.value, 137);
      expect(t.tokenSubClass!.bitString.value, 0x2);
    });

    test('ClearTamperCondition (0x5) decodes with a zero pad', () {
      final tokenNo = _hsm().generateToken('ctc-rt', {
        ..._baseHsmParams(tokenClass: '2', tokenSubclass: '5'),
      }).tokenNo;

      final key = _deriveKey(keyRevisionNumber: 1, tariffIndex: '07');
      final dec = TokenDecoderDispatcher(
        key,
        StandardTransferAlgorithm(),
      ).decodeDecimal('ctc-rt-dec', tokenNo);

      expect(dec, isA<DecodeAccepted>());
      final t = (dec as DecodeAccepted).token as ClearTamperConditionToken;
      expect(t.pad!.value, 0);
      expect(t.tokenSubClass!.bitString.value, 0x5);
    });

    test(
      'SetMaximumPhasePowerUnbalanceLimit (0x6) decodes the issued value',
      () {
        final tokenNo = _hsm().generateToken('mppul-rt', {
          ..._baseHsmParams(tokenClass: '2', tokenSubclass: '6'),
          VirtualHsmParams.maximumPhasePowerUnbalanceLimit: 999,
        }).tokenNo;

        final key = _deriveKey(keyRevisionNumber: 1, tariffIndex: '07');
        final dec = TokenDecoderDispatcher(
          key,
          StandardTransferAlgorithm(),
        ).decodeDecimal('mppul-rt-dec', tokenNo);

        expect(dec, isA<DecodeAccepted>());
        final t =
            (dec as DecodeAccepted).token
                as SetMaximumPhasePowerUnbalanceLimitToken;
        expect(t.maximumPhasePowerUnbalanceLimit!.value, 999);
        expect(t.tokenSubClass!.bitString.value, 0x6);
      },
    );
  });

  group('Class 2 register-payload tokens — meter application', () {
    test('SetMaximumPowerLimit mutates meter and is replay-protected', () {
      final meter = VirtualMeter.setup(
        identity: _meterIdentity(),
        vendingKeyBytes: parseHexKey(_vendingKeyHex),
      );
      expect(meter.maximumPowerLimit, isNull);

      final tokenNo = _hsm().generateToken('mpl-apply', {
        ..._baseHsmParams(
          tokenClass: '2',
          tokenSubclass: '0',
          tokenId: DateTime.utc(2024, 6, 15, 11, 0),
        ),
        VirtualHsmParams.maximumPowerLimit: 5000,
      }).tokenNo;

      final r = meter.applyToken(tokenNo);
      expect(r, isA<ApplyMaximumPowerLimitSet>());
      expect((r as ApplyMaximumPowerLimitSet).maximumPowerLimit, 5000);
      expect(meter.maximumPowerLimit, 5000);

      final r2 = meter.applyToken(tokenNo);
      expect(r2, isA<ApplyManagementReplay>());
      expect((r2 as ApplyManagementReplay).tidMinutes, r.tidMinutes);
      expect(meter.appliedManagementTokens, hasLength(1));
    });

    test('ClearCredit resets balanceKwh to 0 and stamps creditClearedAt', () {
      final meter = VirtualMeter.setup(
        identity: _meterIdentity(),
        vendingKeyBytes: parseHexKey(_vendingKeyHex),
        initialBalanceKwh: 250.5,
      );

      final tokenNo = _hsm().generateToken('cc-apply', {
        ..._baseHsmParams(
          tokenClass: '2',
          tokenSubclass: '1',
          tokenId: DateTime.utc(2024, 6, 15, 12, 0),
        ),
        VirtualHsmParams.register: 0,
      }).tokenNo;

      final r = meter.applyToken(tokenNo);
      expect(r, isA<ApplyCreditCleared>());
      expect((r as ApplyCreditCleared).previousBalanceKwh, 250.5);
      expect(r.register, 0);
      expect(meter.balanceKwh, 0.0);
      expect(meter.creditClearedAt, isNotNull);
    });

    test('SetTariffRate mutates meter tariff rate', () {
      final meter = VirtualMeter.setup(
        identity: _meterIdentity(),
        vendingKeyBytes: parseHexKey(_vendingKeyHex),
      );

      final tokenNo = _hsm().generateToken('rate-apply', {
        ..._baseHsmParams(
          tokenClass: '2',
          tokenSubclass: '2',
          tokenId: DateTime.utc(2024, 6, 15, 13, 0),
        ),
        VirtualHsmParams.tariffRate: 42,
      }).tokenNo;

      final r = meter.applyToken(tokenNo);
      expect(r, isA<ApplyTariffRateSet>());
      expect((r as ApplyTariffRateSet).tariffRate, 42);
      expect(meter.tariffRate, 42);
    });

    test('ClearTamperCondition stamps tamperConditionClearedAt', () {
      final meter = VirtualMeter.setup(
        identity: _meterIdentity(),
        vendingKeyBytes: parseHexKey(_vendingKeyHex),
      );
      expect(meter.tamperConditionClearedAt, isNull);

      final tokenNo = _hsm().generateToken('ctc-apply', {
        ..._baseHsmParams(
          tokenClass: '2',
          tokenSubclass: '5',
          tokenId: DateTime.utc(2024, 6, 15, 14, 0),
        ),
      }).tokenNo;

      final r = meter.applyToken(tokenNo);
      expect(r, isA<ApplyTamperConditionCleared>());
      expect(meter.tamperConditionClearedAt, isNotNull);
    });

    test('SetMaximumPhasePowerUnbalanceLimit mutates meter MPPUL', () {
      final meter = VirtualMeter.setup(
        identity: _meterIdentity(),
        vendingKeyBytes: parseHexKey(_vendingKeyHex),
      );

      final tokenNo = _hsm().generateToken('mppul-apply', {
        ..._baseHsmParams(
          tokenClass: '2',
          tokenSubclass: '6',
          tokenId: DateTime.utc(2024, 6, 15, 15, 0),
        ),
        VirtualHsmParams.maximumPhasePowerUnbalanceLimit: 250,
      }).tokenNo;

      final r = meter.applyToken(tokenNo);
      expect(r, isA<ApplyMaximumPhasePowerUnbalanceLimitSet>());
      expect(
        (r as ApplyMaximumPhasePowerUnbalanceLimitSet)
            .maximumPhasePowerUnbalanceLimit,
        250,
      );
      expect(meter.maximumPhasePowerUnbalanceLimit, 250);
    });

    test('JSON round-trip preserves all new fields after mutations', () {
      final meter = VirtualMeter.setup(
        identity: _meterIdentity(),
        vendingKeyBytes: parseHexKey(_vendingKeyHex),
        initialBalanceKwh: 100.0,
      );

      // Apply one of each management token.
      meter.applyToken(
        _hsm().generateToken('j-mpl', {
          ..._baseHsmParams(
            tokenClass: '2',
            tokenSubclass: '0',
            tokenId: DateTime.utc(2024, 7, 1, 10, 0),
          ),
          VirtualHsmParams.maximumPowerLimit: 6000,
        }).tokenNo,
      );
      meter.applyToken(
        _hsm().generateToken('j-rate', {
          ..._baseHsmParams(
            tokenClass: '2',
            tokenSubclass: '2',
            tokenId: DateTime.utc(2024, 7, 1, 11, 0),
          ),
          VirtualHsmParams.tariffRate: 77,
        }).tokenNo,
      );
      meter.applyToken(
        _hsm().generateToken('j-ctc', {
          ..._baseHsmParams(
            tokenClass: '2',
            tokenSubclass: '5',
            tokenId: DateTime.utc(2024, 7, 1, 12, 0),
          ),
        }).tokenNo,
      );
      meter.applyToken(
        _hsm().generateToken('j-mppul', {
          ..._baseHsmParams(
            tokenClass: '2',
            tokenSubclass: '6',
            tokenId: DateTime.utc(2024, 7, 1, 13, 0),
          ),
          VirtualHsmParams.maximumPhasePowerUnbalanceLimit: 300,
        }).tokenNo,
      );
      meter.applyToken(
        _hsm().generateToken('j-cc', {
          ..._baseHsmParams(
            tokenClass: '2',
            tokenSubclass: '1',
            tokenId: DateTime.utc(2024, 7, 1, 14, 0),
          ),
          VirtualHsmParams.register: 0,
        }).tokenNo,
      );

      final json = meter.toJson();
      final reloaded = VirtualMeter.fromJson(json);

      expect(reloaded.maximumPowerLimit, 6000);
      expect(reloaded.tariffRate, 77);
      expect(reloaded.tamperConditionClearedAt, isNotNull);
      expect(reloaded.maximumPhasePowerUnbalanceLimit, 300);
      expect(reloaded.creditClearedAt, isNotNull);
      expect(reloaded.balanceKwh, 0.0);
      expect(reloaded.appliedManagementTokens, hasLength(5));
      final types = reloaded.appliedManagementTokens
          .map((r) => r.tokenType)
          .toSet();
      expect(types, contains('SetMaximumPowerLimit_20'));
      expect(types, contains('SetTariffRate_22'));
      expect(types, contains('ClearTamperCondition_25'));
      expect(types, contains('SetMaximumPhasePowerUnbalanceLimit_26'));
      expect(types, contains('ClearCredit_21'));
    });
  });

  group('Class 2 register-payload tokens — input validation', () {
    test('MaximumPowerLimit out-of-range throws InvalidMplException', () {
      expect(() => MaximumPowerLimit(-1), throwsA(isA<InvalidMplException>()));
      expect(
        () => MaximumPowerLimit(0x10000),
        throwsA(isA<InvalidMplException>()),
      );
    });

    test('Rate.fromValue out-of-range throws InvalidRateException', () {
      expect(() => Rate.fromValue(-1), throwsA(isA<InvalidRateException>()));
      expect(
        () => Rate.fromValue(0x10000),
        throwsA(isA<InvalidRateException>()),
      );
    });

    test('Register wrong-length BitString throws', () {
      expect(
        () => Register(BitString.fromValue(0, 8)),
        throwsA(isA<InvalidRegisterBitStringException>()),
      );
    });

    test('Bytes-on-the-wire smoke: token is 20 decimal digits', () {
      final tokenNo = _hsm().generateToken('len-check', {
        ..._baseHsmParams(tokenClass: '2', tokenSubclass: '0'),
        VirtualHsmParams.maximumPowerLimit: 1,
      }).tokenNo;
      expect(tokenNo.length, 20);
      expect(tokenNo, matches(RegExp(r'^[0-9]{20}$')));
    });
  });
}

// avoid unused-import lint for Uint8List if the test ever stops
// using it; keep harmless reference.
// ignore: unused_element
Uint8List _u8(List<int> b) => Uint8List.fromList(b);
