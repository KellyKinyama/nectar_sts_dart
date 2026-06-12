// STS compliance test vectors ported from NectarAPI/tokens-service:
//   src/test/java/ke/co/nectar/token/domain/token/
//     STSComplianceTests_STS_531_1_0_02_CTSA11.java
//
// SCOPE:
//   CTSA11 — Class 1 InitiateMeterTest/Display: 16 control-bit sweep
//   rows (powers of 2) exercised against both the 2-digit (8-bit)
//   ManufacturerCode (Subclass 0) and the 4-digit (16-bit)
//   ManufacturerCode (Subclass 1) generators. Manufacturer code is 0
//   throughout; only the control word varies.
//
//   Class 1 tokens are NOT encrypted by the issuer (see
//   `Class1TokenGenerator.generate` in the Dart port). The
//   `decoderKey` / `encryptionAlgorithm` arguments to the generator
//   constructors are accepted for API parity with Class 0/2 only — a
//   dummy decoder key and STA EA are passed below.
import 'dart:typed_data';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

void main() {
  group('STS_531_1_0_02 CTSA11 (Class 1 InitiateMeterTest/Display)', () {
    final dummyKey = DecoderKey(Uint8List(8));
    final ea07 = StandardTransferAlgorithm();
    const requestId = 'request_id';

    final mfg2Digit = ManufacturerCode.fromInt(0, widthBits: 8);
    final mfg4Digit = ManufacturerCode.fromInt(0, widthBits: 16);

    // control, twoDigitExpected, fourDigitExpected
    final rows = <List<Object>>[
      [0x1, '00000000000150997584', '01152921509036054672'],
      [0x2, '00000000000167774880', '01152921513331042448'],
      [0x4, '00000000000201328896', '01152921521920952465'],
      [0x8, '18446744073843772416', '01152921539100838034'],
      [0x10, '36893488147553322496', '01152921573460543637'],
      [0x20, '00000000000671093248', '01152921642180020378'],
      [0x40, '00000000001207974400', '01152921779618973828'],
      [0x80, '00000000002281728512', '01152922054496880824'],
      [0x100, '00000000004429208064', '01152922604252694700'],
      [0x200, '00000000008724195840', '01152923703764322536'],
      [0x400, '00000000017314105857', '01152925902787577952'],
      [0x2000, '00000000137573173770', '01152956689113154192'],
      [0x4000, '00000000275012127252', '01152991873485249680'],
      [0x8000, '00000000549890034216', '01153062242229428368'],
      [0x10000, '00000001099645848124', '01153202979717788816'],
      [0x20000, '00000002199157475960', '01153484454694514832'],
    ];

    for (final r in rows) {
      final control = r[0] as int;
      final twoDigit = r[1] as String;
      final fourDigit = r[2] as String;
      final hex = '0x${control.toRadixString(16)}';

      test('control=$hex, 2-digit mfg (subclass 0) → $twoDigit', () {
        final token = InitiateMeterTestOrDisplay1Token(requestId)
          ..manufacturerCode = mfg2Digit
          ..control = Control(BitString.fromValue(control, 36), mfg2Digit);
        InitiateMeterTestOrDisplay1TokenGenerator(
          dummyKey,
          ea07,
        ).generate(token);
        expect(token.tokenNo, equals(twoDigit));
      });

      test('control=$hex, 4-digit mfg (subclass 1) → $fourDigit', () {
        final token = InitiateMeterTestOrDisplay2Token(requestId)
          ..manufacturerCode = mfg4Digit
          ..control = Control(BitString.fromValue(control, 28), mfg4Digit);
        InitiateMeterTestOrDisplay2TokenGenerator(
          dummyKey,
          ea07,
        ).generate(token);
        expect(token.tokenNo, equals(fourDigit));
      });
    }
  });
}
