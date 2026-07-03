import 'dart:typed_data';

import '../domain/primitives.dart';
import '../encryption/data_encryption_algorithm.dart';
import '../keys/decoder_key.dart';
import '../keys/vending_key.dart';

/// Common surface shared by `DecoderKeyGeneratorAlgorithm02` and
/// `DecoderKeyGeneratorAlgorithm04`.
abstract class DecoderKeyGeneratorAlgorithm {
  /// Short identifier of the algorithm (`"DKGA02"`, `"DKGA04"`).
  String get name;

  /// Runs the derivation and returns the resulting [DecoderKey].
  ///
  /// The width of the returned key is 64 bits (STA/DEA) or 128 bits
  /// (MISTY1 via DKGA-04).
  DecoderKey generate();
}

/// XOR two equal-length byte buffers into a fresh `Uint8List`.
Uint8List xorBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    throw ArgumentError('xor requires equal-length buffers');
  }
  final out = Uint8List(a.length);
  for (var i = 0; i < a.length; i++) {
    out[i] = (a[i] ^ b[i]) & 0xFF;
  }
  return out;
}

/// Decode a 16-char hex string into 8 bytes (big-endian nibble order).
Uint8List hexDecode8(String hex) {
  if (hex.length != 16) {
    throw ArgumentError(
      'hexDecode8 expects exactly 16 hex chars, got ${hex.length}: $hex',
    );
  }
  final out = Uint8List(8);
  for (var i = 0; i < 8; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// DKGA-02: derive a 64-bit decoder key from a vending key + PAN block
/// + control block using DES-ECB as the one-way step.
///
/// Direct port of
/// `generators/decoderkeygenerator/DecoderKeyGeneratorAlgorithm02.java`.
///
/// Flow:
///   1. panBlock = hex_decode(PrimaryAccountNumberBlock)   // 8 bytes
///   2. ctlBlock = hex_decode(ControlBlock)                // 8 bytes
///   3. mixed    = panBlock XOR ctlBlock
///   4. enc      = DES_ECB(vendingKey, mixed)
///   5. doubled  = enc XOR mixed                            // (1)
///   6. derived  = doubled XOR vendingKey
///   7. result   = reverse_bytes(derived)
///
/// (1) The XOR-with-input dance after DES is the IEC 62055-41
/// "key-derivation" construction — it turns the one-way DES step into
/// a Davies-Meyer-flavored compression.
///
/// Example (from `test/dkga_test.dart`):
/// ```dart
/// final dk = DecoderKeyGeneratorAlgorithm02(
///   keyType:           KeyType(2),
///   supplyGroupCode:   SupplyGroupCode('123456'),
///   tariffIndex:       TariffIndex('07'),
///   keyRevisionNumber: KeyRevisionNumber(1),
///   issuerIdentificationNumber:            IssuerIdentificationNumber('600727'),
///   individualAccountIdentificationNumber:
///       IndividualAccountIdentificationNumber('12345678901'),
///   vendingKey: VendingCommonDesKey(
///     [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF],
///   ),
/// ).generate();
/// dk.keyData.length; // 8 (64-bit derived DES key)
/// ```
class DecoderKeyGeneratorAlgorithm02 extends DecoderKeyGeneratorAlgorithm {
  /// Issuer Identification Number (4 or 6 digits).
  final IssuerIdentificationNumber issuerIdentificationNumber;

  /// Individual Account Identification Number (11 or 13 digits).
  final IndividualAccountIdentificationNumber
      individualAccountIdentificationNumber;

  /// Key type (0=DITK, 1=DDTK, 2=DUTK, 3=DCTK).
  final KeyType keyType;

  /// Six-digit supply group code.
  final SupplyGroupCode supplyGroupCode;

  /// Two-digit tariff index.
  final TariffIndex tariffIndex;

  /// One-digit key revision number.
  final KeyRevisionNumber keyRevisionNumber;

  /// 8-byte DES vending key that seeds the derivation.
  final VendingKey vendingKey;

  /// Bundles the meter and issuer parameters DKGA-02 needs to derive
  /// a decoder key. All arguments are required; call [generate] to
  /// perform the derivation.
  DecoderKeyGeneratorAlgorithm02({
    required this.keyType,
    required this.supplyGroupCode,
    required this.tariffIndex,
    required this.keyRevisionNumber,
    required this.issuerIdentificationNumber,
    required this.individualAccountIdentificationNumber,
    required this.vendingKey,
  });

  /// Returns `"DKGA02"`.
  @override
  String get name => 'DKGA02';

  /// Runs the DKGA-02 derivation and returns the resulting 64-bit
  /// [DecoderKey].
  @override
  DecoderKey generate() {
    final panBlock = PrimaryAccountNumberBlock(
      issuerIdentificationNumber: issuerIdentificationNumber,
      individualAccountIdentificationNumber:
          individualAccountIdentificationNumber,
      keyType: keyType,
    );
    final ctlBlock = ControlBlock(
      keyType: keyType,
      supplyGroupCode: supplyGroupCode,
      tariffIndex: tariffIndex,
      keyRevisionNumber: keyRevisionNumber,
    );

    final panBytes = hexDecode8(panBlock.value);
    final ctlBytes = hexDecode8(ctlBlock.value);
    final mixed = xorBytes(panBytes, ctlBytes);

    final ea09 = DataEncryptionAlgorithm();
    final enc = ea09.encryptBytes(vendingKey.keyData, mixed);
    final doubled = xorBytes(enc, mixed);
    final derived = xorBytes(doubled, vendingKey.keyData);

    return DecoderKey(_reverseBytes(derived));
  }

  static Uint8List _reverseBytes(Uint8List input) {
    final out = Uint8List(input.length);
    for (var i = 0; i < input.length; i++) {
      out[i] = input[input.length - 1 - i];
    }
    return out;
  }
}
