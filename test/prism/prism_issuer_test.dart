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
import 'package:nectar_sts_dart/src/exceptions/exceptions.dart';
import 'package:test/test.dart';

typedef _Handler = Uint8List Function(TMessage call, BinaryReader args);

class _FakeServer {
  final ServerSocket _server;
  final Map<String, _Handler> _handlers;
  int connectionCount = 0;

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
    connectionCount++;
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
  test(
      'PrismIssuer.generateToken (class 0/0) maps a Prism reply into a '
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

  test(
      'PrismIssuer.generateToken throws NotImplementedException for '
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

  test(
      'PrismIssuer.decodeToken (class 0/0) maps a Valid VerifyResult into '
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

    final decoded =
        await issuer.decodeToken('req-decode-1', '11122233344455566677', {
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

  test('PrismIssuer.checkBackend reports ok when ping succeeds', () async {
    final server = await _FakeServer.bind({
      'ping': (call, args) {
        final w = BinaryWriter();
        w.writeMessageBegin(TMessage('ping', TMessageType.reply, call.seqId));
        w.writeFieldBegin(TType.string, 0);
        w.writeString('nectar-sts');
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

    final report = await issuer.checkBackend();
    expect(report['ok'], isTrue);
    expect(report['echo'], 'nectar-sts');
    expect(report['backend'], contains('PrismIssuer'));
    expect(report['roundTripMs'], isA<int>());
  });

  test(
    'PrismIssuer.checkBackend reports ok=false when connection fails',
    () async {
      // No fake server bound; connect to a port nothing is listening on.
      Future<Socket> failingFactory() => Socket.connect(
            InternetAddress.loopbackIPv4,
            1, // privileged port nothing in CI binds to
            timeout: const Duration(milliseconds: 200),
          );

      final issuer = PrismIssuer.forTesting(
        const PrismConfig(
          host: '127.0.0.1',
          port: 1,
          realm: 'STS',
          username: 'vendor',
          password: 'pw',
        ),
        failingFactory,
      );

      final report = await issuer.checkBackend();
      expect(report['ok'], isFalse);
      expect(report['error'], isNotEmpty);
    },
  );

  test('PrismIssuer.getNodeStatus signs in then maps Prism nodes', () async {
    final server = await _FakeServer.bind({
      'signInWithPassword': (call, args) {
        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('signInWithPassword', TMessageType.reply, call.seqId),
        );
        w.writeFieldBegin(TType.struct, 0);
        w.writeFieldBegin(TType.string, 1);
        w.writeString('jwt-status');
        w.writeFieldStop();
        w.writeFieldStop();
        return w.takeBytes();
      },
      'getStatus': (call, args) {
        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('getStatus', TMessageType.reply, call.seqId),
        );
        w.writeFieldBegin(TType.list, 0);
        w.writeListBegin(TType.struct, 1);
        w.writeFieldBegin(TType.map, 1);
        w.writeMapBegin(TType.string, TType.string, 2);
        w.writeString('host');
        w.writeString('prism-1');
        w.writeString('version');
        w.writeString('2.5.1');
        w.writeFieldBegin(TType.list, 2);
        w.writeListBegin(TType.struct, 1);
        w.writeFieldBegin(TType.string, 1);
        w.writeString('LOW_DISK');
        w.writeFieldBegin(TType.string, 2);
        w.writeString('Disk usage above 80%');
        w.writeFieldStop();
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

    final nodes = await issuer.getNodeStatus();
    expect(nodes, hasLength(1));
    expect(nodes.first['info'], {'host': 'prism-1', 'version': '2.5.1'});
    final alerts = nodes.first['alerts'] as List;
    expect(alerts, hasLength(1));
    expect((alerts.first as Map)['eCode'], 'LOW_DISK');
    expect((alerts.first as Map)['eMsg'], 'Disk usage above 80%');
  });

  test(
    'PrismIssuer.issueKeyChangeTokens signs in then maps the bundle',
    () async {
      final server = await _FakeServer.bind({
        'signInWithPassword': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('signInWithPassword', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.struct, 0);
          w.writeFieldBegin(TType.string, 1);
          w.writeString('jwt-kct');
          w.writeFieldStop();
          w.writeFieldStop();
          return w.takeBytes();
        },
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
            w.writeFieldBegin(TType.string, 20);
            w.writeString('KeyChange:section$sc');
            w.writeFieldBegin(TType.string, 30);
            w.writeString('${sc}0000000000000000000'.padRight(20, '0'));
            w.writeFieldStop();
          }
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

      final tokens = await issuer.issueKeyChangeTokens('req-kct', {
        VirtualHsmParams.decoderReferenceNumber: '56000000001',
        VirtualHsmParams.encryptionAlgorithm: 'misty1',
        VirtualHsmParams.supplyGroupCode: '123456',
        VirtualHsmParams.tariffIndex: '1',
        VirtualHsmParams.keyRevisionNo: '1',
        VirtualHsmParams.newSupplyGroupCode: '234567',
        VirtualHsmParams.newKeyRevisionNumber: '2',
        VirtualHsmParams.newTariffIndex: '1',
      });

      expect(tokens, hasLength(4));
      expect(tokens.map((t) => t['subclass']).toList(), [3, 4, 8, 9]);
      expect(tokens.first['description'], 'KeyChange:section3');
      expect(tokens.first['tokenNo'], startsWith('30'));
    },
  );

  test(
    'PrismIssuer.issueMseToken signs in then forwards subclass + transferAmount',
    () async {
      late double observedTransferAmount;
      late int observedSubclass;
      final server = await _FakeServer.bind({
        'signInWithPassword': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('signInWithPassword', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.struct, 0);
          w.writeFieldBegin(TType.string, 1);
          w.writeString('jwt-mse');
          w.writeFieldStop();
          w.writeFieldStop();
          return w.takeBytes();
        },
        'issueMseToken': (call, args) {
          // Walk the request struct to capture subclass (field 4) and
          // transferAmount (field 5).
          observedSubclass = 0;
          observedTransferAmount = 0;
          while (true) {
            final (type, id) = args.readFieldBegin();
            if (type == TType.stop) break;
            if (id == 4 && type == TType.i16) {
              observedSubclass = args.readI16();
            } else if (id == 5 && type == TType.double_) {
              observedTransferAmount = args.readDouble();
            } else {
              args.skip(type);
            }
          }

          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('issueMseToken', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.list, 0);
          w.writeListBegin(TType.struct, 1);
          w.writeFieldBegin(TType.i16, 11);
          w.writeI16(observedSubclass);
          w.writeFieldBegin(TType.string, 20);
          w.writeString('Mse:subclass$observedSubclass');
          w.writeFieldBegin(TType.string, 30);
          w.writeString('99999999999999999999');
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

      final tokens = await issuer.issueMseToken('req-mse', 0, 12.5, {
        VirtualHsmParams.decoderReferenceNumber: '56000000001',
        VirtualHsmParams.encryptionAlgorithm: 'sta',
        VirtualHsmParams.supplyGroupCode: '123456',
        VirtualHsmParams.tariffIndex: '1',
        VirtualHsmParams.keyRevisionNo: '1',
      });

      expect(observedSubclass, 0);
      expect(observedTransferAmount, 12.5);
      expect(tokens, hasLength(1));
      expect(tokens.first['subclass'], 0);
      expect(tokens.first['description'], 'Mse:subclass0');
      expect(tokens.first['tokenNo'], '99999999999999999999');
    },
  );

  test(
      'PrismIssuer.issueMeterTestToken forwards subclass/control/mfrcode '
      'and maps the reply struct', () async {
    late int observedSubclass;
    late int observedControl;
    late int observedMfrcode;
    final server = await _FakeServer.bind({
      'signInWithPassword': (call, args) {
        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('signInWithPassword', TMessageType.reply, call.seqId),
        );
        w.writeFieldBegin(TType.struct, 0);
        w.writeFieldBegin(TType.string, 1);
        w.writeString('jwt-nmse');
        w.writeFieldStop();
        w.writeFieldStop();
        return w.takeBytes();
      },
      'issueMeterTestToken': (call, args) {
        observedSubclass = 0;
        observedControl = 0;
        observedMfrcode = 0;
        while (true) {
          final (type, id) = args.readFieldBegin();
          if (type == TType.stop) break;
          if (id == 3 && type == TType.i16) {
            observedSubclass = args.readI16();
          } else if (id == 4 && type == TType.i64) {
            observedControl = args.readI64();
          } else if (id == 5 && type == TType.i16) {
            observedMfrcode = args.readI16();
          } else {
            args.skip(type);
          }
        }

        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('issueMeterTestToken', TMessageType.reply, call.seqId),
        );
        // success field 0: PrismMeterTestToken struct
        w.writeFieldBegin(TType.struct, 0);
        w.writeFieldBegin(TType.i16, 11);
        w.writeI16(observedSubclass);
        w.writeFieldBegin(TType.i64, 12);
        w.writeI64(observedControl);
        w.writeFieldBegin(TType.i16, 13);
        w.writeI16(observedMfrcode);
        w.writeFieldBegin(TType.string, 20);
        w.writeString('NMse:control$observedControl');
        w.writeFieldBegin(TType.string, 30);
        w.writeString('88888888888888888888');
        w.writeFieldBegin(TType.string, 31);
        w.writeString('0xCAFEBABE');
        w.writeFieldStop(); // PrismMeterTestToken
        w.writeFieldStop(); // reply
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

    final token = await issuer.issueMeterTestToken('req-nmse', 1, 3, 7);

    expect(observedSubclass, 1);
    expect(observedControl, 3);
    expect(observedMfrcode, 7);
    expect(token['subclass'], 1);
    expect(token['control'], 3);
    expect(token['manufacturerCode'], 7);
    expect(token['description'], 'NMse:control3');
    expect(token['tokenNo'], '88888888888888888888');
    expect(token['tokenHex'], '0xCAFEBABE');
  });

  test(
      'PrismIssuer.issueCurrencyCreditToken scales amount by 100000 '
      'and forwards subclass', () async {
    late int observedSubclass;
    late double observedTransferAmount;
    final server = await _FakeServer.bind({
      'signInWithPassword': (call, args) {
        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('signInWithPassword', TMessageType.reply, call.seqId),
        );
        w.writeFieldBegin(TType.struct, 0);
        w.writeFieldBegin(TType.string, 1);
        w.writeString('jwt-currency');
        w.writeFieldStop();
        w.writeFieldStop();
        return w.takeBytes();
      },
      'issueCreditToken': (call, args) {
        observedSubclass = 0;
        observedTransferAmount = 0;
        while (true) {
          final (type, id) = args.readFieldBegin();
          if (type == TType.stop) break;
          if (id == 4 && type == TType.i16) {
            observedSubclass = args.readI16();
          } else if (id == 5 && type == TType.double_) {
            observedTransferAmount = args.readDouble();
          } else {
            args.skip(type);
          }
        }

        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('issueCreditToken', TMessageType.reply, call.seqId),
        );
        w.writeFieldBegin(TType.list, 0);
        w.writeListBegin(TType.struct, 1);
        w.writeFieldBegin(TType.i16, 11);
        w.writeI16(observedSubclass);
        w.writeFieldBegin(TType.string, 20);
        w.writeString('Credit:ElectricityCurrency');
        w.writeFieldBegin(TType.string, 22);
        w.writeString(observedTransferAmount.toString());
        w.writeFieldBegin(TType.string, 30);
        w.writeString('77777777777777777777');
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

    final tokens = await issuer.issueCurrencyCreditToken('req-cur', 4, {
      VirtualHsmParams.decoderReferenceNumber: '56000000001',
      VirtualHsmParams.encryptionAlgorithm: 'sta',
      VirtualHsmParams.supplyGroupCode: '123456',
      VirtualHsmParams.tariffIndex: '1',
      VirtualHsmParams.keyRevisionNo: '1',
      VirtualHsmParams.amount: 25.50,
    });

    expect(observedSubclass, 4);
    expect(observedTransferAmount, 25.50 * 100000);
    expect(tokens, hasLength(1));
    expect(tokens.first['subclass'], 4);
    expect(tokens.first['description'], 'Credit:ElectricityCurrency');
    expect(tokens.first['tokenNo'], '77777777777777777777');
    expect(tokens.first['scaledAmount'], (25.50 * 100000).toString());
  });

  test(
    'PrismIssuer.issueCurrencyCreditToken rejects subclass outside 4..7',
    () async {
      final issuer = PrismIssuer.forTesting(
        const PrismConfig(
          host: '127.0.0.1',
          port: 0,
          realm: 'STS',
          username: 'vendor',
          password: 'pw',
        ),
        () => throw StateError('should not connect'),
      );
      expect(
        () => issuer.issueCurrencyCreditToken('req-bad', 0, {}),
        throwsA(isA<NotImplementedException>()),
      );
    },
  );

  test(
    'PrismIssuer.fetchTokenResult forwards originalRequestId and maps the list',
    () async {
      late String observedOriginalReqId;
      final server = await _FakeServer.bind({
        'signInWithPassword': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('signInWithPassword', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.struct, 0);
          w.writeFieldBegin(TType.string, 1);
          w.writeString('jwt-replay');
          w.writeFieldStop();
          w.writeFieldStop();
          return w.takeBytes();
        },
        'fetchTokenResult': (call, args) {
          observedOriginalReqId = '';
          while (true) {
            final (type, id) = args.readFieldBegin();
            if (type == TType.stop) break;
            if (id == 3 && type == TType.string) {
              observedOriginalReqId = args.readString();
            } else {
              args.skip(type);
            }
          }

          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('fetchTokenResult', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.list, 0);
          w.writeListBegin(TType.struct, 1);
          w.writeFieldBegin(TType.i16, 11);
          w.writeI16(0);
          w.writeFieldBegin(TType.string, 20);
          w.writeString('Credit:Electricity');
          w.writeFieldBegin(TType.string, 22);
          w.writeString('75.0');
          w.writeFieldBegin(TType.string, 30);
          w.writeString('66666666666666666666');
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

      final tokens = await issuer.fetchTokenResult(
        'req-replay',
        'req-original-abc',
      );

      expect(observedOriginalReqId, 'req-original-abc');
      expect(tokens, hasLength(1));
      expect(tokens.first['tokenNo'], '66666666666666666666');
      expect(tokens.first['subclass'], 0);
      expect(tokens.first['description'], 'Credit:Electricity');
      expect(tokens.first['scaledAmount'], '75.0');
    },
  );

  test(
      'PrismIssuer.verifyToken returns raw {validationResult,isValid,token} '
      'and does NOT throw on non-Valid results', () async {
    late String observedTokenDec;
    final server = await _FakeServer.bind({
      'signInWithPassword': (call, args) {
        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('signInWithPassword', TMessageType.reply, call.seqId),
        );
        w.writeFieldBegin(TType.struct, 0);
        w.writeFieldBegin(TType.string, 1);
        w.writeString('jwt-verify');
        w.writeFieldStop();
        w.writeFieldStop();
        return w.takeBytes();
      },
      'verifyToken': (call, args) {
        observedTokenDec = '';
        while (true) {
          final (type, id) = args.readFieldBegin();
          if (type == TType.stop) break;
          if (id == 4 && type == TType.string) {
            observedTokenDec = args.readString();
          } else {
            args.skip(type);
          }
        }

        final w = BinaryWriter();
        w.writeMessageBegin(
          TMessage('verifyToken', TMessageType.reply, call.seqId),
        );
        w.writeFieldBegin(TType.struct, 0);
        w.writeFieldBegin(TType.string, 1);
        w.writeString('Expired');
        w.writeFieldBegin(TType.struct, 2);
        w.writeFieldBegin(TType.i16, 11);
        w.writeI16(0);
        w.writeFieldBegin(TType.string, 20);
        w.writeString('Credit:Electricity');
        w.writeFieldBegin(TType.string, 22);
        w.writeString('12.5');
        w.writeFieldBegin(TType.string, 30);
        w.writeString('99988877766655544433');
        w.writeFieldStop();
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

    final result =
        await issuer.verifyToken('req-verify', '99988877766655544433', {
      VirtualHsmParams.decoderReferenceNumber: '56000000001',
      VirtualHsmParams.supplyGroupCode: '123456',
      VirtualHsmParams.tariffIndex: '1',
      VirtualHsmParams.keyRevisionNo: '1',
      VirtualHsmParams.encryptionAlgorithm: 'sta',
    });

    expect(observedTokenDec, '99988877766655544433');
    expect(result['validationResult'], 'Expired');
    expect(result['isValid'], false);
    final t = result['token'] as Map<String, Object?>;
    expect(t['tokenNo'], '99988877766655544433');
    expect(t['subclass'], 0);
    expect(t['description'], 'Credit:Electricity');
    expect(t['scaledAmount'], '12.5');
  });

  group('PrismIssuer auth-token cache', () {
    // Returns a configured fake server + counter that captures how many
    // times signInWithPassword was called. The fetchTokenResult handler
    // is the cheapest RPC to drive end-to-end since it ignores most
    // input fields.
    Future<({_FakeServer server, int Function() signInCount})>
        bootCached() async {
      int signIns = 0;
      final server = await _FakeServer.bind({
        'signInWithPassword': (call, args) {
          signIns++;
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('signInWithPassword', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.struct, 0);
          w.writeFieldBegin(TType.string, 1);
          w.writeString('jwt-$signIns');
          w.writeFieldStop();
          w.writeFieldStop();
          return w.takeBytes();
        },
        'fetchTokenResult': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('fetchTokenResult', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.list, 0);
          w.writeListBegin(TType.struct, 0);
          w.writeFieldStop();
          return w.takeBytes();
        },
      });
      return (server: server, signInCount: () => signIns);
    }

    test('sequential calls within authTokenTtl reuse the cached JWT', () async {
      final boot = await bootCached();
      addTearDown(boot.server.close);

      final issuer = PrismIssuer.forTesting(
        const PrismConfig(
          host: '127.0.0.1',
          port: 0,
          realm: 'STS',
          username: 'vendor',
          password: 'pw',
          // default 10-minute TTL is plenty for two back-to-back calls.
        ),
        boot.server.socketFactory,
      );

      await issuer.fetchTokenResult('req-1', 'orig-1');
      await issuer.fetchTokenResult('req-2', 'orig-2');

      expect(
        boot.signInCount(),
        1,
        reason: 'cached JWT should be reused across calls',
      );
    });

    test('authTokenTtl == Duration.zero disables the cache', () async {
      final boot = await bootCached();
      addTearDown(boot.server.close);

      final issuer = PrismIssuer.forTesting(
        const PrismConfig(
          host: '127.0.0.1',
          port: 0,
          realm: 'STS',
          username: 'vendor',
          password: 'pw',
          authTokenTtl: Duration.zero,
        ),
        boot.server.socketFactory,
      );

      await issuer.fetchTokenResult('req-1', 'orig-1');
      await issuer.fetchTokenResult('req-2', 'orig-2');

      expect(
        boot.signInCount(),
        2,
        reason: 'TTL=0 should re-sign-in on every call',
      );
    });

    test(
      'concurrent cache-miss callers coalesce on a single sign-in',
      () async {
        final boot = await bootCached();
        addTearDown(boot.server.close);

        final issuer = PrismIssuer.forTesting(
          const PrismConfig(
            host: '127.0.0.1',
            port: 0,
            realm: 'STS',
            username: 'vendor',
            password: 'pw',
          ),
          boot.server.socketFactory,
        );

        await Future.wait([
          issuer.fetchTokenResult('req-a', 'orig-a'),
          issuer.fetchTokenResult('req-b', 'orig-b'),
          issuer.fetchTokenResult('req-c', 'orig-c'),
        ]);

        expect(
          boot.signInCount(),
          1,
          reason: 'three concurrent cache-miss calls must share one sign-in',
        );
      },
    );
  });

  group('PrismIssuer connection pool', () {
    // Same fake-server scaffolding the cache tests use, but the
    // handlers stay lightweight (no auth bookkeeping) so the tests
    // only count *connections*, not RPCs.
    Future<_FakeServer> _bootPoolServer({Duration callDelay = Duration.zero}) {
      return _FakeServer.bind({
        'signInWithPassword': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('signInWithPassword', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.struct, 0);
          w.writeFieldBegin(TType.string, 1);
          w.writeString('jwt-pool');
          w.writeFieldStop();
          w.writeFieldStop();
          return w.takeBytes();
        },
        'fetchTokenResult': (call, args) {
          final w = BinaryWriter();
          w.writeMessageBegin(
            TMessage('fetchTokenResult', TMessageType.reply, call.seqId),
          );
          w.writeFieldBegin(TType.list, 0);
          w.writeListBegin(TType.struct, 0);
          w.writeFieldStop();
          return w.takeBytes();
        },
      });
    }

    test(
      'sequential calls reuse a single pooled connection',
      () async {
        final server = await _bootPoolServer();
        addTearDown(server.close);

        final issuer = PrismIssuer.forTesting(
          const PrismConfig(
            host: '127.0.0.1',
            port: 0,
            realm: 'STS',
            username: 'vendor',
            password: 'pw',
            // default maxConnections: 4 - plenty for serial calls
          ),
          server.socketFactory,
        );
        addTearDown(issuer.close);

        await issuer.fetchTokenResult('req-1', 'orig-1');
        await issuer.fetchTokenResult('req-2', 'orig-2');
        await issuer.fetchTokenResult('req-3', 'orig-3');

        expect(
          server.connectionCount,
          1,
          reason: 'all 3 calls should share one pooled TCP connection',
        );
      },
    );

    test('maxConnections == 0 disables the pool (per-call connect)', () async {
      final server = await _bootPoolServer();
      addTearDown(server.close);

      final issuer = PrismIssuer.forTesting(
        const PrismConfig(
          host: '127.0.0.1',
          port: 0,
          realm: 'STS',
          username: 'vendor',
          password: 'pw',
          maxConnections: 0,
        ),
        server.socketFactory,
      );
      addTearDown(issuer.close);

      await issuer.fetchTokenResult('req-1', 'orig-1');
      await issuer.fetchTokenResult('req-2', 'orig-2');

      expect(
        server.connectionCount,
        2,
        reason: 'maxConnections=0 must reconnect on every call',
      );
    });

    test(
      'concurrent calls beyond maxConnections wait, never exceed the cap',
      () async {
        final server = await _bootPoolServer();
        addTearDown(server.close);

        final issuer = PrismIssuer.forTesting(
          const PrismConfig(
            host: '127.0.0.1',
            port: 0,
            realm: 'STS',
            username: 'vendor',
            password: 'pw',
            maxConnections: 2,
          ),
          server.socketFactory,
        );
        addTearDown(issuer.close);

        // 5 concurrent calls vs maxConnections=2 -> the first 2
        // open new sockets, the other 3 wait on the FIFO and reuse.
        await Future.wait([
          issuer.fetchTokenResult('req-1', 'orig-1'),
          issuer.fetchTokenResult('req-2', 'orig-2'),
          issuer.fetchTokenResult('req-3', 'orig-3'),
          issuer.fetchTokenResult('req-4', 'orig-4'),
          issuer.fetchTokenResult('req-5', 'orig-5'),
        ]);

        expect(
          server.connectionCount,
          lessThanOrEqualTo(2),
          reason: 'pool must never open more than maxConnections sockets',
        );
        expect(
          server.connectionCount,
          greaterThanOrEqualTo(1),
          reason: 'pool should open at least one connection to serve calls',
        );
      },
    );
  });
}
