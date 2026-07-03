/// All checked / unchecked exceptions used across the algorithm port.
///
/// The Java original splits these across dozens of files
/// (`InvalidBitException`, `InvalidNibbleBitStringException`,
/// `BitConcatOverflowError`, etc.). The Dart port keeps them as a flat
/// set in one place because the algorithm rarely catches them
/// individually — the test usually just wants "did this throw?".
/// Base class for every algorithm-layer exception in this port.
///
/// Subclasses only carry a human-readable [message]. Catch [StsError]
/// to trap any algorithm-level failure without listing every specific
/// subtype; catch a specific subtype when you need to react to a
/// particular failure mode (e.g. [CrcError] on the decoder path).
class StsError implements Exception {
  /// Human-readable description of what failed.
  final String message;

  /// Creates an [StsError] carrying [message].
  const StsError(this.message);

  /// Returns `"<RuntimeType>: <message>"`.
  @override
  String toString() => '$runtimeType: $message';
}

/// Raised when a bit value is not `0` / `1` (or `'0'` / `'1'`).
class InvalidBitException extends StsError {
  const InvalidBitException(super.message);
}

/// Raised when a `BitString` is empty, too long, or contains a
/// non-binary character.
class InvalidBitStringException extends StsError {
  const InvalidBitStringException(super.message);
}

/// Raised when a `Nibble` is constructed from a `BitString` whose value
/// exceeds `0xF`.
class InvalidNibbleBitStringException extends StsError {
  const InvalidNibbleBitStringException(super.message);
}

/// Raised when a nibble index is outside `[0, length / 4)`.
class NibbleOutOfRangeException extends StsError {
  const NibbleOutOfRangeException(super.message);
}

/// Raised when a bit-range operation is called with `to < from` or a
/// span exceeding 64 bits.
class InvalidRangeException extends StsError {
  const InvalidRangeException(super.message);
}

/// Raised when a numeric rate parameter is outside its allowed domain.
class InvalidRateException extends StsError {
  const InvalidRateException(super.message);
}

/// Raised when concatenating `BitString`s would produce more than 64
/// bits.
class BitConcatOverflowError extends StsError {
  const BitConcatOverflowError(super.message);
}

/// Raised when two `BitString`s of different lengths are compared with
/// `compareTo`.
class IllegalComparisonError extends StsError {
  const IllegalComparisonError(super.message);
}

/// Raised when a token's date/time bit-field is malformed.
class InvalidDateTimeBitsException extends StsError {
  const InvalidDateTimeBitsException(super.message);
}

/// Raised when a units-purchased bit-field is malformed or out of
/// range.
class InvalidUnitsPurchasedBitsException extends StsError {
  const InvalidUnitsPurchasedBitsException(super.message);
}

/// Raised when a vending / decoder key parameter fails STS validation.
class InvalidVendingOrDecoderKeyException extends StsError {
  const InvalidVendingOrDecoderKeyException(super.message);
}

/// Raised when a base-date value is not a legal STS reference date.
class InvalidBaseDateException extends StsError {
  const InvalidBaseDateException(super.message);
}

/// Raised when a token control field is malformed.
class InvalidControlException extends StsError {
  const InvalidControlException(super.message);
}

/// Raised when a control `BitString` fails structural validation.
class InvalidControlBitStringException extends StsError {
  const InvalidControlBitStringException(super.message);
}

/// Raised when a key's date-of-expiry field is invalid.
class InvalidDateOfExpiryException extends StsError {
  const InvalidDateOfExpiryException(super.message);
}

/// Raised when an unknown / unsupported DKGA identifier is supplied.
class InvalidDecoderKeyGenerationAlgorithm extends StsError {
  const InvalidDecoderKeyGenerationAlgorithm(super.message);
}

/// Raised when parameters passed to a DKGA fail validation.
class InvalidDecoderKeyParametersException extends StsError {
  const InvalidDecoderKeyParametersException(super.message);
}

/// Raised when a decoder serial number is malformed or fails a check
/// digit.
class InvalidDecoderSerialNumberException extends StsError {
  const InvalidDecoderSerialNumberException(super.message);
}

/// Raised when a DRN check digit does not match the payload.
class InvalidDrnCheckDigitException extends StsError {
  const InvalidDrnCheckDigitException(super.message);
}

/// Raised when an IAIN (Individual Account Identification Number) is
/// malformed.
class InvalidIAINNumberException extends StsError {
  const InvalidIAINNumberException(super.message);
}

/// Raised when the components of an Individual Account Identification
/// Number fail composition rules.
class InvalidIndividualAccountIdentificationNumberException extends StsError {
  const InvalidIndividualAccountIdentificationNumberException(super.message);
}

/// Raised when issuer-IAIN components are inconsistent.
class InvalidIssuerIAINComponents extends StsError {
  const InvalidIssuerIAINComponents(super.message);
}

/// Raised when an Issuer Identification Number (IIN) fails STS
/// validation.
class InvalidIssuerIdentificationNumberException extends StsError {
  const InvalidIssuerIdentificationNumberException(super.message);
}

/// Raised when `KENHO` (Key Encryption / Higher Order) is invalid.
class InvalidKenhoException extends StsError {
  const InvalidKenhoException(super.message);
}

/// Raised when `KENLO` (Key Encryption / Lower Order) is invalid.
class InvalidKenloException extends StsError {
  const InvalidKenloException(super.message);
}

/// Raised when the raw key material bytes are the wrong length /
/// shape.
class InvalidKeyDataException extends StsError {
  const InvalidKeyDataException(super.message);
}

/// Raised when the Key Expiry Number (KEN) is out of range.
class InvalidKeyExpiryNumberException extends StsError {
  const InvalidKeyExpiryNumberException(super.message);
}

/// Raised when the Key Revision Number (KRN) is out of range.
class InvalidKeyRevisionNumberException extends StsError {
  const InvalidKeyRevisionNumberException(super.message);
}

/// Raised when a Key Type field does not match any STS-defined value.
class InvalidKeyTypeException extends StsError {
  const InvalidKeyTypeException(super.message);
}

/// Raised when a manufacturer code is not a recognised STS value.
class InvalidManufacturerCodeException extends StsError {
  const InvalidManufacturerCodeException(super.message);
}

/// Raised when the components that make up a meter PAN are
/// inconsistent.
class InvalidMeterPanComponentsException extends StsError {
  const InvalidMeterPanComponentsException(super.message);
}

/// Raised when a full Meter Primary Account Number is malformed or
/// fails its check digit.
class InvalidMeterPrimaryAccountNumberException extends StsError {
  const InvalidMeterPrimaryAccountNumberException(super.message);
}

/// Raised when the MPL (Maximum Power Limit) register value is
/// invalid.
class InvalidMplException extends StsError {
  const InvalidMplException(super.message);
}

/// Raised when the MPPUL (Maximum Power Purchase Unit Limit) is
/// invalid.
class InvalidMppulException extends StsError {
  const InvalidMppulException(super.message);
}

/// Raised when the New-Key Middle-Order-1 field is malformed during
/// KCT construction.
class InvalidNewKeyMiddleOrder1Exception extends StsError {
  const InvalidNewKeyMiddleOrder1Exception(super.message);
}

/// Raised when the New-Key Middle-Order-2 field is malformed during
/// KCT construction.
class InvalidNewKeyMiddleOrder2Exception extends StsError {
  const InvalidNewKeyMiddleOrder2Exception(super.message);
}

/// Raised when `NKHO` (New-Key Higher-Order) is invalid.
class InvalidNkhoException extends StsError {
  const InvalidNkhoException(super.message);
}

/// Raised when `NKLO` (New-Key Lower-Order) is invalid.
class InvalidNkloException extends StsError {
  const InvalidNkloException(super.message);
}

/// Raised when a step count parameter is not in the allowed STS range.
class InvalidNoOfStepsException extends StsError {
  const InvalidNoOfStepsException(super.message);
}

/// Raised when a PAD field (padding / test-token filler) is malformed.
class InvalidPadException extends StsError {
  const InvalidPadException(super.message);
}

/// Raised when a PAN check digit does not match the payload.
class InvalidPanCheckDigitException extends StsError {
  const InvalidPanCheckDigitException(super.message);
}

/// Raised when the components used to build a Primary Account Number
/// block are inconsistent.
class InvalidPrimaryAccountNumberBlockComponentsException extends StsError {
  const InvalidPrimaryAccountNumberBlockComponentsException(super.message);
}

/// Raised when a Register bitstring (Class 2 payload register) is
/// malformed.
class InvalidRegisterBitStringException extends StsError {
  const InvalidRegisterBitStringException(super.message);
}

/// Raised when a roll-over Key Change Token (KCT) is inconsistent.
class InvalidRollOverKeyChangeException extends StsError {
  const InvalidRollOverKeyChangeException(super.message);
}

/// Raised when a random-number bit-width parameter is out of range.
class InvalidRndBitsNoException extends StsError {
  const InvalidRndBitsNoException(super.message);
}

/// Raised when a random-number value is malformed.
class InvalidRndNoException extends StsError {
  const InvalidRndNoException(super.message);
}

/// Raised when `SGCHO` (Supply Group Code Higher Order) is invalid.
class InvalidSgchoException extends StsError {
  const InvalidSgchoException(super.message);
}

/// Raised when `SGCLO` (Supply Group Code Lower Order) is invalid.
class InvalidSgcloException extends StsError {
  const InvalidSgcloException(super.message);
}

/// Raised when a Supply Group Code (SGC) is malformed.
class InvalidSupplyGroupCodeException extends StsError {
  const InvalidSupplyGroupCodeException(super.message);
}

/// Raised when a tariff index is outside the STS-defined range.
class InvalidTariffIndexException extends StsError {
  const InvalidTariffIndexException(super.message);
}

/// Raised when a Token Class value is not a recognised STS class.
class InvalidTokenClassException extends StsError {
  const InvalidTokenClassException(super.message);
}

/// Raised for any structurally invalid token (used as a catch-all).
class InvalidTokenException extends StsError {
  const InvalidTokenException(super.message);
}

/// Raised when a Token Subclass value is not recognised.
class InvalidTokenSubclassException extends StsError {
  const InvalidTokenSubclassException(super.message);
}

/// Raised when a units-purchased value fails range validation.
class InvalidUnitsPurchasedException extends StsError {
  const InvalidUnitsPurchasedException(super.message);
}

/// Raised when a Water Meter Factor field is malformed.
class InvalidWmfException extends StsError {
  const InvalidWmfException(super.message);
}

/// Raised when a numeric input contains non-digit characters.
class CharactersNotDigitException extends StsError {
  const CharactersNotDigitException(super.message);
}

/// Raised when the vending-key length does not match what the chosen
/// encryption algorithm requires.
class EncryptionAlgorithmVendingKeyLengthMismatchException extends StsError {
  const EncryptionAlgorithmVendingKeyLengthMismatchException(super.message);
}

/// Raised when a code path deliberately marks a feature as not yet
/// ported.
class NotImplementedException extends StsError {
  const NotImplementedException(super.message);
}

/// Raised when a token cannot be located in a store / registry.
class TokenNotFoundException extends StsError {
  const TokenNotFoundException(super.message);
}

/// Raised when a required property is missing from a token payload.
class TokenPropertyNotFoundException extends StsError {
  const TokenPropertyNotFoundException(super.message);
}

/// Raised when a token type has no supported generator / decoder
/// strategy configured.
class UnsupportedTokenStrategyException extends StsError {
  const UnsupportedTokenStrategyException(super.message);
}

// ---------------------------------------------------------------------------
// Decoder-side error hierarchy (Java's `decoder.error.*`). Surfaced as
// exceptions because the meter-state-machine port isn't built yet.
// ---------------------------------------------------------------------------

/// Raised by the decoder when a token's CRC does not verify.
class CrcError extends StsError {
  const CrcError(super.message);
}

/// Raised by the decoder when the presented key has expired against
/// the meter clock.
class KeyExpiredError extends StsError {
  const KeyExpiredError(super.message);
}

/// Raised by the decoder when the token key-type does not match the
/// meter's expectation.
class KeyTypeError extends StsError {
  const KeyTypeError(super.message);
}

/// Generic decoder-side rejection when no more-specific error applies.
class TokenError extends StsError {
  const TokenError(super.message);
}

/// Raised by the decoder when a value would place a register outside
/// its allowed range. Named with a trailing underscore to avoid clash
/// with `dart:core`'s `RangeError`.
class RangeError_ extends StsError {
  const RangeError_(super.message);
}

/// Raised by the decoder when a token's TID is older than the meter's
/// last-seen watermark.
class OldTokenError extends StsError {
  const OldTokenError(super.message);
}

/// Raised by the decoder when a token's TID has already been consumed.
class UsedTokenError extends StsError {
  const UsedTokenError(super.message);
}
