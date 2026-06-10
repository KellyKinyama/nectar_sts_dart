/// End-to-end demo of the algorithm core.
///
/// Issues an electricity-credit top-up token from a hard-coded vending
/// key + meter identity, prints the 20-digit token, then plays the
/// "meter side" by decoding it and printing the recovered amount.
///
/// Run with:
///   dart run nectar_sts_dart:demo
/// or
///   dart run bin/demo.dart
///
/// Override the parameters via CLI args:
///   dart run bin/demo.dart --amount 25.5 --tid-time 2024-06-01T12:00Z
library;

import 'package:nectar_sts_dart/nectar_sts_dart.dart';

void main(List<String> args) {
  final opts = _parse(args);

  print('--- nectar_sts_dart demo (algorithm core) -----------------\n');

  // 1. Build the vending key + meter identity.
  final vendingKey = VendingCommonDesKey([
    0x01,
    0x23,
    0x45,
    0x67,
    0x89,
    0xAB,
    0xCD,
    0xEF,
  ]);
  final hsm = VirtualHsm(vendingKey);
  print('HSM:           ${hsm.name}');
  print(
    'Vending key:   '
    '${vendingKey.keyData.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'
    ' (${vendingKey.keyData.length} bytes)',
  );

  final iin = IssuerIdentificationNumber('600727');
  final iain = IndividualAccountIdentificationNumber('12345678901');
  final keyType = KeyType(2); // DUTK
  final sgc = SupplyGroupCode('123456');
  final ti = TariffIndex('07');
  final krn = KeyRevisionNumber(1);

  print('Meter IIN:     ${iin.value}');
  print('Meter IAIN:    ${iain.value}');
  print('Key type:      ${keyType.value} (DUTK)');
  print('SGC / TI / KRN: ${sgc.value} / ${ti.value} / ${krn.value}');

  // 2. Derive the per-meter decoder key via DKGA-02.
  final decoderKey = hsm.deriveDecoderKeyDkga02(
    issuerIdentificationNumber: iin,
    individualAccountIdentificationNumber: iain,
    keyType: keyType,
    supplyGroupCode: sgc,
    tariffIndex: ti,
    keyRevisionNumber: krn,
  );
  print(
    'Decoder key:   '
    '${decoderKey.keyData.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'
    ' (DKGA-02)\n',
  );

  // 3. Build a TransferElectricityCredit token (Class 0 / SubClass 0).
  final ea07 = StandardTransferAlgorithm();
  final tid = TokenIdentifier(BaseDate.date1993, timeOfIssue: opts.tidTime);
  final amount = Amount(opts.amount);
  final rnd = RandomNo.random();

  final token = TransferElectricityCreditToken(opts.requestID)
    ..amountPurchased = amount
    ..tokenIdentifier = tid
    ..randomNo = rnd;

  TransferElectricityCreditTokenGenerator(decoderKey, ea07).generate(token);

  print('--- Issued token ------------------------------------------');
  print('Type:          ${token.type}');
  print('Amount:        ${amount.unitsPurchased} kWh');
  print('TID time:      ${tid.timeOfIssue.toIso8601String()}');
  print('TID minutes:   ${tid.bitString.value}');
  print('RandomNo:      ${rnd.bitString.value}');
  print(
    'CRC:           '
    '0x${token.crc!.bitString.value.toRadixString(16).padLeft(4, '0')}',
  );
  print('Token:         ${_formatToken(token.tokenNo)}');
  print('Bits (66):     ${token.encryptedTokenBitString}\n');

  // 4. Decode it as a meter would.
  print('--- Decoding (meter side) ---------------------------------');
  final dispatcher = TokenDecoderDispatcher(decoderKey, ea07);
  final result = dispatcher.decodeDecimal(
    '${opts.requestID}.decode',
    token.tokenNo,
  );

  switch (result) {
    case DecodeAccepted(:final token):
      final decoded = token as TransferElectricityCreditToken;
      print('Status:        ACCEPTED');
      print('Type:          ${decoded.type}');
      print(
        'Recovered:     ${decoded.amountPurchased!.unitsPurchased} kWh '
        '@ ${decoded.tokenIdentifier!.bitString.value} min',
      );
      print(
        'CRC matched:   0x'
        '${decoded.crc!.bitString.value.toRadixString(16).padLeft(4, '0')}',
      );
    case DecodeFailure(:final error, :final reason):
      print('Status:        REJECTED');
      print('Error:         ${error.runtimeType}: $reason');
  }
  print('');

  // 5. Same round-trip via the params-driven API (mirrors NectarAPI
  //    tokens-service's flat Map<String,dynamic> request body shape).
  print('--- Params-driven API (NectarAPI-compatible) -------------');
  final paramsRequest = <String, dynamic>{
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
    VirtualHsmParams.baseDate: '1993',
    VirtualHsmParams.amount: opts.amount,
    VirtualHsmParams.tokenId: opts.tidTime.toIso8601String(),
  };
  final paramsToken = hsm.generateToken(
    '${opts.requestID}.params',
    paramsRequest,
  );
  print('Token:         ${_formatToken(paramsToken.tokenNo)}');
  final paramsDecoded =
      hsm.decodeToken(
            '${opts.requestID}.params.decode',
            paramsToken.tokenNo,
            paramsRequest,
          )
          as TransferElectricityCreditToken;
  print(
    'Round-trip OK: ${paramsDecoded.amountPurchased!.unitsPurchased} kWh '
    '@ ${paramsDecoded.tokenIdentifier!.bitString.value} min',
  );
  print('');

  // 6. Class 2 / SubClass 3+4 — STA Decoder Key Change Token pair.
  //    Mint a new decoder key (DKGA-02 with the next KRN) and ship it
  //    to the meter as a 1st + 2nd section pair, encrypted under the
  //    *current* decoder key. The meter would stage these halves, then
  //    rotate to the new key when both have arrived.
  print('--- Class 2 KCT (STA, 1st + 2nd section) -----------------');
  final newKeyStaSta = hsm.deriveDecoderKeyDkga02(
    issuerIdentificationNumber: iin,
    individualAccountIdentificationNumber: iain,
    keyType: keyType,
    supplyGroupCode: sgc,
    tariffIndex: TariffIndex('08'),
    keyRevisionNumber: KeyRevisionNumber(2),
  );
  print(
    'New decoder key: '
    '${newKeyStaSta.keyData.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'
    ' (DKGA-02, KRN=2, TI=08)',
  );

  final kct1 = Set1stSectionDecoderKeyTokenGenerator(
    decoderKey: decoderKey,
    encryptionAlgorithm: ea07,
    keyExpiryNumberHighOrder: KeyExpiryNumberHighOrder(
      BitString.fromValue(0xA, 4),
    ),
    keyRevisionNumber: KeyRevisionNumber(2),
    rolloverKeyChange: RolloverKeyChange.fromBool(false),
    keyType: KeyType(2),
    newDecoderKey: newKeyStaSta,
  ).generateNew('${opts.requestID}.kct.1st');
  final kct2 = Set2ndSectionDecoderKeyTokenGenerator(
    decoderKey: decoderKey,
    encryptionAlgorithm: ea07,
    keyExpiryNumberLowOrder: KeyExpiryNumberLowOrder(
      BitString.fromValue(0xB, 4),
    ),
    tariffIndex: TariffIndex('08'),
    newDecoderKey: newKeyStaSta,
  ).generateNew('${opts.requestID}.kct.2nd');

  print('1st section token: ${_formatToken(kct1.tokenNo)}');
  print('2nd section token: ${_formatToken(kct2.tokenNo)}');

  // Decode both halves and confirm we can rebuild the new key bit-exactly.
  final class2Dec = Class2TokenDecoder(decoderKey, ea07);
  final d1 =
      class2Dec.decodeBinary66(
            '${opts.requestID}.kct.1st.dec',
            kct1.encryptedTokenBitString!,
          )
          as Set1stSectionDecoderKeyToken;
  final d2 =
      class2Dec.decodeBinary66(
            '${opts.requestID}.kct.2nd.dec',
            kct2.encryptedTokenBitString!,
          )
          as Set2ndSectionDecoderKeyToken;
  final rebuilt = combineStaDecoderKey(d1.newKeyHighOrder!, d2.newKeyLowOrder!);
  print(
    'Rebuilt new key: '
    '${rebuilt.keyData.map((b) => b.toRadixString(16).padLeft(2, '0')).join()} '
    '(${rebuilt.keyData.length == newKeyStaSta.keyData.length && _bytesEqual(rebuilt.keyData, newKeyStaSta.keyData) ? 'MATCH' : 'MISMATCH'})',
  );
  print('');

  // 7. Class 2 / SubClass 3+4+8+9 — MISTY1 KCT, full 4-section flow.
  //    MISTY1 carries a 128-bit decoder key, so the rotation needs all
  //    four sections (1st = NKHO, 2nd = NKLO, 3rd = NKMO2 + SGCLO,
  //    4th = NKMO1 + SGCHO). Derive both the current and the new key
  //    via DKGA-04 + MISTY1, then mint and decode all four halves.
  print('--- Class 2 KCT (MISTY1, full 4-section) -----------------');
  final vendingKey160 = VendingCommonDesKey(
    parseHexKey('0123456789ABCDEF0123456789ABCDEF01234567'),
  );
  final dkga04 = ({required int krn, required String ti}) =>
      DecoderKeyGeneratorAlgorithm04(
        baseDate: BaseDate.date1993,
        tariffIndex: TariffIndex(ti),
        supplyGroupCode: sgc,
        keyType: keyType,
        keyRevisionNumber: KeyRevisionNumber(krn),
        encryptionAlgorithm: Misty1EncryptionAlgorithm(),
        meterPan: MeterPrimaryAccountNumber(
          issuerIdentificationNumber: iin,
          individualAccountIdentificationNumber: iain,
        ),
        vendingKey: vendingKey160,
      ).generate();
  final misty1Cur = dkga04(krn: 1, ti: '07');
  final misty1New = dkga04(krn: 2, ti: '08');
  final misty1Ea = Misty1EncryptionAlgorithm();
  print(
    'Current MISTY1 key (16B): '
    '${misty1Cur.keyData.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
  );
  print(
    'New MISTY1 key     (16B): '
    '${misty1New.keyData.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
  );

  final t1 = Set1stSectionDecoderKeyTokenGenerator(
    decoderKey: misty1Cur,
    encryptionAlgorithm: misty1Ea,
    keyExpiryNumberHighOrder: KeyExpiryNumberHighOrder(
      BitString.fromValue(0xA, 4),
    ),
    keyRevisionNumber: KeyRevisionNumber(2),
    rolloverKeyChange: RolloverKeyChange.fromBool(false),
    keyType: KeyType(2),
    newDecoderKey: misty1New,
  ).generateNew('${opts.requestID}.misty1.1');
  final t2 = Set2ndSectionDecoderKeyTokenGenerator(
    decoderKey: misty1Cur,
    encryptionAlgorithm: misty1Ea,
    keyExpiryNumberLowOrder: KeyExpiryNumberLowOrder(
      BitString.fromValue(0xB, 4),
    ),
    tariffIndex: TariffIndex('08'),
    newDecoderKey: misty1New,
  ).generateNew('${opts.requestID}.misty1.2');
  final t3 = Set3rdSectionDecoderKeyTokenGenerator(
    decoderKey: misty1Cur,
    encryptionAlgorithm: misty1Ea,
    supplyGroupCode: sgc,
    newDecoderKey: misty1New,
  ).generateNew('${opts.requestID}.misty1.3');
  final t4 = Set4thSectionDecoderKeyTokenGenerator(
    decoderKey: misty1Cur,
    encryptionAlgorithm: misty1Ea,
    supplyGroupCode: sgc,
    newDecoderKey: misty1New,
  ).generateNew('${opts.requestID}.misty1.4');

  print('1st section token: ${_formatToken(t1.tokenNo)}');
  print('2nd section token: ${_formatToken(t2.tokenNo)}');
  print('3rd section token: ${_formatToken(t3.tokenNo)}');
  print('4th section token: ${_formatToken(t4.tokenNo)}');

  final mistyDec = Class2TokenDecoder(misty1Cur, misty1Ea);
  final m1 =
      mistyDec.decodeBinary66('m1', t1.encryptedTokenBitString!)
          as Set1stSectionDecoderKeyToken;
  final m2 =
      mistyDec.decodeBinary66('m2', t2.encryptedTokenBitString!)
          as Set2ndSectionDecoderKeyToken;
  final m3 =
      mistyDec.decodeBinary66('m3', t3.encryptedTokenBitString!)
          as Set3rdSectionDecoderKeyToken;
  final m4 =
      mistyDec.decodeBinary66('m4', t4.encryptedTokenBitString!)
          as Set4thSectionDecoderKeyToken;
  final rebuiltMisty = combineMisty1DecoderKey(
    m1.newKeyHighOrder!,
    m3.newKeyMiddleOrder2!,
    m4.newKeyMiddleOrder1!,
    m2.newKeyLowOrder!,
  );
  print(
    'Rebuilt MISTY1 key (16B): '
    '${rebuiltMisty.keyData.map((b) => b.toRadixString(16).padLeft(2, '0')).join()} '
    '(${_bytesEqual(rebuiltMisty.keyData, misty1New.keyData) ? 'MATCH' : 'MISMATCH'})',
  );
  print('');
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _formatToken(String tokenNo) {
  if (tokenNo.length != 20) return tokenNo;
  final m = RegExp(r'(\d{4})(\d{4})(\d{4})(\d{4})(\d{4})').firstMatch(tokenNo);
  if (m == null) return tokenNo;
  return '${m[1]}-${m[2]}-${m[3]}-${m[4]}-${m[5]}';
}

class _Opts {
  final double amount;
  final DateTime tidTime;
  final String requestID;
  _Opts(this.amount, this.tidTime, this.requestID);
}

_Opts _parse(List<String> args) {
  var amount = 5.5;
  var tidTime = DateTime.utc(2024, 3, 15, 10, 30);
  var requestID = 'demo-001';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--amount':
        amount = double.parse(args[++i]);
      case '--tid-time':
        tidTime = DateTime.parse(args[++i]).toUtc();
      case '--request-id':
        requestID = args[++i];
      case '-h' || '--help':
        print(
          'Usage: dart run bin/demo.dart '
          '[--amount <kWh>] [--tid-time <ISO8601>] [--request-id <id>]',
        );
        return _Opts(amount, tidTime, requestID);
    }
  }
  return _Opts(amount, tidTime, requestID);
}
