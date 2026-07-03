import 'dart:typed_data';

import '../decoderkey/dkga02.dart';
import '../decoderkey/dkga04.dart';
import '../domain/base_date.dart';
import '../domain/primitives.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../keys/vending_key.dart';

/// Abstract HSM (Hardware Security Module) interface for STS key
/// derivation. The vending key is the long-term shared secret between
/// the issuing back-office and the meter; an HSM typically never lets
/// the vending key leave protected hardware. Host code instead calls
/// these methods and the HSM does the DKGA computation inside the
/// secure boundary, returning the derived decoder key.
abstract class Hsm {
  /// Short human-readable label (`"VirtualHsm"` /
  /// `"PrismHsm(...)"`) used in logs and error messages.
  String get name;

  /// Run DKGA-02 (DES-based) to derive a decoder key.
  DecoderKey deriveDecoderKeyDkga02({
    required IssuerIdentificationNumber issuerIdentificationNumber,
    required IndividualAccountIdentificationNumber
        individualAccountIdentificationNumber,
    required KeyType keyType,
    required SupplyGroupCode supplyGroupCode,
    required TariffIndex tariffIndex,
    required KeyRevisionNumber keyRevisionNumber,
  });

  /// Run DKGA-04 (HMAC-SHA256-based). Requires a 160-bit (20-byte)
  /// vending key and an encryption algorithm (STA=EA07 or MISTY1=EA11;
  /// this port only supports STA).
  DecoderKey deriveDecoderKeyDkga04({
    required BaseDate baseDate,
    required TariffIndex tariffIndex,
    required SupplyGroupCode supplyGroupCode,
    required KeyType keyType,
    required KeyRevisionNumber keyRevisionNumber,
    required EncryptionAlgorithm encryptionAlgorithm,
    required MeterPrimaryAccountNumber meterPan,
  });
}

/// Virtual (software) HSM: runs DKGA-02 / DKGA-04 in this Dart
/// process. The vending key sits in plain memory.
///
/// Mirrors NectarAPI's terminology — the api-gateway README describes
/// its in-process implementation as the "internal virtual HSM" (vs.
/// the external Prism HSM reached over Thrift). Use this for unit
/// tests, embedded apps, demos, and any deployment where holding the
/// vending key in process memory is acceptable. For production
/// vending behind real hardware, plug in [PrismHsm].
///
/// Example (from `test/dkga_test.dart`):
/// ```dart
/// final hsm = VirtualHsm(
///   VendingCommonDesKey([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]),
/// );
///
/// final decoderKey = hsm.deriveDecoderKeyDkga02(
///   issuerIdentificationNumber:            IssuerIdentificationNumber('600727'),
///   individualAccountIdentificationNumber:
///       IndividualAccountIdentificationNumber('12345678901'),
///   keyType:                               KeyType(2),
///   supplyGroupCode:                       SupplyGroupCode('123456'),
///   tariffIndex:                           TariffIndex('07'),
///   keyRevisionNumber:                     KeyRevisionNumber(1),
/// );
/// decoderKey.keyData.length; // 8
/// ```
class VirtualHsm extends Hsm {
  /// Long-term shared vending master key. In real hardware this
  /// would live behind a secure boundary; here it sits in process
  /// memory.
  final VendingKey vendingKey;

  /// Wraps a plain-memory [vendingKey].
  VirtualHsm(this.vendingKey);

  /// Constant `"VirtualHsm"`.
  @override
  String get name => 'VirtualHsm';

  @override
  DecoderKey deriveDecoderKeyDkga02({
    required IssuerIdentificationNumber issuerIdentificationNumber,
    required IndividualAccountIdentificationNumber
        individualAccountIdentificationNumber,
    required KeyType keyType,
    required SupplyGroupCode supplyGroupCode,
    required TariffIndex tariffIndex,
    required KeyRevisionNumber keyRevisionNumber,
  }) {
    return DecoderKeyGeneratorAlgorithm02(
      keyType: keyType,
      supplyGroupCode: supplyGroupCode,
      tariffIndex: tariffIndex,
      keyRevisionNumber: keyRevisionNumber,
      issuerIdentificationNumber: issuerIdentificationNumber,
      individualAccountIdentificationNumber:
          individualAccountIdentificationNumber,
      vendingKey: vendingKey,
    ).generate();
  }

  @override
  DecoderKey deriveDecoderKeyDkga04({
    required BaseDate baseDate,
    required TariffIndex tariffIndex,
    required SupplyGroupCode supplyGroupCode,
    required KeyType keyType,
    required KeyRevisionNumber keyRevisionNumber,
    required EncryptionAlgorithm encryptionAlgorithm,
    required MeterPrimaryAccountNumber meterPan,
  }) {
    return DecoderKeyGeneratorAlgorithm04(
      baseDate: baseDate,
      tariffIndex: tariffIndex,
      supplyGroupCode: supplyGroupCode,
      keyType: keyType,
      keyRevisionNumber: keyRevisionNumber,
      encryptionAlgorithm: encryptionAlgorithm,
      meterPan: meterPan,
      vendingKey: vendingKey,
    ).generate();
  }
}

/// Placeholder for a real Prism HSM (Utimaco / Thales payShield /
/// other PKCS#11 device). The real implementation would speak the
/// vendor's management protocol over TCP / PKCS#11 / HSE.
///
/// The original `nectar/tokens-service` uses Prism for production
/// vending — that integration is OUT OF SCOPE for this algorithm-core
/// port. All derivation methods throw [NotImplementedException].
class PrismHsm extends Hsm {
  /// Prism HSM host (DNS name or IP).
  final String host;

  /// Prism HSM TCP port.
  final int port;

  /// Optional client certificate used to authenticate to the HSM.
  final Uint8List? clientCertificate;

  /// Binds the connection parameters; nothing is opened until a
  /// derivation call is made (currently all throw
  /// [NotImplementedException]).
  PrismHsm({required this.host, required this.port, this.clientCertificate});

  /// `"PrismHsm(host=<host>, port=<port>)"`.
  @override
  String get name => 'PrismHsm(host=$host, port=$port)';

  Never _stub(String method) {
    throw NotImplementedException(
      'PrismHsm.$method is a stub. The Prism HSM integration is out of '
      'scope for the nectar_sts_dart algorithm core; wire up your real '
      'HSM client here, or use VirtualHsm for in-process key derivation.',
    );
  }

  @override
  DecoderKey deriveDecoderKeyDkga02({
    required IssuerIdentificationNumber issuerIdentificationNumber,
    required IndividualAccountIdentificationNumber
        individualAccountIdentificationNumber,
    required KeyType keyType,
    required SupplyGroupCode supplyGroupCode,
    required TariffIndex tariffIndex,
    required KeyRevisionNumber keyRevisionNumber,
  }) =>
      _stub('deriveDecoderKeyDkga02');

  @override
  DecoderKey deriveDecoderKeyDkga04({
    required BaseDate baseDate,
    required TariffIndex tariffIndex,
    required SupplyGroupCode supplyGroupCode,
    required KeyType keyType,
    required KeyRevisionNumber keyRevisionNumber,
    required EncryptionAlgorithm encryptionAlgorithm,
    required MeterPrimaryAccountNumber meterPan,
  }) =>
      _stub('deriveDecoderKeyDkga04');
}
