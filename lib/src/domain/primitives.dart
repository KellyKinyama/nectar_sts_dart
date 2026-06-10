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

  final String value;
  IssuerIdentificationNumber(this.value) {
    if (!_re6.hasMatch(value) && !_re4zeros.hasMatch(value)) {
      throw InvalidIssuerIdentificationNumberException('Invalid IIN: $value');
    }
  }

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

  final String value;
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

  @override
  String get name => 'Individual Account Identification Number';
}

/// 0 = DITK, 1 = DDTK, 2 = DUTK, 3 = DCTK.
class KeyType implements _Entity {
  final int value;
  KeyType(this.value) {
    if (value < 0 || value > 3) {
      throw InvalidKeyTypeException('Invalid key type: $value');
    }
  }

  @override
  String get name => 'Key Type';
}

class KeyRevisionNumber implements _Entity {
  final int value;
  KeyRevisionNumber(this.value) {
    if (value < 1 || value > 9) {
      throw InvalidKeyRevisionNumberException(
        'Invalid key revision number: $value',
      );
    }
  }

  @override
  String get name => 'Key Revision Number';

  @override
  String toString() => '$value';
}

class TariffIndex implements _Entity {
  static final _re = RegExp(r'^[0-9]{2}$');
  final String value;
  TariffIndex(this.value) {
    if (!_re.hasMatch(value)) {
      throw InvalidTariffIndexException('Invalid tariff index: $value');
    }
  }

  @override
  String get name => 'Tariff Index';
}

class SupplyGroupCode implements _Entity {
  static final _re = RegExp(r'^[0-9]{6}$');
  final String value;
  SupplyGroupCode(this.value) {
    if (!_re.hasMatch(value)) {
      throw InvalidSupplyGroupCodeException(
        'Invalid supply group code: $value',
      );
    }
  }

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
class ControlBlock implements _Entity {
  final KeyType keyType;
  final SupplyGroupCode supplyGroupCode;
  final TariffIndex tariffIndex;
  final KeyRevisionNumber keyRevisionNumber;

  ControlBlock({
    required this.keyType,
    required this.supplyGroupCode,
    required this.tariffIndex,
    required this.keyRevisionNumber,
  });

  String get value =>
      '${keyType.value}${supplyGroupCode.value}${tariffIndex.value}'
      '${keyRevisionNumber.value}FFFFFF';

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
class PrimaryAccountNumberBlock implements _Entity {
  final IssuerIdentificationNumber issuerIdentificationNumber;
  final IndividualAccountIdentificationNumber
  individualAccountIdentificationNumber;
  final KeyType keyType;

  PrimaryAccountNumberBlock({
    required this.issuerIdentificationNumber,
    required this.individualAccountIdentificationNumber,
    required this.keyType,
  });

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
class MeterPrimaryAccountNumber implements _Entity {
  static const _legacyIin = '600727';

  final IssuerIdentificationNumber issuerIdentificationNumber;
  final IndividualAccountIdentificationNumber
  individualAccountIdentificationNumber;
  late final int checkDigit;
  late final String meterPanValue;

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

  @override
  String get name => 'MeterPAN';
}
