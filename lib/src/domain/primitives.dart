/// Value objects from `ke.co.nectar.token.domain.*` that DKGA-02 and
/// DKGA-04 need.
///
/// Consolidated into a single file because each Java class is a thin
/// validated string/int wrapper. The asymmetric MeterPAN parsing logic
/// (manufacturer code, decoder serial number, DRN check digit splitting,
/// legacy IIN handling) is deliberately kept out of scope — we only
/// implement the (IIN, IAIN) constructor that the demo + DKGA path use.
library;

import '../exceptions/exceptions.dart';
import '../util/luhn.dart';

abstract class _Entity {
  String get name;
}

/// Issuer Identification Number — 6 digits, or `"0000"` (the 4-digit
/// "zeros" variant used when the IAIN is the full 13-digit form).
class IssuerIdentificationNumber implements _Entity {
  static final _re6 = RegExp(r'^[0-9]{6}$');
  static final _re4zeros = RegExp(r'^0{4}$');

  /// Digit string (`"NNNNNN"` or `"0000"`).
  final String value;

  /// Validates and stores [value].
  ///
  /// Accepts either a 6-digit numeric string or the special
  /// 4-digit `"0000"` marker; anything else throws
  /// [InvalidIssuerIdentificationNumberException].
  IssuerIdentificationNumber(this.value) {
    if (!_re6.hasMatch(value) && !_re4zeros.hasMatch(value)) {
      throw InvalidIssuerIdentificationNumberException('Invalid IIN: $value');
    }
  }

  /// Human-readable field name (`"Issuer Identification Number"`).
  @override
  String get name => 'Issuer Identification Number';
}

/// Individual Account Identification Number.
///
/// Holds the **already-formed** IAIN string. Two valid shapes:
///   - 11 digits  (2-digit manufacturer code + 8-digit DSN + 1-digit Luhn)
///   - 13 digits  (4-digit manufacturer code + 8-digit DSN + 1-digit Luhn)
///
/// We do not split / recompute the Luhn check digit here — callers
/// that need to derive the check digit from a manufacturer+DSN pair
/// should use [IndividualAccountIdentificationNumber.fromComponents].
class IndividualAccountIdentificationNumber implements _Entity {
  static final _re = RegExp(r'^([0-9]{11}|[0-9]{13})$');

  /// Digit string (11 or 13 digits).
  final String value;

  /// Validates and stores [value] as-is.
  ///
  /// Rejects anything that is not exactly 11 or 13 numeric digits with
  /// [InvalidIndividualAccountIdentificationNumberException]. Use
  /// [IndividualAccountIdentificationNumber.fromComponents] when you
  /// need the trailing Luhn check digit derived automatically.
  IndividualAccountIdentificationNumber(this.value) {
    if (!_re.hasMatch(value)) {
      throw InvalidIndividualAccountIdentificationNumberException(
        'Invalid IAIN: $value',
      );
    }
  }

  /// Build an IAIN from a manufacturer code + decoder serial number.
  ///
  /// If [drnCheckDigit] is null the trailing Luhn check digit is
  /// computed via Nectar's variant; otherwise the supplied digit is
  /// trusted verbatim (mirrors the Java 3-arg constructor used by
  /// `MeterPrimaryAccountNumber` in NO_METER_PAN_VALIDATION mode).
  factory IndividualAccountIdentificationNumber.fromComponents({
    required String manufacturerCode,
    required String decoderSerialNumber,
    int? drnCheckDigit,
  }) {
    if (!(RegExp(r'^([0-9]{2}|[0-9]{4})$').hasMatch(manufacturerCode))) {
      throw InvalidManufacturerCodeException(
        'Invalid manufacturer code: $manufacturerCode',
      );
    }
    if (!RegExp(r'^[0-9]{8}$').hasMatch(decoderSerialNumber)) {
      throw InvalidDecoderSerialNumberException(
        'Invalid decoder serial number: $decoderSerialNumber',
      );
    }
    final combined = '$manufacturerCode$decoderSerialNumber';
    final check =
        drnCheckDigit ?? LuhnAlgorithm.generateCheckDigit(int.parse(combined));
    if (check < 0 || check > 9) {
      throw InvalidDrnCheckDigitException(
        'DRN check digit must be 0..9: $check',
      );
    }
    return IndividualAccountIdentificationNumber('$combined$check');
  }

  /// Human-readable field name.
  @override
  String get name => 'Individual Account Identification Number';
}

/// 0 = DITK, 1 = DDTK, 2 = DUTK, 3 = DCTK.
class KeyType implements _Entity {
  /// Integer key-type code in `0..3`.
  final int value;

  /// Validates and stores [value]; values outside `0..3` throw
  /// [InvalidKeyTypeException].
  KeyType(this.value) {
    if (value < 0 || value > 3) {
      throw InvalidKeyTypeException('Invalid key type: $value');
    }
  }

  /// Human-readable field name.
  @override
  String get name => 'Key Type';
}

/// Key Revision Number (`1..9`).
///
/// Rolls over as issuers rotate the master vending key; presented on
/// every non-KCT token so the meter can pick the right decoder key.
class KeyRevisionNumber implements _Entity {
  /// Integer KRN in `1..9`.
  final int value;

  /// Validates and stores [value]; values outside `1..9` throw
  /// [InvalidKeyRevisionNumberException].
  KeyRevisionNumber(this.value) {
    if (value < 1 || value > 9) {
      throw InvalidKeyRevisionNumberException(
        'Invalid key revision number: $value',
      );
    }
  }

  /// Human-readable field name.
  @override
  String get name => 'Key Revision Number';

  /// Returns the decimal digit as a string.
  @override
  String toString() => '$value';
}

/// Two-digit tariff index (`"00"`..`"99"`).
///
/// Meter-side lookup key that ties a token to a rate table. Stored as
/// a string to preserve the leading zero.
class TariffIndex implements _Entity {
  static final _re = RegExp(r'^[0-9]{2}$');

  /// Two-digit numeric string.
  final String value;

  /// Validates and stores [value]; non 2-digit input throws
  /// [InvalidTariffIndexException].
  TariffIndex(this.value) {
    if (!_re.hasMatch(value)) {
      throw InvalidTariffIndexException('Invalid tariff index: $value');
    }
  }

  /// Human-readable field name.
  @override
  String get name => 'Tariff Index';
}

/// Six-digit Supply Group Code (`"NNNNNN"`).
///
/// Identifies the utility supply zone; part of the [ControlBlock] used
/// during decoder-key derivation.
class SupplyGroupCode implements _Entity {
  static final _re = RegExp(r'^[0-9]{6}$');

  /// Six-digit numeric string.
  final String value;

  /// Validates and stores [value]; non 6-digit input throws
  /// [InvalidSupplyGroupCodeException].
  SupplyGroupCode(this.value) {
    if (!_re.hasMatch(value)) {
      throw InvalidSupplyGroupCodeException(
        'Invalid supply group code: $value',
      );
    }
  }

  /// Human-readable field name.
  @override
  String get name => 'Supply Group Code';
}

/// Hex-encoded 8-byte control block that DKGA-02 XORs with the PAN
/// block before encryption. Format (16 hex chars):
///   `<KT><SGC><TI><KRN>FFFFFF`
///
///   - KT  : 1 hex digit  (0..3, decimal printed as-is)
///   - SGC : 6 hex digits
///   - TI  : 2 hex digits
///   - KRN : 1 hex digit  (1..9, decimal printed as-is)
///   - then 6 'F' nibbles of padding (the `maximumPhasePowerUnbalanceLimit`
///     field, hard-coded to all-ones in the Nectar code).
///
/// Example (from `test/dkga_test.dart`):
/// ```dart
/// final cb = ControlBlock(
///   keyType:           KeyType(2),
///   supplyGroupCode:   SupplyGroupCode('123456'),
///   tariffIndex:       TariffIndex('07'),
///   keyRevisionNumber: KeyRevisionNumber(1),
/// );
/// cb.value; // '2123456071FFFFFF'
/// ```
class ControlBlock implements _Entity {
  /// Key type (drives the DKGA branch).
  final KeyType keyType;

  /// Six-digit supply group code.
  final SupplyGroupCode supplyGroupCode;

  /// Two-digit tariff index.
  final TariffIndex tariffIndex;

  /// One-digit key revision number.
  final KeyRevisionNumber keyRevisionNumber;

  /// Bundles the four fields that make up the DKGA control block.
  ControlBlock({
    required this.keyType,
    required this.supplyGroupCode,
    required this.tariffIndex,
    required this.keyRevisionNumber,
  });

  /// The concatenated 16-hex-digit control block string documented on
  /// the class.
  String get value =>
      '${keyType.value}${supplyGroupCode.value}${tariffIndex.value}'
      '${keyRevisionNumber.value}FFFFFF';

  /// Human-readable field name.
  @override
  String get name => 'ControlBlock';
}

/// Hex-encoded 8-byte primary-account-number block. Layout depends on
/// IIN length:
///
/// - 6-digit IIN: last 5 digits of IIN + last 11 digits of IAIN.
/// - 4-digit IIN (`"0000"`): last 3 digits of IIN + last 13 digits of IAIN.
///
/// For KT == 3 (DCTK / common transfer key) the IAIN portion is
/// replaced by zeros — the meter-specific bits are stripped because the
/// derived key isn't tied to a single meter.
///
/// Example (from `test/dkga_test.dart`):
/// ```dart
/// // 6-digit IIN keeps last 5 of IIN + last 11 of IAIN.
/// final pan = PrimaryAccountNumberBlock(
///   issuerIdentificationNumber:           IssuerIdentificationNumber('600727'),
///   individualAccountIdentificationNumber:
///       IndividualAccountIdentificationNumber('12345678901'),
///   keyType: KeyType(2),
/// );
/// pan.value; // '0072712345678901'
///
/// // KT=3 (Common Transfer Key) zeros the IAIN portion.
/// PrimaryAccountNumberBlock(
///   issuerIdentificationNumber:           IssuerIdentificationNumber('600727'),
///   individualAccountIdentificationNumber:
///       IndividualAccountIdentificationNumber('12345678901'),
///   keyType: KeyType(3),
/// ).value; // '0072700000000000'
/// ```
class PrimaryAccountNumberBlock implements _Entity {
  /// IIN portion — 6 or 4 digits.
  final IssuerIdentificationNumber issuerIdentificationNumber;

  /// IAIN portion — 11 or 13 digits.
  final IndividualAccountIdentificationNumber
      individualAccountIdentificationNumber;

  /// Key type; drives whether the IAIN is zeroed (KT == 3).
  final KeyType keyType;

  /// Bundles the fields that make up the DKGA PAN block.
  PrimaryAccountNumberBlock({
    required this.issuerIdentificationNumber,
    required this.individualAccountIdentificationNumber,
    required this.keyType,
  });

  /// The concatenated 16-hex-digit PAN block string documented on the
  /// class.
  ///
  /// Throws [InvalidPrimaryAccountNumberBlockComponentsException] when
  /// [issuerIdentificationNumber] has a length other than 4 or 6.
  String get value {
    final iin = issuerIdentificationNumber.value;
    final iain = individualAccountIdentificationNumber.value;
    if (keyType.value == 0 || keyType.value == 1 || keyType.value == 2) {
      if (iin.length == 6) {
        return iin.substring(iin.length - 5) + iain.substring(iain.length - 11);
      }
      if (iin.length == 4) {
        return iin.substring(iin.length - 3) + iain.substring(iain.length - 13);
      }
    } else if (keyType.value == 3) {
      if (iin.length == 6) {
        return '${iin.substring(iin.length - 5)}00000000000';
      }
      if (iin.length == 4) {
        return '${iin.substring(iin.length - 3)}0000000000000';
      }
    }
    throw const InvalidPrimaryAccountNumberBlockComponentsException(
      'IIN length must be 4 or 6 to build a PAN block',
    );
  }

  /// Human-readable field name.
  @override
  String get name => 'Primary Account Number Block';
}

/// Validation mode for the [MeterPrimaryAccountNumber.fromString]
/// parser. Mirrors the Java
/// `MeterPrimaryAccountNumber.Validate` enum used by the upstream
/// `tokens-service` test suite.
enum MeterPanValidation { validate, skip }

/// 18-digit Meter Primary Account Number built from an IIN + IAIN.
///
/// Layout: `<IIN><IAIN><checkDigit>`. The check digit is Nectar's
/// (non-standard) Luhn variant over `IIN || IAIN` parsed as an integer.
///
/// Construction:
///   - `MeterPrimaryAccountNumber({iin, iain})` — build from already
///     validated components.
///   - `MeterPrimaryAccountNumber.fromString(panStr, validate: ...)`
///     — parse an 18-digit MeterPAN string. With the legacy `600727`
///     prefix the IIN is `"600727"` and the manufacturer code is the
///     2-digit slice `panStr[6..8]`; otherwise the IIN collapses to
///     `"0000"` and the manufacturer code is the 4-digit slice
///     `panStr[4..8]`. The DSN is always `panStr[8..16]`, the
///     extracted DRN check digit is `panStr[len-2]`, and the PAN
///     check digit is `panStr[len-1]`.
///
/// Example (from `test/meter_pan_parser_test.dart`):
/// ```dart
/// final pan = MeterPrimaryAccountNumber.fromString(
///   '600727000000000009',
///   validate: MeterPanValidation.skip,
/// );
/// pan.issuerIdentificationNumber.value;           // '600727'
/// pan.individualAccountIdentificationNumber.value; // '00000000000'
/// ```
class MeterPrimaryAccountNumber implements _Entity {
  static const _legacyIin = '600727';

  /// IIN portion of the MeterPAN.
  final IssuerIdentificationNumber issuerIdentificationNumber;

  /// IAIN portion of the MeterPAN.
  final IndividualAccountIdentificationNumber
      individualAccountIdentificationNumber;

  /// Nectar-variant Luhn check digit appended to `IIN || IAIN`.
  late final int checkDigit;

  /// The full 18-digit MeterPAN string.
  late final String meterPanValue;

  /// Builds a MeterPAN from an already-validated IIN + IAIN pair.
  ///
  /// Enforces `iin.length + iain.length == 17` and the STS constraint
  /// that a 13-digit IAIN pairs with the `"0000"` IIN. Throws
  /// [InvalidMeterPanComponentsException] or
  /// [InvalidMeterPrimaryAccountNumberException] on violation.
  MeterPrimaryAccountNumber({
    required this.issuerIdentificationNumber,
    required this.individualAccountIdentificationNumber,
  }) {
    final iin = issuerIdentificationNumber.value;
    final iain = individualAccountIdentificationNumber.value;
    final iinLen = iin.length;
    final iainLen = iain.length;
    final ok = (iinLen == 4 && iainLen == 13) || (iinLen == 6 && iainLen == 11);
    if (!ok) {
      throw const InvalidMeterPanComponentsException(
        'IIN+IAIN combined length must be 17 digits',
      );
    }
    if (iainLen == 13 && iin != '0000') {
      throw const InvalidMeterPanComponentsException(
        '13-digit IAIN requires the 4-digit zeros IIN',
      );
    }
    final combined = '$iin$iain';
    checkDigit = LuhnAlgorithm.generateCheckDigit(int.parse(combined));
    meterPanValue = '$combined$checkDigit';
    if (meterPanValue.length != 18) {
      throw const InvalidMeterPrimaryAccountNumberException(
        'Generated MeterPAN must be exactly 18 digits',
      );
    }
  }

  /// Parse an 18-digit MeterPAN string. Mirrors the upstream Java
  /// `MeterPrimaryAccountNumber(String, Validate)` constructor.
  ///
  /// - With [MeterPanValidation.validate] (default) the extracted DRN
  ///   check digit must equal the Luhn check of the manufacturer code
  ///   + DSN, and the extracted PAN check digit must equal the Luhn
  ///   check of IIN ‖ IAIN. The Java compliance suite exercises this
  ///   path via `CTSA17` with the 22-digit string
  ///   `"1234567890411111111113"` — the DRN slice mismatches, so the
  ///   parser throws [InvalidIAINNumberException].
  /// - With [MeterPanValidation.skip] the extracted DRN check digit is
  ///   trusted verbatim and no PAN check verification runs. The
  ///   compliance vectors use this mode (e.g.
  ///   `"600727000000000009"`, `"000001000000000082"`).
  factory MeterPrimaryAccountNumber.fromString(
    String pan, {
    MeterPanValidation validate = MeterPanValidation.validate,
  }) {
    if (pan.length < 18 || !RegExp(r'^[0-9]+$').hasMatch(pan)) {
      throw const InvalidMeterPrimaryAccountNumberException(
        'MeterPAN must contain at least 18 digits',
      );
    }
    final isLegacy = pan.startsWith(_legacyIin);
    final iin = IssuerIdentificationNumber(isLegacy ? _legacyIin : '0000');
    final mfg = isLegacy ? pan.substring(6, 8) : pan.substring(4, 8);
    final dsn = pan.substring(8, 16);
    final extractedDrnCheckDigit = int.parse(
      pan.substring(pan.length - 2, pan.length - 1),
    );
    final extractedPanCheckDigit = int.parse(
      pan.substring(pan.length - 1, pan.length),
    );

    final IndividualAccountIdentificationNumber iain;
    switch (validate) {
      case MeterPanValidation.validate:
        iain = IndividualAccountIdentificationNumber.fromComponents(
          manufacturerCode: mfg,
          decoderSerialNumber: dsn,
        );
        final computedDrn = int.parse(
          iain.value.substring(iain.value.length - 1),
        );
        if (computedDrn != extractedDrnCheckDigit) {
          throw const InvalidIAINNumberException(
            'Invalid Individual Account Identification Number',
          );
        }
        break;
      case MeterPanValidation.skip:
        iain = IndividualAccountIdentificationNumber.fromComponents(
          manufacturerCode: mfg,
          decoderSerialNumber: dsn,
          drnCheckDigit: extractedDrnCheckDigit,
        );
        break;
    }

    final result = MeterPrimaryAccountNumber(
      issuerIdentificationNumber: iin,
      individualAccountIdentificationNumber: iain,
    );
    if (validate == MeterPanValidation.validate &&
        result.checkDigit != extractedPanCheckDigit) {
      throw const InvalidMeterPrimaryAccountNumberException(
        'Invalid Meter Primary Account Number',
      );
    }
    return result;
  }

  /// Human-readable field name.
  @override
  String get name => 'MeterPAN';
}
