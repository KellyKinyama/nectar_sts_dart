/// All checked / unchecked exceptions used across the algorithm port.
///
/// The Java original splits these across dozens of files
/// (`InvalidBitException`, `InvalidNibbleBitStringException`,
/// `BitConcatOverflowError`, etc.). The Dart port keeps them as a flat
/// set in one place because the algorithm rarely catches them
/// individually — the test usually just wants "did this throw?".
class StsError implements Exception {
  final String message;
  const StsError(this.message);
  @override
  String toString() => '$runtimeType: $message';
}

class InvalidBitException extends StsError {
  const InvalidBitException(super.message);
}

class InvalidBitStringException extends StsError {
  const InvalidBitStringException(super.message);
}

class InvalidNibbleBitStringException extends StsError {
  const InvalidNibbleBitStringException(super.message);
}

class NibbleOutOfRangeException extends StsError {
  const NibbleOutOfRangeException(super.message);
}

class InvalidRangeException extends StsError {
  const InvalidRangeException(super.message);
}

class InvalidRateException extends StsError {
  const InvalidRateException(super.message);
}

class BitConcatOverflowError extends StsError {
  const BitConcatOverflowError(super.message);
}

class IllegalComparisonError extends StsError {
  const IllegalComparisonError(super.message);
}

class InvalidDateTimeBitsException extends StsError {
  const InvalidDateTimeBitsException(super.message);
}

class InvalidUnitsPurchasedBitsException extends StsError {
  const InvalidUnitsPurchasedBitsException(super.message);
}

class InvalidVendingOrDecoderKeyException extends StsError {
  const InvalidVendingOrDecoderKeyException(super.message);
}

class InvalidBaseDateException extends StsError {
  const InvalidBaseDateException(super.message);
}

class InvalidControlException extends StsError {
  const InvalidControlException(super.message);
}

class InvalidControlBitStringException extends StsError {
  const InvalidControlBitStringException(super.message);
}

class InvalidDateOfExpiryException extends StsError {
  const InvalidDateOfExpiryException(super.message);
}

class InvalidDecoderKeyGenerationAlgorithm extends StsError {
  const InvalidDecoderKeyGenerationAlgorithm(super.message);
}

class InvalidDecoderKeyParametersException extends StsError {
  const InvalidDecoderKeyParametersException(super.message);
}

class InvalidDecoderSerialNumberException extends StsError {
  const InvalidDecoderSerialNumberException(super.message);
}

class InvalidDrnCheckDigitException extends StsError {
  const InvalidDrnCheckDigitException(super.message);
}

class InvalidIAINNumberException extends StsError {
  const InvalidIAINNumberException(super.message);
}

class InvalidIndividualAccountIdentificationNumberException extends StsError {
  const InvalidIndividualAccountIdentificationNumberException(super.message);
}

class InvalidIssuerIAINComponents extends StsError {
  const InvalidIssuerIAINComponents(super.message);
}

class InvalidIssuerIdentificationNumberException extends StsError {
  const InvalidIssuerIdentificationNumberException(super.message);
}

class InvalidKenhoException extends StsError {
  const InvalidKenhoException(super.message);
}

class InvalidKenloException extends StsError {
  const InvalidKenloException(super.message);
}

class InvalidKeyDataException extends StsError {
  const InvalidKeyDataException(super.message);
}

class InvalidKeyExpiryNumberException extends StsError {
  const InvalidKeyExpiryNumberException(super.message);
}

class InvalidKeyRevisionNumberException extends StsError {
  const InvalidKeyRevisionNumberException(super.message);
}

class InvalidKeyTypeException extends StsError {
  const InvalidKeyTypeException(super.message);
}

class InvalidManufacturerCodeException extends StsError {
  const InvalidManufacturerCodeException(super.message);
}

class InvalidMeterPanComponentsException extends StsError {
  const InvalidMeterPanComponentsException(super.message);
}

class InvalidMeterPrimaryAccountNumberException extends StsError {
  const InvalidMeterPrimaryAccountNumberException(super.message);
}

class InvalidMplException extends StsError {
  const InvalidMplException(super.message);
}

class InvalidMppulException extends StsError {
  const InvalidMppulException(super.message);
}

class InvalidNewKeyMiddleOrder1Exception extends StsError {
  const InvalidNewKeyMiddleOrder1Exception(super.message);
}

class InvalidNewKeyMiddleOrder2Exception extends StsError {
  const InvalidNewKeyMiddleOrder2Exception(super.message);
}

class InvalidNkhoException extends StsError {
  const InvalidNkhoException(super.message);
}

class InvalidNkloException extends StsError {
  const InvalidNkloException(super.message);
}

class InvalidNoOfStepsException extends StsError {
  const InvalidNoOfStepsException(super.message);
}

class InvalidPadException extends StsError {
  const InvalidPadException(super.message);
}

class InvalidPanCheckDigitException extends StsError {
  const InvalidPanCheckDigitException(super.message);
}

class InvalidPrimaryAccountNumberBlockComponentsException extends StsError {
  const InvalidPrimaryAccountNumberBlockComponentsException(super.message);
}

class InvalidRegisterBitStringException extends StsError {
  const InvalidRegisterBitStringException(super.message);
}

class InvalidRollOverKeyChangeException extends StsError {
  const InvalidRollOverKeyChangeException(super.message);
}

class InvalidRndBitsNoException extends StsError {
  const InvalidRndBitsNoException(super.message);
}

class InvalidRndNoException extends StsError {
  const InvalidRndNoException(super.message);
}

class InvalidSgchoException extends StsError {
  const InvalidSgchoException(super.message);
}

class InvalidSgcloException extends StsError {
  const InvalidSgcloException(super.message);
}

class InvalidSupplyGroupCodeException extends StsError {
  const InvalidSupplyGroupCodeException(super.message);
}

class InvalidTariffIndexException extends StsError {
  const InvalidTariffIndexException(super.message);
}

class InvalidTokenClassException extends StsError {
  const InvalidTokenClassException(super.message);
}

class InvalidTokenException extends StsError {
  const InvalidTokenException(super.message);
}

class InvalidTokenSubclassException extends StsError {
  const InvalidTokenSubclassException(super.message);
}

class InvalidUnitsPurchasedException extends StsError {
  const InvalidUnitsPurchasedException(super.message);
}

class InvalidWmfException extends StsError {
  const InvalidWmfException(super.message);
}

class CharactersNotDigitException extends StsError {
  const CharactersNotDigitException(super.message);
}

class EncryptionAlgorithmVendingKeyLengthMismatchException extends StsError {
  const EncryptionAlgorithmVendingKeyLengthMismatchException(super.message);
}

class NotImplementedException extends StsError {
  const NotImplementedException(super.message);
}

class TokenNotFoundException extends StsError {
  const TokenNotFoundException(super.message);
}

class TokenPropertyNotFoundException extends StsError {
  const TokenPropertyNotFoundException(super.message);
}

class UnsupportedTokenStrategyException extends StsError {
  const UnsupportedTokenStrategyException(super.message);
}

// ---------------------------------------------------------------------------
// Decoder-side error hierarchy (Java's `decoder.error.*`). Surfaced as
// exceptions because the meter-state-machine port isn't built yet.
// ---------------------------------------------------------------------------

class CrcError extends StsError {
  const CrcError(super.message);
}

class KeyExpiredError extends StsError {
  const KeyExpiredError(super.message);
}

class KeyTypeError extends StsError {
  const KeyTypeError(super.message);
}

class TokenError extends StsError {
  const TokenError(super.message);
}

class RangeError_ extends StsError {
  const RangeError_(super.message);
}

class OldTokenError extends StsError {
  const OldTokenError(super.message);
}

class UsedTokenError extends StsError {
  const UsedTokenError(super.message);
}
