/// Domain primitives used by Class 2 Key-Change tokens.
///
/// Mirrors the upstream Java types under
/// `ke.co.nectar.token.domain.{KeyExpiryNumber*, NewKey*, RolloverKeyChange,
/// _3KCT}` and `domain.supplygroupcode.{SupplyGroupCodeHighOrder,
/// SupplyGroupCodeLowOrder}`. All values are LSB-first BitString-backed
/// wrappers; widths are validated at construction.
library;

import 'dart:typed_data';

import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import 'primitives.dart';

/// Full 8-bit Key Expiry Number (KEN). Carried split across two
/// 4-bit halves on the wire (KENHO + KENLO).
class KeyExpiryNumber {
  final int value;

  KeyExpiryNumber(this.value) {
    if (value < 0 || value > 255) {
      throw const InvalidKeyExpiryNumberException(
        'Key Expiry Number must be 0..255',
      );
    }
  }

  /// Reassemble KEN from its high- and low-order halves.
  factory KeyExpiryNumber.fromHighAndLow(
    KeyExpiryNumberHighOrder high,
    KeyExpiryNumberLowOrder low,
  ) => KeyExpiryNumber((high.bitString.value << 4) | low.bitString.value);

  KeyExpiryNumberHighOrder get high =>
      KeyExpiryNumberHighOrder(BitString.fromValue((value >> 4) & 0xF, 4));

  KeyExpiryNumberLowOrder get low =>
      KeyExpiryNumberLowOrder(BitString.fromValue(value & 0xF, 4));

  String get name => 'Key Expiry Number';

  @override
  String toString() => '$value';
}

/// High-order nibble of the Key Expiry Number, carried in the 1st
/// Section Decoder Key Change Token (bits 56..59 of the data block).
class KeyExpiryNumberHighOrder {
  final BitString bitString;

  KeyExpiryNumberHighOrder(this.bitString) {
    if (bitString.length != 4) {
      throw const InvalidKenhoException('KENHO must be exactly 4 bits');
    }
  }

  int get value => bitString.value;
  String get name => 'Key Expiry Number High Order';
}

/// Low-order nibble of the Key Expiry Number, carried in the 2nd
/// Section Decoder Key Change Token (bits 56..59 of the data block).
class KeyExpiryNumberLowOrder {
  final BitString bitString;

  KeyExpiryNumberLowOrder(this.bitString) {
    if (bitString.length != 4) {
      throw const InvalidKenloException('KENLO must be exactly 4 bits');
    }
  }

  int get value => bitString.value;
  String get name => 'Key Expiry Number Low Order';
}

/// High-order 32 bits of a new 64-bit decoder key, carried in the
/// 1st Section KCT (bits 16..47 of the data block).
class NewKeyHighOrder {
  final BitString bitString;

  NewKeyHighOrder(this.bitString) {
    if (bitString.length != 32) {
      throw const InvalidNkhoException('NKHO must be exactly 32 bits');
    }
  }

  String get name => 'New Key High Order';
}

/// Low-order 32 bits of a new 64-bit decoder key, carried in the
/// 2nd Section KCT (bits 16..47 of the data block).
class NewKeyLowOrder {
  final BitString bitString;

  NewKeyLowOrder(this.bitString) {
    if (bitString.length != 32) {
      throw const InvalidNkloException('NKLO must be exactly 32 bits');
    }
  }

  String get name => 'New Key Low Order';
}

/// Middle-order 1 of a new 128-bit MISTY1 decoder key (3rd / 4th
/// section KCT — MISTY1 path only, currently out of scope).
class NewKeyMiddleOrder1 {
  final BitString bitString;

  NewKeyMiddleOrder1(this.bitString) {
    if (bitString.length != 32) {
      throw const InvalidNewKeyMiddleOrder1Exception(
        'NKMO1 must be exactly 32 bits',
      );
    }
  }

  String get name => 'New Key Middle Order 1';
}

/// Middle-order 2 of a new 128-bit MISTY1 decoder key (3rd / 4th
/// section KCT — MISTY1 path only, currently out of scope).
class NewKeyMiddleOrder2 {
  final BitString bitString;

  NewKeyMiddleOrder2(this.bitString) {
    if (bitString.length != 32) {
      throw const InvalidNewKeyMiddleOrder2Exception(
        'NKMO2 must be exactly 32 bits',
      );
    }
  }

  String get name => 'New Key Middle Order 2';
}

/// 1-bit Rollover Key Change (RO) flag carried in the 1st Section
/// KCT. RO=0 → simple key change, RO=1 → key rollover (the old key
/// remains valid for an in-flight grace period).
class RolloverKeyChange {
  final BitString bitString;

  RolloverKeyChange(this.bitString) {
    if (bitString.length != 1) {
      throw const InvalidRollOverKeyChangeException(
        'RolloverKeyChange must be exactly 1 bit',
      );
    }
  }

  factory RolloverKeyChange.fromBool(bool rollover) =>
      RolloverKeyChange(BitString.fromValue(rollover ? 1 : 0, 1));

  bool get isRollover => bitString.value == 1;
  String get name => 'Roll Over Key Change';
}

/// Reserved 1-bit field (`_3KCT` / Res_B) in the 1st Section KCT.
/// Always 0 for 64-bit decoder key transfer. The Java code names it
/// `_3KCT` because in the 128-bit transfer flow this bit indicates
/// that a 3rd-section KCT is part of the pending set.
class Reserved3Kct {
  final BitString bitString;

  Reserved3Kct(this.bitString) {
    if (bitString.length != 1) {
      throw const InvalidBitStringException('_3KCT must be exactly 1 bit');
    }
  }

  factory Reserved3Kct.zero() => Reserved3Kct(BitString.fromValue(0, 1));

  String get name => '_3KCT';
}

/// High-order 12 bits of a new Supply Group Code, carried in the
/// 4th Section KCT (MISTY1 path only).
class SupplyGroupCodeHighOrder {
  final BitString bitString;

  SupplyGroupCodeHighOrder(this.bitString) {
    if (bitString.length != 12) {
      throw const InvalidSgchoException('SGCHO must be exactly 12 bits');
    }
  }

  /// Mirrors Java `SupplyGroupCodeHighOrder(SupplyGroupCode)` — zero-
  /// pads the SGC's decimal value to 24 bits and keeps the top 12.
  factory SupplyGroupCodeHighOrder.fromSupplyGroupCode(SupplyGroupCode sgc) {
    final v = int.parse(sgc.value);
    final bin = v.toRadixString(2).padLeft(24, '0');
    return SupplyGroupCodeHighOrder(BitString.fromBinary(bin.substring(0, 12)));
  }

  String get name => 'Supply Group Code High Order';
}

/// Low-order 12 bits of a new Supply Group Code, carried in the
/// 3rd Section KCT (MISTY1 path only).
class SupplyGroupCodeLowOrder {
  final BitString bitString;

  SupplyGroupCodeLowOrder(this.bitString) {
    if (bitString.length != 12) {
      throw const InvalidSgcloException('SGCLO must be exactly 12 bits');
    }
  }

  /// Mirrors Java `SupplyGroupCodeLowOrder(SupplyGroupCode)` — zero-
  /// pads the SGC's decimal value to 24 bits and keeps the bottom 12.
  factory SupplyGroupCodeLowOrder.fromSupplyGroupCode(SupplyGroupCode sgc) {
    final v = int.parse(sgc.value);
    final bin = v.toRadixString(2).padLeft(24, '0');
    return SupplyGroupCodeLowOrder(BitString.fromBinary(bin.substring(12, 24)));
  }

  String get name => 'Supply Group Code Low Order';
}

/// Split a 64-bit STA [DecoderKey] into (NKHO, NKLO).
///
/// Mirrors the Java generator's `newDecoderKey.bitsToString()
/// .substring(0, 32)` / `.substring(32, 64)`. `bitsToString` walks
/// the key bytes in reverse (byte 7 first, byte 0 last), each as
/// 8-bit MSB-first — so:
///
///   NKHO = bytes 7..4 (MSB-first per byte)
///   NKLO = bytes 3..0 (MSB-first per byte)
({NewKeyHighOrder high, NewKeyLowOrder low}) splitStaDecoderKey(
  DecoderKey key,
) {
  final s = key.bitsToString();
  if (s.length != 64) {
    throw const InvalidKeyDataException(
      'STA decoder key must be exactly 64 bits',
    );
  }
  final hi = BitString.fromBinary(s.substring(0, 32));
  final lo = BitString.fromBinary(s.substring(32, 64));
  return (high: NewKeyHighOrder(hi), low: NewKeyLowOrder(lo));
}

/// Inverse of [splitStaDecoderKey]: combine NKHO + NKLO back into a
/// 64-bit decoder key. Used by the meter when both Decoder Key
/// Change Token sections have arrived.
DecoderKey combineStaDecoderKey(NewKeyHighOrder high, NewKeyLowOrder low) {
  final combined =
      '${high.bitString.toPaddedBinary()}'
      '${low.bitString.toPaddedBinary()}';
  if (combined.length != 64) {
    throw const InvalidKeyDataException(
      'combined NKHO+NKLO must be exactly 64 bits',
    );
  }
  final bytes = Uint8List(8);
  for (var chunk = 0; chunk < 8; chunk++) {
    final byteIdx = 7 - chunk;
    bytes[byteIdx] = int.parse(
      combined.substring(chunk * 8, chunk * 8 + 8),
      radix: 2,
    );
  }
  return DecoderKey(bytes);
}

/// Split a 128-bit MISTY1 [DecoderKey] into the four 32-bit halves
/// carried by 1st/2nd/3rd/4th Section KCTs.
///
/// Mirrors Java `newDecoderKey.bitsToStringReversed().substring(...)`:
/// `bitsToStringReversed` walks bytes in index order (byte 0 first,
/// byte 15 last), each as 8-bit MSB-first — so the 128-bit string is
/// the key in big-endian byte order. The 4 halves are then:
///
///   NKHO  = bytes 0..3   (1st section)
///   NKMO2 = bytes 4..7   (3rd section)
///   NKMO1 = bytes 8..11  (4th section)
///   NKLO  = bytes 12..15 (2nd section)
({
  NewKeyHighOrder high,
  NewKeyMiddleOrder2 middle2,
  NewKeyMiddleOrder1 middle1,
  NewKeyLowOrder low,
})
splitMisty1DecoderKey(DecoderKey key) {
  final s = key.bitsToStringReversed();
  if (s.length != 128) {
    throw const InvalidKeyDataException(
      'MISTY1 decoder key must be exactly 128 bits',
    );
  }
  return (
    high: NewKeyHighOrder(BitString.fromBinary(s.substring(0, 32))),
    middle2: NewKeyMiddleOrder2(BitString.fromBinary(s.substring(32, 64))),
    middle1: NewKeyMiddleOrder1(BitString.fromBinary(s.substring(64, 96))),
    low: NewKeyLowOrder(BitString.fromBinary(s.substring(96, 128))),
  );
}

/// Inverse of [splitMisty1DecoderKey]: assemble the four halves into
/// a 16-byte MISTY1 decoder key, in big-endian byte order matching
/// what `bitsToStringReversed` produced on the way in.
DecoderKey combineMisty1DecoderKey(
  NewKeyHighOrder high,
  NewKeyMiddleOrder2 middle2,
  NewKeyMiddleOrder1 middle1,
  NewKeyLowOrder low,
) {
  final combined =
      '${high.bitString.toPaddedBinary()}'
      '${middle2.bitString.toPaddedBinary()}'
      '${middle1.bitString.toPaddedBinary()}'
      '${low.bitString.toPaddedBinary()}';
  if (combined.length != 128) {
    throw const InvalidKeyDataException(
      'combined MISTY1 key halves must be exactly 128 bits',
    );
  }
  final bytes = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    bytes[i] = int.parse(combined.substring(i * 8, i * 8 + 8), radix: 2);
  }
  return DecoderKey(bytes);
}
