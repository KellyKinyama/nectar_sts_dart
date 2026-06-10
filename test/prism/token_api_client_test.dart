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

    test(
      'verifyToken returns Valid + decoded PrismToken on happy path',
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
      },
    );

    test(
      'verifyToken with non-Valid result still returns the struct',
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
      },
    );

    test('issueKeyChangeTokens decodes a 2-element list (STA/DEA)', () async {
      final server = await _FakeThriftServer.bind({
        'issueKeyChangeTokens': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('issueKeyChangeTokens', TMessageType.reply, call.seqId),
          );
          // Result struct: success = list<PrismToken>.
          w.writeFieldBegin(TType.list, 0);
          w.writeListBegin(TType.struct, 2);
          // 1st-section KCT (subclass 0x3 = 3).
          w.writeFieldBegin(TType.i16, 11); // subclass
          w.writeI16(3);
          w.writeFieldBegin(TType.string, 20); // description
          w.writeString('KeyChange:1stSection');
          w.writeFieldBegin(TType.string, 30); // tokenDec
          w.writeString('11111111111111111111');
          w.writeFieldStop();
          // 2nd-section KCT (subclass 0x4 = 4).
          w.writeFieldBegin(TType.i16, 11);
          w.writeI16(4);
          w.writeFieldBegin(TType.string, 20);
          w.writeString('KeyChange:2ndSection');
          w.writeFieldBegin(TType.string, 30);
          w.writeString('22222222222222222222');
          w.writeFieldStop();
          w.writeFieldStop(); // end result struct
          return w.takeBytes();
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      final tokens = await client.issueKeyChangeTokens(
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
        newConfig: const MeterConfigAmendment(toSgc: 234567, toKrn: 2, toTi: 1),
      );

      expect(tokens, hasLength(2));
      expect(tokens[0].subclass, 3);
      expect(tokens[0].description, 'KeyChange:1stSection');
      expect(tokens[0].tokenDec, '11111111111111111111');
      expect(tokens[1].subclass, 4);
      expect(tokens[1].description, 'KeyChange:2ndSection');
      expect(tokens[1].tokenDec, '22222222222222222222');
    });

    test('issueKeyChangeTokens decodes a 4-element list (MISTY1)', () async {
      final server = await _FakeThriftServer.bind({
        'issueKeyChangeTokens': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('issueKeyChangeTokens', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.list, 0);
          w.writeListBegin(TType.struct, 4);
          for (final sc in const [3, 4, 8, 9]) {
            w.writeFieldBegin(TType.i16, 11);
            w.writeI16(sc);
            w.writeFieldBegin(TType.string, 30);
            w.writeString('${sc}0000000000000000000'.padRight(20, '0'));
            w.writeFieldStop();
          }
          w.writeFieldStop();
          return w.takeBytes();
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      final tokens = await client.issueKeyChangeTokens(
        messageId: 'r',
        accessToken: 'jwt',
        meterConfig: const MeterConfigIn(
          drn: '56000000001',
          ea: 11, // MISTY1
          tct: 1,
          sgc: 123456,
          krn: 1,
          ti: 1,
          ken: 0,
        ),
        newConfig: const MeterConfigAmendment(toSgc: 234567, toKrn: 2, toTi: 1),
      );

      expect(tokens.map((t) => t.subclass).toList(), [3, 4, 8, 9]);
    });

    test('issueKeyChangeTokens surfaces ApiException', () async {
      final server = await _FakeThriftServer.bind({
        'issueKeyChangeTokens': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('issueKeyChangeTokens', TMessageType.reply, call.seqId),
          );
          // Result struct: ApiException at field 1.
          w.writeFieldBegin(TType.struct, 1);
          w.writeFieldBegin(TType.string, 1);
          w.writeString('NO_KCT');
          w.writeFieldBegin(TType.string, 2);
          w.writeString('Cannot issue KCTs for this meter');
          w.writeFieldStop();
          w.writeFieldStop();
          return w.takeBytes();
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      await expectLater(
        client.issueKeyChangeTokens(
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
          newConfig: const MeterConfigAmendment(
            toSgc: 234567,
            toKrn: 2,
            toTi: 1,
          ),
        ),
        throwsA(isA<PrismApiException>()),
      );
    });

    test('ping echoes the input string', () async {
      final server = await _FakeThriftServer.bind({
        'ping': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(TMessage('ping', TMessageType.reply, call.seqId));
          w.writeFieldBegin(TType.string, 0);
          w.writeString('pong:hello');
          w.writeFieldStop();
          return w.takeBytes();
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      final res = await client.ping(sleepMs: 0, echo: 'hello');
      expect(res, 'pong:hello');
    });

    test(
      'getStatus decodes a list of NodeStatus with info map + alerts',
      () async {
        final server = await _FakeThriftServer.bind({
          'getStatus': (call, args) {
            final w = BinaryWriter();
            w.writeMessageBegin(
              TMessage('getStatus', TMessageType.reply, call.seqId),
            );
            w.writeFieldBegin(TType.list, 0);
            w.writeListBegin(TType.struct, 2);

            // Node 0: 2-entry info, 1 alert.
            w.writeFieldBegin(TType.map, 1);
            w.writeMapBegin(TType.string, TType.string, 2);
            w.writeString('host');
            w.writeString('prism-0');
            w.writeString('version');
            w.writeString('2.5.1');
            w.writeFieldBegin(TType.list, 2);
            w.writeListBegin(TType.struct, 1);
            w.writeFieldBegin(TType.string, 1);
            w.writeString('LOW_DISK');
            w.writeFieldBegin(TType.string, 2);
            w.writeString('Disk usage above 80%');
            w.writeFieldStop();
            w.writeFieldStop(); // end NodeStatus 0

            // Node 1: empty info, no alerts.
            w.writeFieldBegin(TType.map, 1);
            w.writeMapBegin(TType.string, TType.string, 0);
            w.writeFieldBegin(TType.list, 2);
            w.writeListBegin(TType.struct, 0);
            w.writeFieldStop(); // end NodeStatus 1

            w.writeFieldStop(); // end getStatus_result
            return w.takeBytes();
          },
        });
        addTearDown(server.close);

        final client = await TokenApiClient.connect(server.socketFactory);
        addTearDown(client.close);

        final nodes = await client.getStatus(
          messageId: 'r',
          accessToken: 'jwt',
        );
        expect(nodes, hasLength(2));
        expect(nodes[0].info, {'host': 'prism-0', 'version': '2.5.1'});
        expect(nodes[0].alerts, hasLength(1));
        expect(nodes[0].alerts.first.eCode, 'LOW_DISK');
        expect(nodes[0].alerts.first.eMsgEn, 'Disk usage above 80%');
        expect(nodes[1].info, isEmpty);
        expect(nodes[1].alerts, isEmpty);
      },
    );

    test('fetchTokenResult replays a prior issue\'s tokens', () async {
      final server = await _FakeThriftServer.bind({
        'fetchTokenResult': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('fetchTokenResult', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.list, 0);
          w.writeListBegin(TType.struct, 1);
          w.writeFieldBegin(TType.string, 20); // description
          w.writeString('Credit:Electricity');
          w.writeFieldBegin(TType.string, 22); // scaledAmount
          w.writeString('12.34');
          w.writeFieldBegin(TType.string, 30); // tokenDec
          w.writeString('12345678901234567890');
          w.writeFieldStop();
          w.writeFieldStop();
          return w.takeBytes();
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      final tokens = await client.fetchTokenResult(
        messageId: 'r2',
        accessToken: 'jwt',
        reqMessageId: 'orig-req-1',
      );
      expect(tokens, hasLength(1));
      expect(tokens.first.description, 'Credit:Electricity');
      expect(tokens.first.scaledAmount, '12.34');
      expect(tokens.first.tokenDec, '12345678901234567890');
    });

    test('issueMseToken returns a Class 2 ClearCredit token', () async {
      final server = await _FakeThriftServer.bind({
        'issueMseToken': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('issueMseToken', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.list, 0);
          w.writeListBegin(TType.struct, 1);
          w.writeFieldBegin(TType.i16, 10); // tokenClass
          w.writeI16(2);
          w.writeFieldBegin(TType.i16, 11); // subclass = ClearCredit (1)
          w.writeI16(1);
          w.writeFieldBegin(TType.string, 20);
          w.writeString('Mse:ClearCredit');
          w.writeFieldBegin(TType.string, 30);
          w.writeString('99999999999999999999');
          w.writeFieldStop();
          w.writeFieldStop();
          return w.takeBytes();
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      final tokens = await client.issueMseToken(
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
        subclass: 1, // ClearCredit
        transferAmount: 0,
        tokenTime: 1700000000,
      );

      expect(tokens, hasLength(1));
      expect(tokens.first.tokenClass, 2);
      expect(tokens.first.subclass, 1);
      expect(tokens.first.description, 'Mse:ClearCredit');
      expect(tokens.first.tokenDec, '99999999999999999999');
    });

    test('issueMeterTestToken returns a single MeterTestToken', () async {
      final server = await _FakeThriftServer.bind({
        'issueMeterTestToken': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('issueMeterTestToken', TMessageType.reply, call.seqId),
          );
          // Result struct: success at field 0 = STRUCT MeterTestToken.
          w.writeFieldBegin(TType.struct, 0);
          w.writeFieldBegin(TType.string, 1); // drn
          w.writeString('56000000001');
          w.writeFieldBegin(TType.string, 2); // pan
          w.writeString('PAN-1');
          w.writeFieldBegin(TType.i16, 10); // tokenClass
          w.writeI16(1);
          w.writeFieldBegin(TType.i16, 11); // subclass
          w.writeI16(0);
          w.writeFieldBegin(TType.i64, 12); // control
          w.writeI64(7); // DisplayMeterPowerLimit
          w.writeFieldBegin(TType.i16, 13); // mfrcode
          w.writeI16(11);
          w.writeFieldBegin(TType.string, 20); // description
          w.writeString('Test:DisplayMeterPowerLimit');
          w.writeFieldBegin(TType.string, 30); // tokenDec
          w.writeString('44444444444444444444');
          w.writeFieldBegin(TType.string, 31); // tokenHex
          w.writeString('DEADBEEF');
          w.writeFieldStop(); // end MeterTestToken
          w.writeFieldStop(); // end result
          return w.takeBytes();
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      final mtt = await client.issueMeterTestToken(
        messageId: 'r',
        accessToken: 'jwt',
        subclass: 0,
        control: 7,
        mfrcode: 11,
      );

      expect(mtt.drn, '56000000001');
      expect(mtt.pan, 'PAN-1');
      expect(mtt.tokenClass, 1);
      expect(mtt.subclass, 0);
      expect(mtt.control, 7);
      expect(mtt.mfrcode, 11);
      expect(mtt.description, 'Test:DisplayMeterPowerLimit');
      expect(mtt.tokenDec, '44444444444444444444');
      expect(mtt.tokenHex, 'DEADBEEF');
    });

    test('issueMeterTestToken surfaces ApiException', () async {
      final server = await _FakeThriftServer.bind({
        'issueMeterTestToken': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('issueMeterTestToken', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.struct, 1); // ex1
          w.writeFieldBegin(TType.string, 1);
          w.writeString('BAD_MFR');
          w.writeFieldBegin(TType.string, 2);
          w.writeString('Manufacturer code 99 is not registered');
          w.writeFieldStop();
          w.writeFieldStop();
          return w.takeBytes();
        },
      });
      addTearDown(server.close);

      final client = await TokenApiClient.connect(server.socketFactory);
      addTearDown(client.close);

      await expectLater(
        client.issueMeterTestToken(
          messageId: 'r',
          accessToken: 'jwt',
          subclass: 0,
          control: 7,
          mfrcode: 99,
        ),
        throwsA(isA<PrismApiException>()),
      );
    });
  });
}
