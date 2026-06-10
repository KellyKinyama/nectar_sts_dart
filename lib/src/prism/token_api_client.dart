/// Minimal Dart client for Prism's Thrift `TokenApi` service.
///
/// Only the methods `PrismIssuer` needs are implemented:
///
///   - `signInWithPassword(messageId, realm, username, password, sessionOpts)`
///     → returns `accessToken`
///   - `issueCreditToken(messageId, accessToken, meterConfig, subclass,
///     transferAmount, tokenTime, flags)` → returns `List<PrismToken>`
///   - `issueKeyChangeTokens(messageId, accessToken, meterConfig,
///     newConfig)` → returns `List<PrismToken>` (2 entries for STA/DEA,
///     4 for MISTY1; must be applied as a coordinated set)
///   - `verifyToken(messageId, accessToken, meterConfig, tokenDec)` →
///     returns `VerifyResult`
///   - `ping(sleepMs, echo)` → returns the echo verbatim (liveness)
///   - `getStatus(messageId, accessToken)` → returns
///     `List<PrismNodeStatus>` (per-node info + alerts)
///   - `fetchTokenResult(messageId, accessToken, reqMessageId)` →
///     returns `List<PrismToken>` (idempotency replay for a prior
///     issue request)
///
/// Struct field IDs + types are taken verbatim from the Java
/// Thrift-generated reference (`TokenApi.java`, `SessionOptions.java`,
/// `SignInResult.java`, `MeterConfigIn.java`, `MeterConfigAmendment.java`,
/// `Token.java`, `VerifyResult.java`, `NodeStatus.java`, `Alert.java`,
/// `ApiException.java`). See the package doc on
/// `thrift_binary_protocol.dart` for the location.
library;

import 'dart:async';

import 'thrift_binary_protocol.dart';
import 'thrift_framed_transport.dart';

export 'thrift_framed_transport.dart' show SocketFactory, tlsSocketFactory;

// ---- Wire structs ---------------------------------------------------

/// `SessionOptions` (Thrift struct) — only `version` is required.
class SessionOptions {
  final String version;
  final String? culture;
  const SessionOptions({this.version = '1.0', this.culture});

  void writeTo(BinaryWriter w) {
    w.writeFieldBegin(TType.string, 1);
    w.writeString(version);
    if (culture != null) {
      w.writeFieldBegin(TType.string, 10);
      w.writeString(culture!);
    }
    w.writeFieldStop();
  }
}

/// `SignInResult` — only field is `accessToken: string (id=1)`.
class SignInResult {
  final String accessToken;
  const SignInResult(this.accessToken);

  static SignInResult readFrom(BinaryReader r) {
    String? accessToken;
    while (true) {
      final (type, id) = r.readFieldBegin();
      if (type == TType.stop) break;
      if (id == 1 && type == TType.string) {
        accessToken = r.readString();
      } else {
        r.skip(type);
      }
    }
    if (accessToken == null) {
      throw const TProtocolException('SignInResult.accessToken missing');
    }
    return SignInResult(accessToken);
  }
}

/// `ApiException` — `eCode: string (id=1)`, `eMsgEn: string (id=2)`.
class PrismApiException implements Exception {
  final String code;
  final String messageEn;
  const PrismApiException(this.code, this.messageEn);

  static PrismApiException readFrom(BinaryReader r) {
    String code = '';
    String msg = '';
    while (true) {
      final (type, id) = r.readFieldBegin();
      if (type == TType.stop) break;
      if (id == 1 && type == TType.string) {
        code = r.readString();
      } else if (id == 2 && type == TType.string) {
        msg = r.readString();
      } else {
        r.skip(type);
      }
    }
    return PrismApiException(code, msg);
  }

  @override
  String toString() => 'PrismApiException($code: $messageEn)';
}

/// `MeterConfigIn` — subset the Java facade actually sets. Field IDs
/// match the upstream Thrift definitions exactly.
class MeterConfigIn {
  final String drn; // (1) STRING — DRN / IAIN
  final int ea; // (2) I16     — encryption algorithm code
  final int tct; // (3) I16     — token carrier type
  final int sgc; // (10) I32    — supply group code
  final int krn; // (11) I16    — key revision number
  final int ti; // (12) I16    — tariff index
  final bool allowKrnUpdate; // (21) BOOL
  final int ken; // (30) I16   — key expiry number
  final bool allow3Kct; // (32) BOOL
  final bool allowKenUpdate; // (33) BOOL

  const MeterConfigIn({
    required this.drn,
    required this.ea,
    required this.tct,
    required this.sgc,
    required this.krn,
    required this.ti,
    required this.ken,
    this.allow3Kct = false,
    this.allowKrnUpdate = false,
    this.allowKenUpdate = false,
  });

  void writeTo(BinaryWriter w) {
    w.writeFieldBegin(TType.string, 1);
    w.writeString(drn);
    w.writeFieldBegin(TType.i16, 2);
    w.writeI16(ea);
    w.writeFieldBegin(TType.i16, 3);
    w.writeI16(tct);
    w.writeFieldBegin(TType.i32, 10);
    w.writeI32(sgc);
    w.writeFieldBegin(TType.i16, 11);
    w.writeI16(krn);
    w.writeFieldBegin(TType.i16, 12);
    w.writeI16(ti);
    w.writeFieldBegin(TType.bool_, 21);
    w.writeBool(allowKrnUpdate);
    w.writeFieldBegin(TType.i16, 30);
    w.writeI16(ken);
    w.writeFieldBegin(TType.bool_, 32);
    w.writeBool(allow3Kct);
    w.writeFieldBegin(TType.bool_, 33);
    w.writeBool(allowKenUpdate);
    w.writeFieldStop();
  }
}

/// `MeterConfigAmendment` — destination config for
/// `issueKeyChangeTokens`. Only the three fields the Java IDL
/// declares: SGC, KRN, TI.
class MeterConfigAmendment {
  final int toSgc; // (1) I32
  final int toKrn; // (2) I16
  final int toTi; // (3) I16

  const MeterConfigAmendment({
    required this.toSgc,
    required this.toKrn,
    required this.toTi,
  });

  void writeTo(BinaryWriter w) {
    w.writeFieldBegin(TType.i32, 1);
    w.writeI32(toSgc);
    w.writeFieldBegin(TType.i16, 2);
    w.writeI16(toKrn);
    w.writeFieldBegin(TType.i16, 3);
    w.writeI16(toTi);
    w.writeFieldStop();
  }
}

/// `Token` (issued) — subset of fields the Java facade reads back.
///
/// Field IDs follow the auto-generated [Token.java] in the Prism
/// Thrift bundle. We round-trip only what the upstream Java
/// `PrismClientFacade` actually consumes (`description`,
/// `scaledAmount`, `tokenDec`, `tid`).
class PrismToken {
  final String drn; // (1)
  final String pan; // (2)
  final int ea; // (3)
  final int tct; // (4)
  final int sgc; // (5)
  final int krn; // (6)
  final int ti; // (7)
  final int tokenClass; // (10)
  final int subclass; // (11)
  final int tid; // (12) STS TID minutes
  final double transferAmount; // (13)
  final bool isReservedTid; // (14)
  final String description; // (20) e.g. "Credit:Electricity"
  final String stsUnitName; // (21)
  final String scaledAmount; // (22) — decimal string
  final String scaledUnitName; // (23)
  final String tokenDec; // (30) — 20-digit decimal as string
  final String tokenHex; // (31)
  final String idSm; // (40)
  final String vkKcv; // (41)

  const PrismToken({
    required this.drn,
    required this.pan,
    required this.ea,
    required this.tct,
    required this.sgc,
    required this.krn,
    required this.ti,
    required this.tokenClass,
    required this.subclass,
    required this.tid,
    required this.transferAmount,
    required this.isReservedTid,
    required this.description,
    required this.stsUnitName,
    required this.scaledAmount,
    required this.scaledUnitName,
    required this.tokenDec,
    required this.tokenHex,
    required this.idSm,
    required this.vkKcv,
  });

  static PrismToken readFrom(BinaryReader r) {
    String drn = '',
        pan = '',
        description = '',
        stsUnitName = '',
        scaledAmount = '',
        scaledUnitName = '',
        tokenDec = '',
        tokenHex = '',
        idSm = '',
        vkKcv = '';
    int ea = 0, tct = 0, sgc = 0, krn = 0, ti = 0;
    int tokenClass = 0, subclass = 0, tid = 0;
    double transferAmount = 0.0;
    bool isReservedTid = false;
    while (true) {
      final (type, id) = r.readFieldBegin();
      if (type == TType.stop) break;
      switch (id) {
        case 1:
          drn = r.readString();
          break;
        case 2:
          pan = r.readString();
          break;
        case 3:
          ea = r.readI16();
          break;
        case 4:
          tct = r.readI16();
          break;
        case 5:
          sgc = r.readI32();
          break;
        case 6:
          krn = r.readI16();
          break;
        case 7:
          ti = r.readI16();
          break;
        case 10:
          tokenClass = r.readI16();
          break;
        case 11:
          subclass = r.readI16();
          break;
        case 12:
          tid = r.readI32();
          break;
        case 13:
          transferAmount = r.readDouble();
          break;
        case 14:
          isReservedTid = r.readBool();
          break;
        case 20:
          description = r.readString();
          break;
        case 21:
          stsUnitName = r.readString();
          break;
        case 22:
          scaledAmount = r.readString();
          break;
        case 23:
          scaledUnitName = r.readString();
          break;
        case 30:
          tokenDec = r.readString();
          break;
        case 31:
          tokenHex = r.readString();
          break;
        case 40:
          idSm = r.readString();
          break;
        case 41:
          vkKcv = r.readString();
          break;
        default:
          r.skip(type);
      }
    }
    return PrismToken(
      drn: drn,
      pan: pan,
      ea: ea,
      tct: tct,
      sgc: sgc,
      krn: krn,
      ti: ti,
      tokenClass: tokenClass,
      subclass: subclass,
      tid: tid,
      transferAmount: transferAmount,
      isReservedTid: isReservedTid,
      description: description,
      stsUnitName: stsUnitName,
      scaledAmount: scaledAmount,
      scaledUnitName: scaledUnitName,
      tokenDec: tokenDec,
      tokenHex: tokenHex,
      idSm: idSm,
      vkKcv: vkKcv,
    );
  }
}

/// `TokenIssueFlags` bitmap.
class TokenIssueFlags {
  TokenIssueFlags._();
  static const int externalClock = 1;
  static const int tidAdjustBdt = 2;
  static const int specialReserved = 4;
}

/// `VerifyResult` — what `verifyToken` returns.
///
/// Fields (verbatim from the Java IDL):
///   - `validationResult` (1 STRING) — typically `"Valid"` on success.
///   - `token` (2 STRUCT) — the decoded credit/MSE token; absent for
///     non-token validations (in which case [token] is `null`).
///   - `meterTestToken` (3 STRUCT) — only set for NMSE results;
///     ignored / skipped here.
class VerifyResult {
  final String validationResult;
  final PrismToken? token;

  const VerifyResult({required this.validationResult, this.token});

  bool get isValid => validationResult.toLowerCase() == 'valid';

  static VerifyResult readFrom(BinaryReader r) {
    String validationResult = '';
    PrismToken? token;
    while (true) {
      final (type, id) = r.readFieldBegin();
      if (type == TType.stop) break;
      if (id == 1 && type == TType.string) {
        validationResult = r.readString();
      } else if (id == 2 && type == TType.struct) {
        token = PrismToken.readFrom(r);
      } else {
        r.skip(type);
      }
    }
    return VerifyResult(validationResult: validationResult, token: token);
  }
}

/// `Alert` — single status alert entry inside a [PrismNodeStatus].
class PrismAlert {
  final String eCode; // (1)
  final String eMsgEn; // (2)

  const PrismAlert({required this.eCode, required this.eMsgEn});

  static PrismAlert readFrom(BinaryReader r) {
    String eCode = '';
    String eMsgEn = '';
    while (true) {
      final (type, id) = r.readFieldBegin();
      if (type == TType.stop) break;
      if (id == 1 && type == TType.string) {
        eCode = r.readString();
      } else if (id == 2 && type == TType.string) {
        eMsgEn = r.readString();
      } else {
        r.skip(type);
      }
    }
    return PrismAlert(eCode: eCode, eMsgEn: eMsgEn);
  }
}

/// `NodeStatus` — what `getStatus` returns per Prism node.
class PrismNodeStatus {
  final Map<String, String> info; // (1) MAP<STRING,STRING>
  final List<PrismAlert> alerts; // (2) LIST<Alert>

  const PrismNodeStatus({required this.info, required this.alerts});

  static PrismNodeStatus readFrom(BinaryReader r) {
    final info = <String, String>{};
    final alerts = <PrismAlert>[];
    while (true) {
      final (type, id) = r.readFieldBegin();
      if (type == TType.stop) break;
      if (id == 1 && type == TType.map) {
        final (kt, vt, n) = r.readMapBegin();
        if (kt != TType.string || vt != TType.string) {
          throw TProtocolException(
            'NodeStatus.info: expected map<string,string>, got <$kt,$vt>',
          );
        }
        for (var i = 0; i < n; i++) {
          final k = r.readString();
          info[k] = r.readString();
        }
      } else if (id == 2 && type == TType.list) {
        final (elemType, n) = r.readListBegin();
        if (elemType != TType.struct) {
          throw TProtocolException(
            'NodeStatus.alerts: expected list<struct>, got elem $elemType',
          );
        }
        for (var i = 0; i < n; i++) {
          alerts.add(PrismAlert.readFrom(r));
        }
      } else {
        r.skip(type);
      }
    }
    return PrismNodeStatus(info: info, alerts: alerts);
  }
}

// ---- Client ---------------------------------------------------------

/// Stateful Prism TokenApi client. One instance per concurrent
/// caller — the seqId counter and inbound-frame iterator are not
/// re-entrant.
class TokenApiClient {
  final FramedThriftTransport _t;
  int _seq = 0;

  TokenApiClient(this._t);

  static Future<TokenApiClient> connect(SocketFactory factory) async {
    final t = await FramedThriftTransport.connect(factory);
    return TokenApiClient(t);
  }

  Future<void> close() => _t.close();

  // -- signInWithPassword -------------------------------------------

  Future<String> signInWithPassword({
    required String messageId,
    required String realm,
    required String username,
    required String password,
    SessionOptions sessionOptions = const SessionOptions(),
  }) async {
    final w = BinaryWriter();
    final seq = ++_seq;
    w.writeMessageBegin(TMessage('signInWithPassword', TMessageType.call, seq));
    // args struct: messageId(1) realm(2) username(3) password(4) sessionOpts(5)
    w.writeFieldBegin(TType.string, 1);
    w.writeString(messageId);
    w.writeFieldBegin(TType.string, 2);
    w.writeString(realm);
    w.writeFieldBegin(TType.string, 3);
    w.writeString(username);
    w.writeFieldBegin(TType.string, 4);
    w.writeString(password);
    w.writeFieldBegin(TType.struct, 5);
    sessionOptions.writeTo(w);
    w.writeFieldStop();
    await _t.writeFrame(w.takeBytes());

    final result = await _readReplyStruct('signInWithPassword', seq);
    SignInResult? success;
    PrismApiException? ex;
    while (true) {
      final (type, id) = result.readFieldBegin();
      if (type == TType.stop) break;
      if (id == 0 && type == TType.struct) {
        success = SignInResult.readFrom(result);
      } else if (id == 1 && type == TType.struct) {
        ex = PrismApiException.readFrom(result);
      } else {
        result.skip(type);
      }
    }
    if (ex != null) throw ex;
    if (success == null) {
      throw const TApplicationException(
        TApplicationException.missingResult,
        'signInWithPassword: success field missing',
      );
    }
    return success.accessToken;
  }

  // -- issueCreditToken ---------------------------------------------

  Future<List<PrismToken>> issueCreditToken({
    required String messageId,
    required String accessToken,
    required MeterConfigIn meterConfig,
    required int subclass,
    required double transferAmount,
    required int tokenTime,
    int flags = TokenIssueFlags.externalClock,
  }) async {
    final w = BinaryWriter();
    final seq = ++_seq;
    w.writeMessageBegin(TMessage('issueCreditToken', TMessageType.call, seq));
    // args: messageId(1) accessToken(2) meterConfig(3) subclass(4 i16)
    //       transferAmount(5 double) tokenTime(6 i64) flags(7 i64)
    w.writeFieldBegin(TType.string, 1);
    w.writeString(messageId);
    w.writeFieldBegin(TType.string, 2);
    w.writeString(accessToken);
    w.writeFieldBegin(TType.struct, 3);
    meterConfig.writeTo(w);
    w.writeFieldBegin(TType.i16, 4);
    w.writeI16(subclass);
    w.writeFieldBegin(TType.double_, 5);
    w.writeDouble(transferAmount);
    w.writeFieldBegin(TType.i64, 6);
    w.writeI64(tokenTime);
    w.writeFieldBegin(TType.i64, 7);
    w.writeI64(flags);
    w.writeFieldStop();
    await _t.writeFrame(w.takeBytes());

    final r = await _readReplyStruct('issueCreditToken', seq);
    List<PrismToken>? success;
    PrismApiException? ex;
    while (true) {
      final (type, id) = r.readFieldBegin();
      if (type == TType.stop) break;
      if (id == 0 && type == TType.list) {
        final (elemType, n) = r.readListBegin();
        if (elemType != TType.struct) {
          throw TProtocolException(
            'issueCreditToken: expected list<struct>, got elem type $elemType',
          );
        }
        success = <PrismToken>[
          for (var i = 0; i < n; i++) PrismToken.readFrom(r),
        ];
      } else if (id == 1 && type == TType.struct) {
        ex = PrismApiException.readFrom(r);
      } else {
        r.skip(type);
      }
    }
    if (ex != null) throw ex;
    if (success == null) {
      throw const TApplicationException(
        TApplicationException.missingResult,
        'issueCreditToken: success field missing',
      );
    }
    return success;
  }

  // -- issueKeyChangeTokens -----------------------------------------

  /// Issue the full set of Key Change Tokens (KCTs) for migrating a
  /// meter to a new SGC / KRN / TI.
  ///
  /// Returns a list of [PrismToken] — for STA/DEA this is two tokens
  /// (1st + 2nd section), for MISTY1 it's four (1st…4th section). All
  /// must be applied as a coordinated set; do not split them across
  /// independent vending sessions.
  Future<List<PrismToken>> issueKeyChangeTokens({
    required String messageId,
    required String accessToken,
    required MeterConfigIn meterConfig,
    required MeterConfigAmendment newConfig,
  }) async {
    final w = BinaryWriter();
    final seq = ++_seq;
    w.writeMessageBegin(
      TMessage('issueKeyChangeTokens', TMessageType.call, seq),
    );
    // args: messageId(1) accessToken(2) meterConfig(3) newConfig(4)
    w.writeFieldBegin(TType.string, 1);
    w.writeString(messageId);
    w.writeFieldBegin(TType.string, 2);
    w.writeString(accessToken);
    w.writeFieldBegin(TType.struct, 3);
    meterConfig.writeTo(w);
    w.writeFieldBegin(TType.struct, 4);
    newConfig.writeTo(w);
    w.writeFieldStop();
    await _t.writeFrame(w.takeBytes());

    final r = await _readReplyStruct('issueKeyChangeTokens', seq);
    List<PrismToken>? success;
    PrismApiException? ex;
    while (true) {
      final (type, id) = r.readFieldBegin();
      if (type == TType.stop) break;
      if (id == 0 && type == TType.list) {
        final (elemType, n) = r.readListBegin();
        if (elemType != TType.struct) {
          throw TProtocolException(
            'issueKeyChangeTokens: expected list<struct>, got elem type '
            '$elemType',
          );
        }
        success = <PrismToken>[
          for (var i = 0; i < n; i++) PrismToken.readFrom(r),
        ];
      } else if (id == 1 && type == TType.struct) {
        ex = PrismApiException.readFrom(r);
      } else {
        r.skip(type);
      }
    }
    if (ex != null) throw ex;
    if (success == null) {
      throw const TApplicationException(
        TApplicationException.missingResult,
        'issueKeyChangeTokens: success field missing',
      );
    }
    return success;
  }

  // -- verifyToken --------------------------------------------------

  /// Decode / validate a 20-digit decimal token against a meter
  /// configuration.
  ///
  /// Returns the [VerifyResult] verbatim — callers decide what to do
  /// with `validationResult` (e.g. throw if not `"Valid"`).
  Future<VerifyResult> verifyToken({
    required String messageId,
    required String accessToken,
    required MeterConfigIn meterConfig,
    required String tokenDec,
  }) async {
    final w = BinaryWriter();
    final seq = ++_seq;
    w.writeMessageBegin(TMessage('verifyToken', TMessageType.call, seq));
    // args: messageId(1) accessToken(2) meterConfig(3) tokenDec(4)
    w.writeFieldBegin(TType.string, 1);
    w.writeString(messageId);
    w.writeFieldBegin(TType.string, 2);
    w.writeString(accessToken);
    w.writeFieldBegin(TType.struct, 3);
    meterConfig.writeTo(w);
    w.writeFieldBegin(TType.string, 4);
    w.writeString(tokenDec);
    w.writeFieldStop();
    await _t.writeFrame(w.takeBytes());

    final r = await _readReplyStruct('verifyToken', seq);
    VerifyResult? success;
    PrismApiException? ex;
    while (true) {
      final (type, id) = r.readFieldBegin();
      if (type == TType.stop) break;
      if (id == 0 && type == TType.struct) {
        success = VerifyResult.readFrom(r);
      } else if (id == 1 && type == TType.struct) {
        ex = PrismApiException.readFrom(r);
      } else {
        r.skip(type);
      }
    }
    if (ex != null) throw ex;
    if (success == null) {
      throw const TApplicationException(
        TApplicationException.missingResult,
        'verifyToken: success field missing',
      );
    }
    return success;
  }

  // -- ping ---------------------------------------------------------

  /// Round-trip echo for liveness checks. The server sleeps for
  /// [sleepMs] then returns [echo] verbatim. Field IDs: sleepMs(1
  /// I32), echo(2 STRING). Reply: success(0 STRING).
  Future<String> ping({required int sleepMs, required String echo}) async {
    final w = BinaryWriter();
    final seq = ++_seq;
    w.writeMessageBegin(TMessage('ping', TMessageType.call, seq));
    w.writeFieldBegin(TType.i32, 1);
    w.writeI32(sleepMs);
    w.writeFieldBegin(TType.string, 2);
    w.writeString(echo);
    w.writeFieldStop();
    await _t.writeFrame(w.takeBytes());

    final r = await _readReplyStruct('ping', seq);
    String? success;
    PrismApiException? ex;
    while (true) {
      final (type, id) = r.readFieldBegin();
      if (type == TType.stop) break;
      if (id == 0 && type == TType.string) {
        success = r.readString();
      } else if (id == 1 && type == TType.struct) {
        ex = PrismApiException.readFrom(r);
      } else {
        r.skip(type);
      }
    }
    if (ex != null) throw ex;
    if (success == null) {
      throw const TApplicationException(
        TApplicationException.missingResult,
        'ping: success field missing',
      );
    }
    return success;
  }

  // -- getStatus ----------------------------------------------------

  /// Per-node status snapshot for the Prism cluster. Each entry
  /// holds an arbitrary `info` map (e.g. host/version/uptime) plus a
  /// list of active [PrismAlert]s.
  Future<List<PrismNodeStatus>> getStatus({
    required String messageId,
    required String accessToken,
  }) async {
    final w = BinaryWriter();
    final seq = ++_seq;
    w.writeMessageBegin(TMessage('getStatus', TMessageType.call, seq));
    w.writeFieldBegin(TType.string, 1);
    w.writeString(messageId);
    w.writeFieldBegin(TType.string, 2);
    w.writeString(accessToken);
    w.writeFieldStop();
    await _t.writeFrame(w.takeBytes());

    final r = await _readReplyStruct('getStatus', seq);
    List<PrismNodeStatus>? success;
    PrismApiException? ex;
    while (true) {
      final (type, id) = r.readFieldBegin();
      if (type == TType.stop) break;
      if (id == 0 && type == TType.list) {
        final (elemType, n) = r.readListBegin();
        if (elemType != TType.struct) {
          throw TProtocolException(
            'getStatus: expected list<struct>, got elem $elemType',
          );
        }
        success = <PrismNodeStatus>[
          for (var i = 0; i < n; i++) PrismNodeStatus.readFrom(r),
        ];
      } else if (id == 1 && type == TType.struct) {
        ex = PrismApiException.readFrom(r);
      } else {
        r.skip(type);
      }
    }
    if (ex != null) throw ex;
    if (success == null) {
      throw const TApplicationException(
        TApplicationException.missingResult,
        'getStatus: success field missing',
      );
    }
    return success;
  }

  // -- fetchTokenResult ---------------------------------------------

  /// Re-fetch the tokens previously issued for [reqMessageId]. Used
  /// when the original call timed out / disconnected before the
  /// reply could be read — Prism keeps a short-lived idempotency
  /// cache keyed by the original request's messageId.
  Future<List<PrismToken>> fetchTokenResult({
    required String messageId,
    required String accessToken,
    required String reqMessageId,
  }) async {
    final w = BinaryWriter();
    final seq = ++_seq;
    w.writeMessageBegin(TMessage('fetchTokenResult', TMessageType.call, seq));
    w.writeFieldBegin(TType.string, 1);
    w.writeString(messageId);
    w.writeFieldBegin(TType.string, 2);
    w.writeString(accessToken);
    w.writeFieldBegin(TType.string, 3);
    w.writeString(reqMessageId);
    w.writeFieldStop();
    await _t.writeFrame(w.takeBytes());

    final r = await _readReplyStruct('fetchTokenResult', seq);
    List<PrismToken>? success;
    PrismApiException? ex;
    while (true) {
      final (type, id) = r.readFieldBegin();
      if (type == TType.stop) break;
      if (id == 0 && type == TType.list) {
        final (elemType, n) = r.readListBegin();
        if (elemType != TType.struct) {
          throw TProtocolException(
            'fetchTokenResult: expected list<struct>, got elem $elemType',
          );
        }
        success = <PrismToken>[
          for (var i = 0; i < n; i++) PrismToken.readFrom(r),
        ];
      } else if (id == 1 && type == TType.struct) {
        ex = PrismApiException.readFrom(r);
      } else {
        r.skip(type);
      }
    }
    if (ex != null) throw ex;
    if (success == null) {
      throw const TApplicationException(
        TApplicationException.missingResult,
        'fetchTokenResult: success field missing',
      );
    }
    return success;
  }

  // -- shared reply scaffolding -------------------------------------

  Future<BinaryReader> _readReplyStruct(
    String expectedName,
    int expectedSeq,
  ) async {
    final frame = await _t.readFrame();
    final r = BinaryReader(frame);
    final hdr = r.readMessageBegin();
    if (hdr.name != expectedName) {
      throw TApplicationException(
        TApplicationException.wrongMethodName,
        'reply method "${hdr.name}" does not match request "$expectedName"',
      );
    }
    if (hdr.seqId != expectedSeq) {
      throw TApplicationException(
        TApplicationException.badSequenceId,
        'reply seqId ${hdr.seqId} != request $expectedSeq',
      );
    }
    if (hdr.type == TMessageType.exception) {
      throw _readTAppException(r);
    }
    if (hdr.type != TMessageType.reply) {
      throw TApplicationException(
        TApplicationException.invalidMessageType,
        'unexpected reply message type ${hdr.type}',
      );
    }
    return r;
  }

  TApplicationException _readTAppException(BinaryReader r) {
    String message = '';
    int type = TApplicationException.unknown;
    while (true) {
      final (t, id) = r.readFieldBegin();
      if (t == TType.stop) break;
      if (id == 1 && t == TType.string) {
        message = r.readString();
      } else if (id == 2 && t == TType.i32) {
        type = r.readI32();
      } else {
        r.skip(t);
      }
    }
    return TApplicationException(type, message);
  }
}
