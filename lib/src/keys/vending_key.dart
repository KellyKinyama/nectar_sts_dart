import '../base/bit_string.dart';
import '../util/utils.dart';
import 'key.dart';

/// Master key held by the vending system. For DKGA-02 + EA09 this is
/// 8 bytes (single-DES); for DKGA-04 it is 20 bytes (HMAC-SHA-256).
abstract class VendingKey extends Key {
  VendingKey([super.data]);

  @override
  String bitsToString() => String.fromCharCodes(keyData);

  @override
  BitString get bitString => BitString.fromValue(Utils.bytesToLong(keyData));
}

class VendingCommonDesKey extends VendingKey {
  VendingCommonDesKey([super.data]);
  @override
  String get name => 'Vending Common DES Key';
}

class VendingDefaultDesKey extends VendingKey {
  VendingDefaultDesKey([super.data]);
  @override
  String get name => 'Vending Default DES Key';
}

class VendingUniqueDesKey extends VendingKey {
  VendingUniqueDesKey([super.data]);
  @override
  String get name => 'Vending Unique DES Key';
}
