import '../base/bit_string.dart';
import '../util/utils.dart';
import 'key.dart';

/// Master key held by the vending system. For DKGA-02 + EA09 this is
/// 8 bytes (single-DES); for DKGA-04 it is 20 bytes (HMAC-SHA-256).
abstract class VendingKey extends Key {
  /// Base constructor for subclasses; forwards [data] to [Key].
  VendingKey([super.data]);

  /// Interprets the key bytes as a character string (each byte becomes
  /// one Unicode code point). Useful when the vending key is
  /// distributed as an ASCII passphrase; for random binary keys the
  /// output may contain unprintable characters.
  @override
  String bitsToString() => String.fromCharCodes(keyData);

  /// View of the key bytes as a [BitString].
  ///
  /// Interprets the first up-to-8 bytes as an unsigned little-endian
  /// integer. For DKGA-04's 20-byte key this returns only the first
  /// 64 bits.
  @override
  BitString get bitString => BitString.fromValue(Utils.bytesToLong(keyData));
}

/// Vending key shared across every meter of an issuer — the default
/// source for common decoder-key derivation via DKGA-02 / DKGA-04.
class VendingCommonDesKey extends VendingKey {
  /// Builds a common vending DES key from an optional byte list.
  VendingCommonDesKey([super.data]);

  /// Returns `"Vending Common DES Key"`.
  @override
  String get name => 'Vending Common DES Key';
}

/// Vending key used as a fallback when no issuer-specific key is
/// available at the meter.
class VendingDefaultDesKey extends VendingKey {
  /// Builds a default vending DES key from an optional byte list.
  VendingDefaultDesKey([super.data]);

  /// Returns `"Vending Default DES Key"`.
  @override
  String get name => 'Vending Default DES Key';
}

/// Vending key that is scoped to a single meter ("unique" variant).
class VendingUniqueDesKey extends VendingKey {
  /// Builds a unique vending DES key from an optional byte list.
  VendingUniqueDesKey([super.data]);

  /// Returns `"Vending Unique DES Key"`.
  @override
  String get name => 'Vending Unique DES Key';
}
