import 'dart:typed_data';

import '../base/bit_string.dart';
import '../util/utils.dart';
import 'key.dart';

/// 64-bit symmetric key derived from a vending key + meter parameters
/// by one of the DKGA algorithms.
class DecoderKey extends Key {
  DecoderKey([List<int>? data]) : super(data);

  @override
  String get name => 'Decoder Key';

  @override
  String bitsToString() => _convertByteArrToBinary(keyData);

  String bitsToStringReversed() => _convertByteArrToBinaryReversed(keyData);

  @override
  BitString get bitString => BitString.fromValue(Utils.bytesToLong(keyData));

  @override
  String toString() => _toHex(keyData);

  /// Sub-classes from the Java original (DecoderCommonTransferKey,
  /// DecoderDefaultTransferKey, DecoderInitializationTransferKey,
  /// DecoderUniqueTransferKey) only override `getName()`. Use named
  /// constructors instead of one-method subclasses.
  DecoderKey.common([List<int>? data])
    : _name = 'Decoder Common Transfer Key',
      super(data);
  DecoderKey.defaultTransfer([List<int>? data])
    : _name = 'Decoder Default Transfer Key',
      super(data);
  DecoderKey.initialization([List<int>? data])
    : _name = 'Decoder Initialization Transfer Key',
      super(data);
  DecoderKey.unique([List<int>? data])
    : _name = 'Decoder Unique Transfer Key',
      super(data);

  String? _name;

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
