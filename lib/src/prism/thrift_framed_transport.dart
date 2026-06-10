/// Framed transport: every wire message is `[i32 length][bytes]`,
/// big-endian length prefix, no per-frame compression / signing.
///
/// We buffer the full inbound frame before returning it — Thrift's
/// `TFramedTransport` reference implementation does the same. The
/// outbound side just writes the encoded payload preceded by its
/// 4-byte length.
///
/// The transport is socket-agnostic: it takes anything that quacks
/// like `dart:io`'s `Socket` (which `SecureSocket` already does).
/// Tests can supply a plain in-process `Socket` connected to a
/// `ServerSocket`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'thrift_binary_protocol.dart';

/// Factory that opens the underlying byte channel for one connection.
/// Production wiring uses `SecureSocket.connect`; tests can plug in
/// plain `Socket.connect`.
typedef SocketFactory = Future<Socket> Function();

/// Build a [SocketFactory] for a real TLS connection to a Prism node.
///
/// `insecureTls=true` skips server-cert validation to mirror the Java
/// reference (`PrismHSMConnector.getClient` installs a trust-all
/// `X509TrustManager`). Flip it off in production once a proper
/// trust store is wired.
SocketFactory tlsSocketFactory({
  required String host,
  required int port,
  required bool insecureTls,
  Duration? timeout,
}) {
  return () => SecureSocket.connect(
        host,
        port,
        timeout: timeout,
        onBadCertificate: insecureTls ? (_) => true : null,
      );
}

/// One connection to a Thrift server using binary protocol on top
/// of framed transport. Not thread-safe — Thrift binary itself is
/// strictly request/reply, and `seqId` ordering breaks under
/// concurrent in-flight calls.
class FramedThriftTransport {
  final Socket _socket;
  final StreamIterator<Uint8List> _input;
  final List<int> _buffer = <int>[];
  bool _closed = false;

  FramedThriftTransport._(this._socket, this._input);

  static Future<FramedThriftTransport> connect(SocketFactory factory) async {
    final s = await factory();
    s.setOption(SocketOption.tcpNoDelay, true);
    final it = StreamIterator<Uint8List>(s.cast<Uint8List>());
    return FramedThriftTransport._(s, it);
  }

  /// Write a complete frame: `[i32 length][payload]`.
  Future<void> writeFrame(Uint8List payload) async {
    if (_closed) {
      throw const TProtocolException('cannot write to a closed transport');
    }
    final header = ByteData(4)..setInt32(0, payload.length, Endian.big);
    _socket.add(header.buffer.asUint8List());
    _socket.add(payload);
    await _socket.flush();
  }

  /// Read the next inbound frame in full and return its payload.
  Future<Uint8List> readFrame() async {
    final len = await _readExactly(4);
    final size = ByteData.sublistView(len).getInt32(0, Endian.big);
    if (size < 0) {
      throw TProtocolException('negative frame length: $size');
    }
    if (size == 0) return Uint8List(0);
    return _readExactly(size);
  }

  Future<Uint8List> _readExactly(int n) async {
    while (_buffer.length < n) {
      final more = await _input.moveNext();
      if (!more) {
        throw const TProtocolException(
          'transport closed while waiting for more bytes',
        );
      }
      _buffer.addAll(_input.current);
    }
    final out = Uint8List.fromList(_buffer.sublist(0, n));
    _buffer.removeRange(0, n);
    return out;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _input.cancel();
    } catch (_) {}
    try {
      await _socket.close();
    } catch (_) {}
    _socket.destroy();
  }
}
