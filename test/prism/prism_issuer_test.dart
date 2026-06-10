/// Integration test for `PrismIssuer.generateToken` end-to-end:
/// fake Thrift server → `TokenApiClient` → issuer mapping back into
/// a Dart `TransferElectricityCreditToken`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nectar_sts_dart/src/hsm/virtual_hsm_dispatch.dart';
import 'package:nectar_sts_dart/src/prism/thrift_binary_protocol.dart';
import 'package:nectar_sts_dart/src/server/token_issuer.dart';
import 'package:nectar_sts_dart/src/token/class0_tokens.dart';
import 'package:test/test.dart';

typedef _Handler = Uint8List Function(TMessage call, BinaryReader args);

class _FakeServer {
  final ServerSocket _server;
  final Map<String, _Handler> _handlers;

  _FakeServer._(this._server, this._handlers) {
    _server.listen(_serve);
  }

  static Future<_FakeServer> bind(Map<String, _Handler> handlers) async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeServer._(s, handlers);
  }

  Future<Socket> Function() get socketFactory =>
      () => Socket.connect(_server.address.host, _server.port);

  Future<void> close() => _server.close();

  Future<void> _serve(Socket c) async {
    final buf = <int>[];
    try {
      await for (final chunk in c) {
        buf.addAll(chunk);
        while (buf.length >= 4) {
          final len = ByteData.sublistView(
            Uint8List.fromList(buf.sublist(0, 4)),
          ).getInt32(0, Endian.big);
          if (buf.length < 4 + len) break;
          final frame = Uint8List.fromList(buf.sublist(4, 4 + len));
          buf.removeRange(0, 4 + len);
          final r = BinaryReader(frame);
          final hdr = r.readMessageBegin();
          final reply = _handlers[hdr.name]!(hdr, r);
          final out = Uint8List(4 + reply.length);
          ByteData.sublistView(out).setInt32(0, reply.length, Endian.big);
          out.setRange(4, out.length, reply);
          c.add(out);
        }
      }
    } finally {
      await c.close();
    }
  }
}

void main() {
  test('PrismIssuer.generateToken (class 0/0) maps a Prism reply into a '
      'TransferElectricityCreditToken', () async {
    final server = await _FakeServer.bind({
      'signInWithPassword': (call, args) {
        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('signInWithPassword', TMessageType.reply, call.seqId),
        );
        w.writeFieldBegin(TType.struct, 0);
        w.writeFieldBegin(TType.string, 1);
        w.writeString('jwt-abc');
        w.writeFieldStop();
        w.writeFieldStop();
        return w.takeBytes();
      },
      'issueCreditToken': (call, args) {
        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('issueCreditToken', TMessageType.reply, call.seqId),
        );
        w.writeFieldBegin(TType.list, 0);
        w.writeListBegin(TType.struct, 1);
        // PrismToken: drn(1), tid(12), description(20), scaledAmount(22),
        // tokenDec(30).
        w.writeFieldBegin(TType.string, 1);
        w.writeString('56000000001');
        w.writeFieldBegin(TType.i32, 12);
        w.writeI32(12345);
        w.writeFieldBegin(TType.string, 20);
        w.writeString('Credit:Electricity');
        w.writeFieldBegin(TType.string, 22);
        w.writeString('5.0');
        w.writeFieldBegin(TType.string, 30);
        // A valid 1..20-digit decimal so tokenNoToBinary66 succeeds.
        w.writeString('12345678901234567890');
        w.writeFieldStop();
        w.writeFieldStop();
        return w.takeBytes();
      },
    });
    addTearDown(server.close);

    final issuer = PrismIssuer.forTesting(
      const PrismConfig(
        host: '127.0.0.1',
        port: 0,
        realm: 'STS',
        username: 'vendor',
        password: 'pw',
      ),
      server.socketFactory,
    );

    final token = await issuer.generateToken('req-42', {
      VirtualHsmParams.tokenClass: '0',
      VirtualHsmParams.tokenSubclass: '0',
      VirtualHsmParams.decoderReferenceNumber: '56000000001',
      VirtualHsmParams.supplyGroupCode: '123456',
      VirtualHsmParams.tariffIndex: '1',
      VirtualHsmParams.keyRevisionNo: '1',
      VirtualHsmParams.encryptionAlgorithm: 'sta',
      VirtualHsmParams.amount: '5.0',
      VirtualHsmParams.baseDate: '1993',
    });

    expect(token, isA<TransferElectricityCreditToken>());
    final t = token as TransferElectricityCreditToken;
    expect(t.encryptedTokenBitString, isNotNull);
    expect(t.tokenNo, '12345678901234567890');
    expect(t.amountPurchased!.unitsPurchased, 5.0);
    expect(t.tokenIdentifier!.bitString.value, 12345);
  });

  test('PrismIssuer.generateToken throws NotImplementedException for '
      'non-electricity classes', () async {
    final issuer = PrismIssuer.forTesting(
      const PrismConfig(
        host: '127.0.0.1',
        port: 0,
        realm: 'STS',
        username: 'u',
        password: 'p',
      ),
      // Never invoked.
      () => throw StateError('socket factory should not be called'),
    );

    await expectLater(
      issuer.generateToken('r', {
        VirtualHsmParams.tokenClass: '1',
        VirtualHsmParams.tokenSubclass: '0',
      }),
      throwsA(predicate((e) => e.toString().contains('class 0 / subclass 0'))),
    );
  });

  test('PrismIssuer.decodeToken (class 0/0) maps a Valid VerifyResult into '
      'a TransferElectricityCreditToken', () async {
    final server = await _FakeServer.bind({
      'signInWithPassword': (call, args) {
        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('signInWithPassword', TMessageType.reply, call.seqId),
        );
        w.writeFieldBegin(TType.struct, 0);
        w.writeFieldBegin(TType.string, 1);
        w.writeString('jwt-decode');
        w.writeFieldStop();
        w.writeFieldStop();
        return w.takeBytes();
      },
      'verifyToken': (call, args) {
        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('verifyToken', TMessageType.reply, call.seqId),
        );
        // Result struct: success VerifyResult.
        w.writeFieldBegin(TType.struct, 0);
        w.writeFieldBegin(TType.string, 1);
        w.writeString('Valid');
        w.writeFieldBegin(TType.struct, 2);
        // PrismToken — only the fields the issuer reads.
        w.writeFieldBegin(TType.string, 1); // drn
        w.writeString('56000000001');
        w.writeFieldBegin(TType.i32, 12); // tid
        w.writeI32(2024);
        w.writeFieldBegin(TType.string, 20);
        w.writeString('Credit:Electricity');
        w.writeFieldBegin(TType.string, 22);
        w.writeString('7.5');
        w.writeFieldBegin(TType.string, 30);
        w.writeString('11122233344455566677');
        w.writeFieldStop(); // PrismToken
        w.writeFieldStop(); // VerifyResult
        w.writeFieldStop(); // result struct
        return w.takeBytes();
      },
    });
    addTearDown(server.close);

    final issuer = PrismIssuer.forTesting(
      const PrismConfig(
        host: '127.0.0.1',
        port: 0,
        realm: 'STS',
        username: 'vendor',
        password: 'pw',
      ),
      server.socketFactory,
    );

    final decoded = await issuer
        .decodeToken('req-decode-1', '11122233344455566677', {
          VirtualHsmParams.tokenClass: '0',
          VirtualHsmParams.tokenSubclass: '0',
          VirtualHsmParams.decoderReferenceNumber: '56000000001',
          VirtualHsmParams.supplyGroupCode: '123456',
          VirtualHsmParams.tariffIndex: '1',
          VirtualHsmParams.keyRevisionNo: '1',
          VirtualHsmParams.encryptionAlgorithm: 'sta',
        });

    expect(decoded, isA<TransferElectricityCreditToken>());
    final t = decoded as TransferElectricityCreditToken;
    expect(t.tokenNo, '11122233344455566677');
    expect(t.amountPurchased!.unitsPurchased, 7.5);
    expect(t.tokenIdentifier!.bitString.value, 2024);
  });

  test('PrismIssuer.decodeToken throws when Prism returns Invalid', () async {
    final server = await _FakeServer.bind({
      'signInWithPassword': (call, args) {
        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('signInWithPassword', TMessageType.reply, call.seqId),
        );
        w.writeFieldBegin(TType.struct, 0);
        w.writeFieldBegin(TType.string, 1);
        w.writeString('jwt-bad');
        w.writeFieldStop();
        w.writeFieldStop();
        return w.takeBytes();
      },
      'verifyToken': (call, args) {
        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('verifyToken', TMessageType.reply, call.seqId),
        );
        w.writeFieldBegin(TType.struct, 0);
        w.writeFieldBegin(TType.string, 1);
        w.writeString('Invalid');
        w.writeFieldStop(); // VerifyResult (no token)
        w.writeFieldStop(); // result struct
        return w.takeBytes();
      },
    });
    addTearDown(server.close);

    final issuer = PrismIssuer.forTesting(
      const PrismConfig(
        host: '127.0.0.1',
        port: 0,
        realm: 'STS',
        username: 'u',
        password: 'p',
      ),
      server.socketFactory,
    );

    await expectLater(
      issuer.decodeToken('req-bad', '00000000000000000000', {
        VirtualHsmParams.tokenClass: '0',
        VirtualHsmParams.tokenSubclass: '0',
        VirtualHsmParams.decoderReferenceNumber: '56000000001',
        VirtualHsmParams.supplyGroupCode: '123456',
        VirtualHsmParams.tariffIndex: '1',
        VirtualHsmParams.keyRevisionNo: '1',
        VirtualHsmParams.encryptionAlgorithm: 'sta',
      }),
      throwsA(predicate((e) => e.toString().contains('Invalid'))),
    );
  });
}
