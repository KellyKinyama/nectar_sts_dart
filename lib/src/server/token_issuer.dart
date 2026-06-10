/// Server-boundary abstraction over "something that turns a
/// flat-Map token request into an issued [Token]".
///
/// The Dart port has historically wired the HTTP layer directly to
/// `VirtualHsm` (in-process key derivation + cipher). This interface
/// exists so a future Prism HSM client can be dropped in beside the
/// virtual implementation without touching the shelf handler.
///
/// Two implementations:
///
///   - [VirtualHsmIssuer] — wraps a [VirtualHsm]. Key derivation
///     (DKGA-02/04) and token encryption both run in this Dart
///     process. Vending key lives in plain memory.
///   - [PrismIssuer] — placeholder for the real Prism HSM. The
///     upstream `tokens-service` Java code talks to Prism over
///     Apache Thrift (`PrismClientFacade` → `PrismHSMConnector`):
///     it never derives keys client-side; `issueCreditToken` /
///     `issueKeyChangeTokens` Thrift RPCs return fully-formed
///     encrypted tokens. Porting that requires a Dart Thrift client
///     for Prism's IDL — OUT OF SCOPE for this repository today, so
///     every method throws [NotImplementedException].
library;

import '../exceptions/exceptions.dart';
import '../hsm/hsm.dart';
import '../hsm/virtual_hsm_dispatch.dart';
import '../token/token.dart';

/// Anything that can mint and decode tokens for the HTTP API.
///
/// Both methods take the same flat `Map<String, dynamic>` param
/// shape that the upstream NectarAPI uses — see [VirtualHsmParams]
/// for the canonical key names.
abstract class TokenIssuer {
  /// Short identifier for log / health output (e.g. "VirtualHsm").
  String get name;

  /// Issue a token from a flat param map. Returns the issued
  /// [Token] with `tokenNo` populated.
  Token generateToken(String requestId, Map<String, dynamic> params);

  /// Decode a previously-issued 20-digit token using the same
  /// params that were used to mint it.
  Token decodeToken(
    String requestId,
    String tokenNo,
    Map<String, dynamic> params,
  );
}

/// In-process issuer: derives the decoder key and runs the cipher
/// here in Dart via [VirtualHsm] + the [VirtualHsmDispatch]
/// extension methods.
class VirtualHsmIssuer implements TokenIssuer {
  final VirtualHsm hsm;

  VirtualHsmIssuer(this.hsm);

  @override
  String get name => hsm.name;

  @override
  Token generateToken(String requestId, Map<String, dynamic> params) =>
      hsm.generateToken(requestId, params);

  @override
  Token decodeToken(
    String requestId,
    String tokenNo,
    Map<String, dynamic> params,
  ) =>
      hsm.decodeToken(requestId, tokenNo, params);
}

/// Connection parameters for a remote Prism HSM. Mirrors the
/// upstream Java `PrismClientFacade(host, port, realm, username,
/// password, connector)` ctor.
class PrismConfig {
  final String host;
  final int port;
  final String realm;
  final String username;
  final String password;

  /// When `true`, the Thrift TLS socket should skip server-cert
  /// validation. The Java reference (`PrismHSMConnector.getClient`)
  /// installs a trust-all `X509TrustManager`, i.e. this defaults to
  /// `true` for parity — flip it off in production once a proper
  /// trust store is wired.
  final bool insecureTls;

  const PrismConfig({
    required this.host,
    required this.port,
    required this.realm,
    required this.username,
    required this.password,
    this.insecureTls = true,
  });
}

/// Stub Prism-HSM-backed issuer. The real implementation needs a
/// Dart Thrift client speaking Prism's `TokenApi` IDL — see
/// `c:\www\java\tokens-service\src\main\java\ke\co\nectar\hsm\prism\`
/// for the reference Java implementation.
///
/// Until that lands, every method throws [NotImplementedException]
/// so a `HSM_KIND=prism` deployment fails loudly instead of silently
/// degrading to the virtual HSM.
class PrismIssuer implements TokenIssuer {
  final PrismConfig config;

  PrismIssuer(this.config);

  @override
  String get name => 'PrismIssuer(${config.host}:${config.port})';

  Never _stub(String method) {
    throw NotImplementedException(
      'PrismIssuer.$method is a stub. A real Prism HSM integration '
      'requires a Dart Thrift client for Prism\'s TokenApi IDL '
      '(issueCreditToken / issueKeyChangeTokens / decodeToken). '
      'See the upstream Java reference at '
      'ke.co.nectar.hsm.prism.impl.PrismClientFacade.',
    );
  }

  @override
  Token generateToken(String requestId, Map<String, dynamic> params) =>
      _stub('generateToken');

  @override
  Token decodeToken(
    String requestId,
    String tokenNo,
    Map<String, dynamic> params,
  ) =>
      _stub('decodeToken');
}
