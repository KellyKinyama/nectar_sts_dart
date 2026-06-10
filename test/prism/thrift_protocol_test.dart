/// Round-trip + boundary tests for the hand-rolled Thrift binary
/// protocol primitives in `lib/src/prism/thrift_binary_protocol.dart`.
///
/// These don't touch sockets — they're pure encoder/decoder tests.
library;

import 'package:nectar_sts_dart/src/prism/thrift_binary_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('BinaryWriter / BinaryReader primitives', () {
    test('byte / bool / i16 / i32 / i64 / double round-trip', () {
      final w = BinaryWriter();
      w.writeByte(0x7f);
      w.writeBool(true);
      w.writeBool(false);
      w.writeI16(-12345);
      w.writeI32(0x01020304);
      w.writeI64(0x0102030405060708);
      w.writeDouble(3.14159265358979);

      final r = BinaryReader(w.takeBytes());
      expect(r.readByte(), 0x7f);
      expect(r.readBool(), isTrue);
      expect(r.readBool(), isFalse);
      expect(r.readI16(), -12345);
      expect(r.readI32(), 0x01020304);
      expect(r.readI64(), 0x0102030405060708);
      expect(r.readDouble(), closeTo(3.14159265358979, 1e-12));
    });

    test('binary + string round-trip including empty + utf-8', () {
      final w = BinaryWriter();
      w.writeString('');
      w.writeString('hello');
      w.writeString('Crédit:Électricité');

      final r = BinaryReader(w.takeBytes());
      expect(r.readString(), '');
      expect(r.readString(), 'hello');
      expect(r.readString(), 'Crédit:Électricité');
    });

    test('MessageBegin strict-header round-trip preserves seq + type', () {
      final w = BinaryWriter();
      w.writeMessageBegin(TMessage('issueCreditToken', TMessageType.call, 42));
      w.writeFieldStop();

      final r = BinaryReader(w.takeBytes());
      final hdr = r.readMessageBegin();
      expect(hdr.name, 'issueCreditToken');
      expect(hdr.type, TMessageType.call);
      expect(hdr.seqId, 42);
      // Trailing field-stop.
      final (t, _) = r.readFieldBegin();
      expect(t, TType.stop);
    });

    test('list<i32> round-trip preserves element type + count', () {
      final w = BinaryWriter();
      w.writeListBegin(TType.i32, 3);
      w.writeI32(10);
      w.writeI32(20);
      w.writeI32(30);

      final r = BinaryReader(w.takeBytes());
      final (et, n) = r.readListBegin();
      expect(et, TType.i32);
      expect(n, 3);
      expect([r.readI32(), r.readI32(), r.readI32()], [10, 20, 30]);
    });
  });

  group('BinaryReader.skip', () {
    test('skips unknown primitive fields without disturbing layout', () {
      final w = BinaryWriter();
      // Unknown i64 field id=99 then known string field id=1.
      w.writeFieldBegin(TType.i64, 99);
      w.writeI64(0xdeadbeef);
      w.writeFieldBegin(TType.string, 1);
      w.writeString('kept');
      w.writeFieldStop();

      final r = BinaryReader(w.takeBytes());
      String? got;
      while (true) {
        final (t, id) = r.readFieldBegin();
        if (t == TType.stop) break;
        if (id == 1 && t == TType.string) {
          got = r.readString();
        } else {
          r.skip(t);
        }
      }
      expect(got, 'kept');
    });

    test('skips nested struct + list payload', () {
      final w = BinaryWriter();
      // Unknown struct field id=7 containing a list<i16>.
      w.writeFieldBegin(TType.struct, 7);
      w.writeFieldBegin(TType.list, 1);
      w.writeListBegin(TType.i16, 4);
      w.writeI16(1);
      w.writeI16(2);
      w.writeI16(3);
      w.writeI16(4);
      w.writeFieldStop();
      // Then a known string field id=2.
      w.writeFieldBegin(TType.string, 2);
      w.writeString('after');
      w.writeFieldStop();

      final r = BinaryReader(w.takeBytes());
      String? got;
      while (true) {
        final (t, id) = r.readFieldBegin();
        if (t == TType.stop) break;
        if (id == 2 && t == TType.string) {
          got = r.readString();
        } else {
          r.skip(t);
        }
      }
      expect(got, 'after');
    });
  });
}
