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
