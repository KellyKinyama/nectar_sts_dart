import 'dart:typed_data';

import '../base/bit_string.dart';
import '../util/utils.dart';
import 'key.dart';

/// 64-bit symmetric key derived from a vending key + meter parameters
/// by one of the DKGA algorithms.
///
/// Example:
/// ```dart
/// // Wrap the 8-byte output of DKGA-02.
/// final dk = DecoderKey([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]);
/// dk.toString();       // '1122334455667788'
/// dk.keyData.length;   // 8
///
/// // Named-constructor variants set `specialName` for logging.
/// DecoderKey.common(dk.keyData).specialName;   // 'Decoder Common Transfer Key'
/// DecoderKey.unique(dk.keyData).specialName;   // 'Decoder Unique Transfer Key'
/// ```
class DecoderKey extends Key {
  /// Builds a [DecoderKey] from an optional byte list.
  ///
  /// Use one of the named constructors ([DecoderKey.common],
  /// [DecoderKey.defaultTransfer], [DecoderKey.initialization],
  /// [DecoderKey.unique]) when the key needs to advertise a specific
  /// transfer-key role via [specialName].
  DecoderKey([List<int>? data]) : super(data);

  /// Returns `"Decoder Key"`. Named-constructor variants override
  /// [specialName] rather than [name].
  @override
  String get name => 'Decoder Key';

  /// Binary string of the key bytes in **descending** storage order
  /// (byte `N-1` first, byte 0 last). Each byte is MSB-first, padded
  /// to 8 chars.
  @override
  String bitsToString() => _convertByteArrToBinary(keyData);

  /// Binary string of the key bytes in **ascending** storage order
  /// (byte 0 first, byte `N-1` last). Each byte is MSB-first, padded
  /// to 8 chars. Used when splitting a MISTY1 decoder key into KCT
  /// halves.
  String bitsToStringReversed() => _convertByteArrToBinaryReversed(keyData);

  /// View of the (up to) 64-bit key as a [BitString]. Bytes are
  /// interpreted as an unsigned little-endian integer.
  @override
  BitString get bitString => BitString.fromValue(Utils.bytesToLong(keyData));

  /// Lowercase hex dump of the key bytes (2 chars per byte).
  @override
  String toString() => _toHex(keyData);

  /// Sub-classes from the Java original (DecoderCommonTransferKey,
  /// DecoderDefaultTransferKey, DecoderInitializationTransferKey,
  /// DecoderUniqueTransferKey) only override `getName()`. Use named
  /// constructors instead of one-method subclasses.
  ///
  /// Marks this key as a Decoder Common Transfer Key.
  DecoderKey.common([List<int>? data])
      : _name = 'Decoder Common Transfer Key',
        super(data);

  /// Marks this key as a Decoder Default Transfer Key (used when no
  /// issuer-specific key is available).
  DecoderKey.defaultTransfer([List<int>? data])
      : _name = 'Decoder Default Transfer Key',
        super(data);

  /// Marks this key as a Decoder Initialization Transfer Key (used at
  /// meter first-install / factory reset).
  DecoderKey.initialization([List<int>? data])
      : _name = 'Decoder Initialization Transfer Key',
        super(data);

  /// Marks this key as a Decoder Unique Transfer Key (meter-specific,
  /// non-shared).
  DecoderKey.unique([List<int>? data])
      : _name = 'Decoder Unique Transfer Key',
        super(data);

  String? _name;

  /// The transfer-key variant name set by a named constructor, or
  /// falls back to [name] when this instance was built with the
  /// unnamed [DecoderKey] constructor.
  String get specialName => _name ?? name;
}

String _convertByteArrToBinary(Uint8List val) {
  final sb = StringBuffer();
  for (var i = val.length - 1; i >= 0; i--) {
    sb.write(val[i].toRadixString(2).padLeft(8, '0'));
  }
  return sb.toString();
}

String _convertByteArrToBinaryReversed(Uint8List val) {
  final sb = StringBuffer();
  for (var i = 0; i < val.length; i++) {
    sb.write(val[i].toRadixString(2).padLeft(8, '0'));
  }
  return sb.toString();
}

String _toHex(Uint8List val) {
  final sb = StringBuffer();
  for (final b in val) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
