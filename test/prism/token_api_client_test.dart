/// End-to-end tests for `TokenApiClient` that spin up an in-process
/// fake Thrift server over plain TCP. The fake server speaks the
/// same binary protocol + framed transport the client expects, so
/// these tests exercise the full request/reply path including
/// `_readReplyStruct` header validation.
///
/// We test:
///   * `signInWithPassword` happy path (server echoes args, returns
///     a canned `accessToken`).
///   * `signInWithPassword` `PrismApiException` path (server returns
///     field id=1 in the result struct, client should throw).
///   * `issueCreditToken` happy path with one `Credit:Electricity`
///     token; assert all fields round-trip correctly.
///   * `TApplicationException` path: server sends a reply with
///     `TMessageType.exception` — client must surface it.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nectar_sts_dart/src/prism/thrift_binary_protocol.dart';
import 'package:nectar_sts_dart/src/prism/token_api_client.dart';
import 'package:test/test.dart';

/// Per-method handler: takes the decoded call header + the reader
/// positioned right after the header, returns the **payload bytes**
/// of the reply (everything that goes inside the frame, including
/// the message header and the result struct).
typedef _CallHandler = Uint8List Function(TMessage call, BinaryReader args);

/// Tiny single-connection fake Thrift server. Accepts ONE client,
/// loops over frames, dispatches by method name.
class _FakeThriftServer {
  final ServerSocket _server;
  final Map<String, _CallHandler> _handlers;

  _FakeThriftServer._(this._server, this._handlers) {
    _accept();
  }

  static Future<_FakeThriftServer> bind(
    Map<String, _CallHandler> handlers,
  ) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeThriftServer._(server, handlers);
  }

  int get port => _server.port;
  String get host => _server.address.host;

  SocketFactory get socketFactory => () => Socket.connect(host, port);

  Future<void> close() => _server.close();

  void _accept() {
    _server.listen((client) async {
      try {
        await _serveClient(client);
      } finally {
        await client.close();
      }
    });
  }

  Future<void> _serveClient(Socket client) async {
    final buffer = <int>[];
    await for (final chunk in client) {
      buffer.addAll(chunk);
      while (true) {
        if (buffer.length < 4) break;
        final len = ByteData.sublistView(
          Uint8List.fromList(buffer.sublist(0, 4)),
        ).getInt32(0, Endian.big);
        if (buffer.length < 4 + len) break;
        final frame = Uint8List.fromList(buffer.sublist(4, 4 + len));
        buffer.removeRange(0, 4 + len);

        final r = BinaryReader(frame);
        final hdr = r.readMessageBegin();
        final handler = _handlers[hdr.name];
        if (handler == null) {
          throw StateError('fake server: no handler for ${hdr.name}');
        }
        final reply = handler(hdr, r);
        final framed = Uint8List(4 + reply.length);
        ByteData.sublistView(framed).setInt32(0, reply.length, Endian.big);
        framed.setRange(4, framed.length, reply);
        client.add(framed);
      }
    }
  }
}

/// Build a reply payload that writes the standard "success in field
/// 0" envelope produced by Apache Thrift on the wire.
Uint8List _replyWith({
  required String name,
  required int seqId,
  required void Function(BinaryWriter w) writeSuccessStruct,
}) {
  final w = BinaryWriter();
  w.writeMessageBegin(TMessage(name, TMessageType.reply, seqId));
  w.writeFieldBegin(TType.struct, 0);
  writeSuccessStruct(w);
  w.writeFieldStop(); // close result struct (the field-stop INSIDE field 0).
  return w.takeBytes();
}

void main() {
  group('TokenApiClient against fake Thrift server', () {
    test('signInWithPassword returns accessToken on happy path', () async {
      final server = await _FakeThriftServer.bind({
        'signInWithPassword': (call, args) {
          expect(call.type, TMessageType.call);
          // Echo nothing; just respond.
          return _replyWith(
            name: 'signInWithPassword',
            seqId: call.seqId,
            writeSuccessStruct: (w) {
              // SignInResult { accessToken(1) }
              w.writeFieldBegin(TType.string, 1);
              w.writeString('jwt-abc-123');
              w.writeFieldStop();
            },
          );
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      final tok = await client.signInWithPassword(
        messageId: 'req-1',
        realm: 'STS',
        username: 'vendor',
        password: 'pw',
      );
      expect(tok, 'jwt-abc-123');
    });

    test('signInWithPassword surfaces PrismApiException', () async {
      final server = await _FakeThriftServer.bind({
        'signInWithPassword': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('signInWithPassword', TMessageType.reply, call.seqId),
          );
          // Result struct, field id=1 (ex1 ApiException), NOT id=0.
          w.writeFieldBegin(TType.struct, 1);
          w.writeFieldBegin(TType.string, 1);
          w.writeString('BAD_CREDS');
          w.writeFieldBegin(TType.string, 2);
          w.writeString('Bad credentials');
          w.writeFieldStop();
          w.writeFieldStop();
          return w.takeBytes();
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      await expectLater(
        client.signInWithPassword(
          messageId: 'r',
          realm: 'STS',
          username: 'u',
          password: 'p',
        ),
        throwsA(isA<PrismApiException>()),
      );
    });

    test(
      'issueCreditToken decodes a single Credit:Electricity token',
      () async {
        final server = await _FakeThriftServer.bind({
          'issueCreditToken': (call, args) {
            final w = BinaryWriter();
            w.writeMessageBegin(
              TMessage('issueCreditToken', TMessageType.reply, call.seqId),
            );
            // Result struct: field 0 = success = list<PrismToken>.
            w.writeFieldBegin(TType.list, 0);
            w.writeListBegin(TType.struct, 1);
            // One PrismToken — only the fields the issuer reads.
            w.writeFieldBegin(TType.string, 1); // drn
            w.writeString('12345678901234');
            w.writeFieldBegin(TType.i32, 12); // tid
            w.writeI32(98765);
            w.writeFieldBegin(TType.string, 20); // description
            w.writeString('Credit:Electricity');
            w.writeFieldBegin(TType.string, 22); // scaledAmount
            w.writeString('0.5');
            w.writeFieldBegin(TType.string, 30); // tokenDec
            w.writeString('12345678901234567890');
            w.writeFieldStop(); // end PrismToken
            w.writeFieldStop(); // end result struct
            return w.takeBytes();
          },
        });
        addTearDown(server.close);

        final client = await TokenApiClient.connect(server.socketFactory);
        addTearDown(client.close);

        final tokens = await client.issueCreditToken(
          messageId: 'r',
          accessToken: 'jwt',
          meterConfig: const MeterConfigIn(
            drn: '12345678901234',
            ea: 7,
            tct: 1,
            sgc: 123456,
            krn: 1,
            ti: 1,
            ken: 0,
          ),
          subclass: 0,
          transferAmount: 5.0,
          tokenTime: 0,
        );

        expect(tokens, hasLength(1));
        final t = tokens.single;
        expect(t.description, 'Credit:Electricity');
        expect(t.scaledAmount, '0.5');
        expect(t.tokenDec, '12345678901234567890');
        expect(t.tid, 98765);
        expect(t.drn, '12345678901234');
      },
    );

    test('TApplicationException reply is surfaced as exception', () async {
      final server = await _FakeThriftServer.bind({
        'signInWithPassword': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('signInWithPassword', TMessageType.exception, call.seqId),
          );
          // TApplicationException { message(1 STRING), type(2 I32) }
          w.writeFieldBegin(TType.string, 1);
          w.writeString('boom');
          w.writeFieldBegin(TType.i32, 2);
          w.writeI32(TApplicationException.unknown);
          w.writeFieldStop();
          return w.takeBytes();
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      await expectLater(
        client.signInWithPassword(
          messageId: 'r',
          realm: 'STS',
          username: 'u',
          password: 'p',
        ),
        throwsA(isA<TApplicationException>()),
      );
    });

    test('verifyToken returns Valid + decoded PrismToken on happy path',
        () async {
      final server = await _FakeThriftServer.bind({
        'verifyToken': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('verifyToken', TMessageType.reply, call.seqId),
          );
          // Result struct: field 0 = success = VerifyResult struct.
          w.writeFieldBegin(TType.struct, 0);
          // VerifyResult { validationResult(1), token(2 STRUCT) }
          w.writeFieldBegin(TType.string, 1);
          w.writeString('Valid');
          w.writeFieldBegin(TType.struct, 2);
          // Inline PrismToken — only the fields the issuer reads back.
          w.writeFieldBegin(TType.string, 1); // drn
          w.writeString('56000000001');
          w.writeFieldBegin(TType.i32, 12); // tid
          w.writeI32(424242);
          w.writeFieldBegin(TType.string, 20); // description
          w.writeString('Credit:Electricity');
          w.writeFieldBegin(TType.string, 22); // scaledAmount
          w.writeString('1.5');
          w.writeFieldBegin(TType.string, 30); // tokenDec
          w.writeString('98765432109876543210');
          w.writeFieldStop(); // end PrismToken
          w.writeFieldStop(); // end VerifyResult
          w.writeFieldStop(); // end result struct
          return w.takeBytes();
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      final res = await client.verifyToken(
        messageId: 'r',
        accessToken: 'jwt',
        meterConfig: const MeterConfigIn(
          drn: '56000000001',
          ea: 7,
          tct: 1,
          sgc: 123456,
          krn: 1,
          ti: 1,
          ken: 0,
        ),
        tokenDec: '98765432109876543210',
      );

      expect(res.isValid, isTrue);
      expect(res.validationResult, 'Valid');
      expect(res.token, isNotNull);
      expect(res.token!.tid, 424242);
      expect(res.token!.scaledAmount, '1.5');
      expect(res.token!.tokenDec, '98765432109876543210');
    });

    test('verifyToken with non-Valid result still returns the struct',
        () async {
      final server = await _FakeThriftServer.bind({
        'verifyToken': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('verifyToken', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.struct, 0);
          w.writeFieldBegin(TType.string, 1);
          w.writeString('Invalid');
          w.writeFieldStop(); // end VerifyResult (no token field)
          w.writeFieldStop(); // end result struct
          return w.takeBytes();
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      final res = await client.verifyToken(
        messageId: 'r',
        accessToken: 'jwt',
        meterConfig: const MeterConfigIn(
          drn: '56000000001',
          ea: 7,
          tct: 1,
          sgc: 123456,
          krn: 1,
          ti: 1,
          ken: 0,
        ),
        tokenDec: '00000000000000000000',
      );

      expect(res.isValid, isFalse);
      expect(res.validationResult, 'Invalid');
      expect(res.token, isNull);
    });
  });
}
