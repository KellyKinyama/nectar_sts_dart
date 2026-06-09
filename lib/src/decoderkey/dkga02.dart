import 'dart:typed_data';

import '../domain/primitives.dart';
import '../encryption/data_encryption_algorithm.dart';
import '../keys/decoder_key.dart';
import '../keys/vending_key.dart';

/// Common surface shared by `DecoderKeyGeneratorAlgorithm02` and
/// `DecoderKeyGeneratorAlgorithm04`.
abstract class DecoderKeyGeneratorAlgorithm {
  String get name;
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
class DecoderKeyGeneratorAlgorithm02 extends DecoderKeyGeneratorAlgorithm {
  final IssuerIdentificationNumber issuerIdentificationNumber;
  final IndividualAccountIdentificationNumber
  individualAccountIdentificationNumber;
  final KeyType keyType;
  final SupplyGroupCode supplyGroupCode;
  final TariffIndex tariffIndex;
  final KeyRevisionNumber keyRevisionNumber;
  final VendingKey vendingKey;

  DecoderKeyGeneratorAlgorithm02({
    required this.keyType,
    required this.supplyGroupCode,
    required this.tariffIndex,
    required this.keyRevisionNumber,
    required this.issuerIdentificationNumber,
    required this.individualAccountIdentificationNumber,
    required this.vendingKey,
  });

  @override
  String get name => 'DKGA02';

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
