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
};

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('Class 2 Decoder Key Change Tokens', () {
    test('1st Section round-trip via dispatcher', () {
      final newKey = _deriveKey(keyRevisionNumber: 2, tariffIndex: '08');
      final tokenNo = _hsm().generateToken('rt-1st', {
        ..._baseHsmParams(tokenClass: '2', tokenSubclass: '3'),
        VirtualHsmParams.newDecoderKey: _hex(
          Uint8List.fromList(newKey.keyData),
        ),
        VirtualHsmParams.keyExpiryNumberHighOrder: 0xA,
        VirtualHsmParams.newKeyRevisionNumber: 2,
        VirtualHsmParams.newKeyType: 2,
        VirtualHsmParams.rollOverKeyChange: 0,
      }).tokenNo;

      final currentKey = _deriveKey(keyRevisionNumber: 1, tariffIndex: '07');
      final dec = TokenDecoderDispatcher(
        currentKey,
        StandardTransferAlgorithm(),
      ).decodeDecimal('rt-1st-dec', tokenNo);

      expect(dec, isA<DecodeAccepted>());
      final t = (dec as DecodeAccepted).token as Set1stSectionDecoderKeyToken;
      expect(t.keyExpiryNumberHighOrder!.value, 0xA);
      expect(t.keyRevisionNumber!.value, 2);
      expect(t.keyType!.value, 2);
      expect(t.rolloverKeyChange!.isRollover, isFalse);
      expect(t.reserved3Kct!.bitString.value, 0);
      final split = splitStaDecoderKey(newKey);
      expect(
        t.newKeyHighOrder!.bitString.toPaddedBinary(),
        split.high.bitString.toPaddedBinary(),
      );
    });

    test('2nd Section round-trip via dispatcher', () {
      final newKey = _deriveKey(keyRevisionNumber: 2, tariffIndex: '08');
      final tokenNo = _hsm().generateToken('rt-2nd', {
        ..._baseHsmParams(tokenClass: '2', tokenSubclass: '4'),
        VirtualHsmParams.newDecoderKey: _hex(
          Uint8List.fromList(newKey.keyData),
        ),
        VirtualHsmParams.keyExpiryNumberLowOrder: 0xB,
        VirtualHsmParams.newTariffIndex: '08',
      }).tokenNo;

      final currentKey = _deriveKey(keyRevisionNumber: 1, tariffIndex: '07');
      final dec = TokenDecoderDispatcher(
        currentKey,
        StandardTransferAlgorithm(),
      ).decodeDecimal('rt-2nd-dec', tokenNo);

      expect(dec, isA<DecodeAccepted>());
      final t = (dec as DecodeAccepted).token as Set2ndSectionDecoderKeyToken;
      expect(t.keyExpiryNumberLowOrder!.value, 0xB);
      expect(t.tariffIndex!.value, '08');
      final split = splitStaDecoderKey(newKey);
      expect(
        t.newKeyLowOrder!.bitString.toPaddedBinary(),
        split.low.bitString.toPaddedBinary(),
      );
    });

    test('splitStaDecoderKey + combineStaDecoderKey are inverses', () {
      final key = DecoderKey(
        Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE]),
      );
      final split = splitStaDecoderKey(key);
      final rebuilt = combineStaDecoderKey(split.high, split.low);
      expect(
        _hex(Uint8List.fromList(rebuilt.keyData)),
        _hex(Uint8List.fromList(key.keyData)),
      );
    });

    test(
      'meter rotation: 1st staged, 2nd rotates, new credit token applies',
      () {
        final meter = VirtualMeter.setup(
          identity: const MeterIdentity(
            issuerIdentificationNumber: '600727',
            individualAccountIdentificationNumber: '12345678901',
            keyType: 2,
            supplyGroupCode: '123456',
            tariffIndex: '07',
            keyRevisionNumber: 1,
          ),
          vendingKeyBytes: parseHexKey(_vendingKeyHex),
        );
        final originalKey = Uint8List.fromList(meter.decoderKeyBytes);
        final newKey = _deriveKey(keyRevisionNumber: 2, tariffIndex: '08');

        // 1st section
        final tk1 = _hsm().generateToken('iss-1', {
          ..._baseHsmParams(tokenClass: '2', tokenSubclass: '3'),
          VirtualHsmParams.newDecoderKey: _hex(
            Uint8List.fromList(newKey.keyData),
          ),
          VirtualHsmParams.keyExpiryNumberHighOrder: 0xA,
          VirtualHsmParams.newKeyRevisionNumber: 2,
          VirtualHsmParams.newKeyType: 2,
          VirtualHsmParams.rollOverKeyChange: 0,
        }).tokenNo;
        final r1 = meter.applyToken(tk1);
        expect(r1, isA<ApplyKeyChange1stStaged>());
        expect(
          _hex(meter.decoderKeyBytes),
          _hex(originalKey),
          reason: 'meter key must not rotate after only 1st section',
        );
        expect(meter.pending1stSection, isNotNull);
        expect(meter.pending2ndSection, isNull);

        // 2nd section -> rotation
        final tk2 = _hsm().generateToken('iss-2', {
          ..._baseHsmParams(tokenClass: '2', tokenSubclass: '4'),
          VirtualHsmParams.newDecoderKey: _hex(
            Uint8List.fromList(newKey.keyData),
          ),
          VirtualHsmParams.keyExpiryNumberLowOrder: 0xB,
          VirtualHsmParams.newTariffIndex: '08',
        }).tokenNo;
        final r2 = meter.applyToken(tk2);
        expect(r2, isA<ApplyKeyRotated>());
        final rotated = r2 as ApplyKeyRotated;
        expect(rotated.newKeyRevisionNumber, 2);
        expect(rotated.newTariffIndex, '08');
        expect(rotated.keyExpiryNumber, 0xAB);
        expect(rotated.newKeyType, 2);
        expect(rotated.rolloverKeyChange, isFalse);

        expect(
          _hex(meter.decoderKeyBytes),
          _hex(Uint8List.fromList(newKey.keyData)),
        );
        expect(meter.identity.keyRevisionNumber, 2);
        expect(meter.identity.tariffIndex, '08');
        expect(meter.keyExpiryNumber, 0xAB);
        expect(meter.pending1stSection, isNull);
        expect(meter.pending2ndSection, isNull);

        // Credit under the NEW key (must succeed).
        final tkCredit = _hsm().generateToken('iss-credit', {
          ..._baseHsmParams(
            tokenClass: '0',
            tokenSubclass: '0',
            keyRevisionNo: 2,
            tariffIndex: '08',
          ),
          VirtualHsmParams.amount: 25.0,
          VirtualHsmParams.tokenId: DateTime.utc(2024, 7, 1).toIso8601String(),
          VirtualHsmParams.randomNo: 1,
        }).tokenNo;
        final r3 = meter.applyToken(tkCredit);
        expect(r3, isA<ApplyAccepted>());
        expect((r3 as ApplyAccepted).amountKwh, 25.0);
        expect(r3.newBalanceKwh, 25.0);

        // Credit token issued under the OLD key must now fail.
        final stale = _hsm().generateToken('iss-stale', {
          ..._baseHsmParams(tokenClass: '0', tokenSubclass: '0'),
          VirtualHsmParams.amount: 10.0,
          VirtualHsmParams.tokenId: DateTime.utc(2024, 7, 2).toIso8601String(),
          VirtualHsmParams.randomNo: 2,
        }).tokenNo;
        final rStale = meter.applyToken(stale);
        expect(rStale, isA<ApplyRejected>());
      },
    );

    test('2nd-then-1st arrival order also rotates', () {
      final meter = VirtualMeter.setup(
        identity: const MeterIdentity(
          issuerIdentificationNumber: '600727',
          individualAccountIdentificationNumber: '12345678901',
          keyType: 2,
          supplyGroupCode: '123456',
          tariffIndex: '07',
          keyRevisionNumber: 1,
        ),
        vendingKeyBytes: parseHexKey(_vendingKeyHex),
      );
      final newKey = _deriveKey(keyRevisionNumber: 3, tariffIndex: '05');

      final tk2 = _hsm().generateToken('iss-2-first', {
        ..._baseHsmParams(tokenClass: '2', tokenSubclass: '4'),
        VirtualHsmParams.newDecoderKey: _hex(
          Uint8List.fromList(newKey.keyData),
        ),
        VirtualHsmParams.keyExpiryNumberLowOrder: 0x1,
        VirtualHsmParams.newTariffIndex: '05',
      }).tokenNo;
      final r2 = meter.applyToken(tk2);
      expect(r2, isA<ApplyKeyChange2ndStaged>());

      final tk1 = _hsm().generateToken('iss-1-second', {
        ..._baseHsmParams(tokenClass: '2', tokenSubclass: '3'),
        VirtualHsmParams.newDecoderKey: _hex(
          Uint8List.fromList(newKey.keyData),
        ),
        VirtualHsmParams.keyExpiryNumberHighOrder: 0x2,
        VirtualHsmParams.newKeyRevisionNumber: 3,
        VirtualHsmParams.newKeyType: 2,
        VirtualHsmParams.rollOverKeyChange: 1,
      }).tokenNo;
      final r1 = meter.applyToken(tk1);
      expect(r1, isA<ApplyKeyRotated>());
      final rot = r1 as ApplyKeyRotated;
      expect(rot.keyExpiryNumber, 0x21);
      expect(rot.newKeyRevisionNumber, 3);
      expect(rot.newTariffIndex, '05');
      expect(rot.rolloverKeyChange, isTrue);
    });

    test('rotated meter survives a save/load round-trip', () {
      final meter = VirtualMeter.setup(
        identity: const MeterIdentity(
          issuerIdentificationNumber: '600727',
          individualAccountIdentificationNumber: '12345678901',
          keyType: 2,
          supplyGroupCode: '123456',
          tariffIndex: '07',
          keyRevisionNumber: 1,
        ),
        vendingKeyBytes: parseHexKey(_vendingKeyHex),
      );
      final newKey = _deriveKey(keyRevisionNumber: 2, tariffIndex: '08');

      final tk1 = _hsm().generateToken('iss-1', {
        ..._baseHsmParams(tokenClass: '2', tokenSubclass: '3'),
        VirtualHsmParams.newDecoderKey: _hex(
          Uint8List.fromList(newKey.keyData),
        ),
        VirtualHsmParams.keyExpiryNumberHighOrder: 0xF,
        VirtualHsmParams.newKeyRevisionNumber: 2,
        VirtualHsmParams.newKeyType: 2,
        VirtualHsmParams.rollOverKeyChange: 0,
      }).tokenNo;
      meter.applyToken(tk1);
      // Persist with pending 1st only.
      final j1 = meter.toJson();
      final meter2 = VirtualMeter.fromJson(j1);
      expect(meter2.pending1stSection, isNotNull);
      expect(meter2.pending1stSection!.keyExpiryNumberHighOrder, 0xF);

      final tk2 = _hsm().generateToken('iss-2', {
        ..._baseHsmParams(tokenClass: '2', tokenSubclass: '4'),
        VirtualHsmParams.newDecoderKey: _hex(
          Uint8List.fromList(newKey.keyData),
        ),
        VirtualHsmParams.keyExpiryNumberLowOrder: 0x0,
        VirtualHsmParams.newTariffIndex: '08',
      }).tokenNo;
      meter2.applyToken(tk2);
      expect(meter2.keyExpiryNumber, 0xF0);
      expect(meter2.identity.keyRevisionNumber, 2);

      // Persist + reload again; rotated state must survive.
      final j2 = meter2.toJson();
      final meter3 = VirtualMeter.fromJson(j2);
      expect(meter3.keyExpiryNumber, 0xF0);
      expect(meter3.identity.keyRevisionNumber, 2);
      expect(meter3.identity.tariffIndex, '08');
      expect(
        _hex(meter3.decoderKeyBytes),
        _hex(Uint8List.fromList(newKey.keyData)),
      );
      expect(meter3.pending1stSection, isNull);
      expect(meter3.pending2ndSection, isNull);
    });
  });
}
