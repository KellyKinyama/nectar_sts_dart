import 'dart:typed_data';

import '../_internal/digest/hmac.dart' as hmac_impl;
import '../_internal/digest/sha.dart' as sha_impl;
import '../domain/base_date.dart';
import '../domain/primitives.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../keys/vending_key.dart';
import 'dkga02.dart' show DecoderKeyGeneratorAlgorithm;

/// DKGA-04: derive a 64-bit (STA) or 128-bit (MISTY1) decoder key from
/// a 160-bit vending key + meter parameters using HMAC-SHA-256 as a
/// KDF.
///
/// Direct port of
/// `generators/decoderkeygenerator/DecoderKeyGeneratorAlgorithm04.java`.
///
/// Data block layout (49 bytes, byte-for-byte equivalent to Nectar's
/// `generateDataBlock` after `charArrayToByteArray`):
///
///   sep1   `0x04 0x02`
///   dkga   `'0' '4'`
///   sep2   `0x02`
///   bd     2 ASCII chars: `"93"` / `"14"` / `"35"`
///   sep3   `0x02`
///   ea     2 ASCII chars: `"07"` / `"11"`
///   sep4   `0x02`
///   ti     2 ASCII digits
///   sep5   `0x00 0x04 0x06`
///   sgc    6 ASCII digits
///   sep6   `0x01`
///   kt     1 ASCII hex digit ('0'..'3')
///   sep7   `0x01`
///   krn    1 ASCII hex digit ('1'..'9')
///   sep8   `0x12`
///   meterpan  18 ASCII digits
///   decoderLength  `0x00 0x00 0x00 0x40` (STA, 64-bit) or
///                  `0x00 0x00 0x00 0x80` (MISTY1, 128-bit)
///
/// Output post-processing:
///   - STA    : first 8 bytes of the HMAC in REVERSE order. This
///              byte-reversal is documented in the Java original as the
///              compatibility shim with the earlier DKGA-02 + EA02
///              implementation referenced by IEC 62055-41:2014.
///   - MISTY1 : first 16 bytes of the HMAC, as-is.
///
/// Example (from `test/dkga_test.dart`, EA07 branch):
/// ```dart
/// final dk = DecoderKeyGeneratorAlgorithm04(
///   baseDate:            BaseDate.date2014,
///   tariffIndex:         TariffIndex('07'),
///   supplyGroupCode:     SupplyGroupCode('123456'),
///   keyType:             KeyType(2),
///   keyRevisionNumber:   KeyRevisionNumber(1),
///   encryptionAlgorithm: StandardTransferAlgorithm(),
///   meterPan: MeterPrimaryAccountNumber(
///     issuerIdentificationNumber:            IssuerIdentificationNumber('600727'),
///     individualAccountIdentificationNumber:
///         IndividualAccountIdentificationNumber('12345678901'),
///   ),
///   // 20-byte (160-bit) HMAC-SHA-256 vending key.
///   vendingKey: VendingUniqueDesKey(List<int>.generate(20, (i) => i + 1)),
/// ).generate();
/// dk.keyData.length; // 8 (STA-sized 64-bit key)
/// ```
class DecoderKeyGeneratorAlgorithm04 extends DecoderKeyGeneratorAlgorithm {
  /// STS reference base date (drives the `bd` field of the data block).
  final BaseDate baseDate;

  /// Two-digit tariff index.
  final TariffIndex tariffIndex;

  /// Six-digit supply group code.
  final SupplyGroupCode supplyGroupCode;

  /// Key type (0=DITK, 1=DDTK, 2=DUTK, 3=DCTK).
  final KeyType keyType;

  /// One-digit key revision number.
  final KeyRevisionNumber keyRevisionNumber;

  /// Chosen block cipher (STA → 64-bit key, MISTY1 → 128-bit key).
  final EncryptionAlgorithm encryptionAlgorithm;

  /// Full 18-digit MeterPAN of the target meter.
  final MeterPrimaryAccountNumber meterPan;

  /// 20-byte (160-bit) vending key used as the HMAC-SHA-256 key.
  final VendingKey vendingKey;

  /// Bundles the parameters DKGA-04 needs to derive a decoder key.
  ///
  /// All arguments are required. The [vendingKey] must be exactly 20
  /// bytes and its length must be consistent with
  /// [encryptionAlgorithm]; otherwise [generate] throws
  /// [EncryptionAlgorithmVendingKeyLengthMismatchException].
  DecoderKeyGeneratorAlgorithm04({
    required this.baseDate,
    required this.tariffIndex,
    required this.supplyGroupCode,
    required this.keyType,
    required this.keyRevisionNumber,
    required this.encryptionAlgorithm,
    required this.meterPan,
    required this.vendingKey,
  });

  /// Mirrors the Java `getName()` which (correctly or not) returns
  /// "DKGA02". We return the actual name.
  @override
  String get name => 'DKGA04';

  /// Runs the DKGA-04 derivation and returns the resulting 64-bit
  /// (STA) or 128-bit (MISTY1) [DecoderKey].
  ///
  /// Throws [EncryptionAlgorithmVendingKeyLengthMismatchException] if
  /// [vendingKey] is not exactly 20 bytes or the chosen
  /// [encryptionAlgorithm] is neither STA nor MISTY1.
  @override
  DecoderKey generate() {
    final int decoderKeyLengthMarker;
    if (encryptionAlgorithm.code == EncryptionAlgorithmCode.sta &&
        vendingKey.keyData.length == 20) {
      decoderKeyLengthMarker = 0x40; // 64 bits
    } else if (encryptionAlgorithm.code == EncryptionAlgorithmCode.misty1 &&
        vendingKey.keyData.length == 20) {
      decoderKeyLengthMarker = 0x80; // 128 bits
    } else {
      throw EncryptionAlgorithmVendingKeyLengthMismatchException(
        'Vending key (${vendingKey.keyData.length} bytes) does not match '
        'encryption algorithm ${encryptionAlgorithm.code.name} '
        '(expected 160-bit / 20-byte key)',
      );
    }

    final dataBlock = _buildDataBlock(decoderKeyLengthMarker);
    final mac = hmac_impl.hmac(
      vendingKey.keyData,
      dataBlock,
      sha_impl.newSha256Digest(),
    );

    if (encryptionAlgorithm.code == EncryptionAlgorithmCode.misty1) {
      return DecoderKey(Uint8List.fromList(mac.sublist(0, 16)));
    }

    final reversed = Uint8List(8);
    for (var i = 0; i < 8; i++) {
      reversed[i] = mac[7 - i];
    }
    return DecoderKey(reversed);
  }

  Uint8List _buildDataBlock(int decoderKeyLengthMarker) {
    final sb = BytesBuilder();
    sb.add([0x04, 0x02]);
    sb.add('04'.codeUnits); // dkga
    sb.add([0x02]);
    sb.add(baseDate.shortCode.codeUnits);
    sb.add([0x02]);
    sb.add(encryptionAlgorithm.code.name.codeUnits);
    sb.add([0x02]);
    sb.add(tariffIndex.value.codeUnits);
    sb.add([0x00, 0x04, 0x06]);
    sb.add(supplyGroupCode.value.codeUnits);
    sb.add([0x01]);
    sb.add(keyType.value.toRadixString(16).codeUnits);
    sb.add([0x01]);
    sb.add(keyRevisionNumber.value.toRadixString(16).codeUnits);
    sb.add([0x12]);
    sb.add(meterPan.meterPanValue.codeUnits);
    sb.add([0x00, 0x00, 0x00, decoderKeyLengthMarker]);
    return sb.toBytes();
  }
}
