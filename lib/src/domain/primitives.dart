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

  /// Build an IAIN from a manufacturer code + decoder serial number;
  /// the trailing Luhn check digit is computed via Nectar's variant.
  factory IndividualAccountIdentificationNumber.fromComponents({
    required String manufacturerCode,
    required String decoderSerialNumber,
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
    final check = LuhnAlgorithm.generateCheckDigit(int.parse(combined));
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

/// 18-digit Meter Primary Account Number built from an IIN + IAIN.
///
/// Layout: `<IIN><IAIN><checkDigit>`. The check digit is Nectar's
/// (non-standard) Luhn variant over `IIN || IAIN` parsed as an integer.
/// Only the `(IIN, IAIN)` constructor is implemented — the string
/// parsing constructor with legacy-IIN detection is out of scope.
class MeterPrimaryAccountNumber implements _Entity {
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

  @override
  String get name => 'MeterPAN';
}
