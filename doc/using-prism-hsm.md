# Using the Prism HSM — operator's guide

[TOC](./README.md)

---

`nectar_sts_dart` ships with two pluggable token-issuer backends:

- `VirtualHsmIssuer` — pure-Dart, in-process, mints tokens locally
  from a `VendingCommonDesKey`. Great for tests, demos, and the
  reference vectors in [07 — Compliance](./07-compliance-and-conclusion.md).
- `PrismIssuer` — thin client that forwards every issue / decode /
  status call to a remote **Prism HSM** over a hand-rolled Thrift
  binary protocol. Use this when you hold no vending key locally and
  the utility's real HSM must sign every token.

This guide covers the Prism path end to end: env config, HTTP surface,
programmatic use, TLS and pooling behaviour, and the current wiring
gaps.

If you want the architectural tour of the local backend first, read
[06 — The virtual HSM & virtual meter](./06-virtual-hsm-and-meter.md).

## What lives where

| Piece | File |
| --- | --- |
| Thrift binary protocol (encoder + decoder) | [lib/src/prism/thrift_binary_protocol.dart](../lib/src/prism/thrift_binary_protocol.dart) |
| Framed transport + TLS socket factory | [lib/src/prism/thrift_framed_transport.dart](../lib/src/prism/thrift_framed_transport.dart) |
| `TokenApi` client (one method per RPC) | [lib/src/prism/token_api_client.dart](../lib/src/prism/token_api_client.dart) |
| `PrismConfig` + `PrismIssuer` (glue to `TokenIssuer`) | [lib/src/server/token_issuer.dart](../lib/src/server/token_issuer.dart) |
| Server-side backend selection | [bin/server.dart](../bin/server.dart) |

There are no generated Thrift stubs — the wire format is implemented
by hand against the upstream Java reference (`TokenApi.java`,
`SessionOptions.java`, `MeterConfigIn.java`, `Token.java`,
`VerifyResult.java`, `NodeStatus.java`, `ApiException.java`). The
library header on [token_api_client.dart](../lib/src/prism/token_api_client.dart)
lists every implemented RPC.

## Running the HTTP server against Prism

The HTTP surface is identical whether the issuer is virtual or Prism —
`HSM_KIND` chooses the backend at startup:

```powershell
$env:HSM_KIND       = "prism"
$env:PRISM_HOST     = "prism.example.com"
$env:PRISM_PORT     = "9090"
$env:PRISM_REALM    = "your-realm"
$env:PRISM_USERNAME = "vendor-user"
$env:PRISM_PASSWORD = "..."
$env:PRISM_INSECURE_TLS = "true"   # default; see the TLS section below
dart run bin/server.dart
```

On startup the server logs the resolved backend:

```
[info] hsm backend: PrismIssuer(prism.example.com:9090)
```

If any of the required `PRISM_*` vars are missing / empty, startup
fails fast with a `StateError` — see `_buildIssuer` in
[bin/server.dart](../bin/server.dart).

> Prism env vars are not yet included in [.env.example](../.env.example);
> add them there if your operators rely on `cp .env.example .env` as
> the onboarding step.

### Endpoints backed by Prism

Once `HSM_KIND=prism`, every endpoint that touches the issuer forwards
to Prism (see route table in
[lib/src/server/api_server.dart](../lib/src/server/api_server.dart)):

| Method | Route | Prism RPC |
| --- | --- | --- |
| `GET`  | `/v1/health/backend` | `ping(sleepMs, echo)` |
| `GET`  | `/v1/status/nodes` | `getStatus` |
| `POST` | `/v1/tokens` | `issueCreditToken` |
| `POST` | `/v1/tokens/<tokenNo>/verify` | `verifyToken` |
| `POST` | `/v1/tokens/<tokenNo>` | `verifyToken` (decode-only) |
| `POST` | `/v1/tokens/key-change` | `issueKeyChangeTokens` |
| `POST` | `/v1/tokens/mse/{clear-credit,clear-tamper,set-max-power,set-tariff,set-flag}` | `issueMseToken` |
| `POST` | `/v1/tokens/meter-test` | `issueMeterTestToken` |
| `POST` | `/v1/tokens/credit/{electricity,water,gas,time}-currency` | `issueCurrencyCreditToken` |
| `GET`  | `/v1/tokens/results/<originalRequestId>` | `fetchTokenResult` (idempotency replay) |

The meter-registry, vending-log, and tariff-book endpoints are handled
entirely inside the Dart process — they don't call Prism.

## Using `PrismIssuer` directly from Dart

If you're embedding the library and don't need the HTTP server, wire a
`PrismIssuer` and call it through the [`TokenIssuer`](../lib/src/server/token_issuer.dart)
interface — the same shape `VirtualHsmIssuer` implements:

```dart
import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:nectar_sts_dart/src/server/token_issuer.dart';

final issuer = PrismIssuer(PrismConfig(
  host: 'prism.example.com',
  port: 9090,
  realm: 'your-realm',
  username: 'vendor-user',
  password: '...',
  insecureTls: true,                    // trust-all, matches Java default
  maxConnections: 4,                    // pooled Thrift connections
  authTokenTtl: Duration(minutes: 10),  // JWT cache window
));

final token = await issuer.generateToken('req-123', {
  VirtualHsmParams.tokenClass:    '0',
  VirtualHsmParams.tokenSubclass: '0',   // 0=elec, 1=water, 2=gas
  VirtualHsmParams.amount:        '0.5', // kWh / m^3 / m^3
  // ...meter identity (DRN/SGC/KRN/TI/EA/TCT/etc.) — see
  // _meterConfigFromParams in token_issuer.dart for the full key set.
});

// Non-credit operations use their dedicated methods:
final kct = await issuer.issueKeyChangeTokens('req-124', params);
final mse = await issuer.issueMseToken('req-125', subclass, amount, params);
final test = await issuer.issueMeterTestToken('req-126', subclass, control, mfrcode);
final cur  = await issuer.issueCurrencyCreditToken('req-127', 4, params);
final status = await issuer.getNodeStatus();
final health = await issuer.checkBackend();
```

### Test-only constructor

`PrismIssuer.forTesting(config, socketFactory)` injects a plain-TCP
`SocketFactory` so an in-process fake Thrift server (see
[test/prism/token_api_client_test.dart](../test/prism/token_api_client_test.dart))
can accept connections without certificates. Use it only from tests.

## Using `TokenApiClient` directly

If you need something the issuer doesn't expose — or want to script a
one-off `ping` / `getStatus` from an ops box — bypass the issuer and
talk to Prism directly:

```dart
import 'package:nectar_sts_dart/src/prism/token_api_client.dart';
import 'package:nectar_sts_dart/src/prism/thrift_framed_transport.dart';

final client = await TokenApiClient.connect(tlsSocketFactory(
  host: 'prism.example.com',
  port: 9090,
  insecureTls: true,
));
try {
  final jwt = await client.signInWithPassword(
    messageId: 'req-1', realm: '...', username: '...', password: '...');
  final pong = await client.ping(sleepMs: 0, echo: 'hello');
  print(pong);
} finally {
  await client.close();
}
```

A `TokenApiClient` wraps **one** framed transport and is **not**
re-entrant: don't fan out concurrent RPCs on the same client — the
Thrift seqId counter and inbound-frame iterator are single-consumer.
For concurrency, either build one client per caller or let
`PrismIssuer` manage a pool for you.

## Connection pooling and auth caching

`PrismIssuer` layers two performance optimisations on top of the raw
`TokenApiClient`:

- **Connection pool** — `PrismConfig.maxConnections` (default `4`)
  live Thrift/TLS connections are kept warm and handed out FIFO. When
  the pool is saturated, callers wait. A wire-level failure
  (`SocketException` / `TimeoutException`) discards the connection;
  a Prism logic error (`PrismApiException`) returns it to the pool.
  Set `maxConnections: 0` to disable pooling — every RPC then
  connects, runs, and closes (matches the Java reference behaviour).

- **JWT cache** — `PrismConfig.authTokenTtl` (default `10 min`) caches
  the access token from `signInWithPassword` and reuses it across RPC
  calls. Concurrent callers that find the cache stale share a single
  in-flight sign-in via an internal completer, so a burst of requests
  produces exactly one `signInWithPassword` round-trip. Set
  `authTokenTtl: Duration.zero` to sign in on every call.

Both caches are per-`PrismIssuer` instance. Construct one issuer per
process and reuse it — do **not** build a fresh `PrismIssuer` per
request or you lose both optimisations.

## TLS notes

`tlsSocketFactory(...)` returns a `SocketFactory` that opens a Dart
`SecureSocket`. When `insecureTls: true` (the default, matching the
upstream Java `PrismHSMConnector` which installs a trust-all
`X509TrustManager`), server certificate validation is skipped
entirely.

**This is safe only on a trusted network segment.** Before pointing
this at a production Prism, either:

1. Set `PRISM_INSECURE_TLS=false` and trust Prism's cert through the
   OS trust store, or
2. Extend `tlsSocketFactory` to load a specific CA bundle (there is
   no built-in "trust this one cert" convenience yet).

## Current wiring gaps

The Prism backend is functionally complete for the RPCs listed above,
with these known limits:

1. **`generateToken` restricts to class 0 subclass 0..2** (electricity /
   water / gas credit). Class 1 tokens and currency-credit variants
   (subclasses 4..7) are reachable only through their dedicated
   methods (`issueCurrencyCreditToken`) or dedicated routes; a plain
   `POST /v1/tokens` with `subclass=4` returns 501.

2. **`decodeToken` requires a Prism-side `verifyToken` success.** Prism
   returns the decoded fields directly — this path does not fall back
   to local decryption if Prism rejects the token, which means you
   cannot decode tokens minted under a key Prism doesn't hold. This
   is intentional (the whole point of Prism is that keys never leave
   it) but worth flagging.

3. **DKGA-01 and DKGA-03 are not implemented on either backend.** The
   virtual HSM throws
   [`InvalidDecoderKeyGenerationAlgorithm`](../lib/src/decoderkey/decoder_key_generator_exception.dart);
   Prism will reject with its own `ApiException`.

4. **`.env.example` doesn't yet list `PRISM_*` vars.** Add them if
   your onboarding relies on the template.

## Tests

| Test | What it covers |
| --- | --- |
| [test/prism/thrift_protocol_test.dart](../test/prism/thrift_protocol_test.dart) | Pure encoder/decoder round-trips for the Thrift binary protocol + framed transport. |
| [test/prism/token_api_client_test.dart](../test/prism/token_api_client_test.dart) | `TokenApiClient` end-to-end against an in-process fake Thrift server (signIn, issueCreditToken, exception paths). |
| [test/prism/prism_issuer_test.dart](../test/prism/prism_issuer_test.dart) | `PrismIssuer.generateToken` mapping back into `TransferElectricityCreditToken`. |
| [test/token_issuer_test.dart](../test/token_issuer_test.dart) | `PrismConfig` plumbing on `PrismIssuer` (no network). |

None of these tests hit a real Prism — they use `PrismIssuer.forTesting`
and a fake Thrift server, so `dart test` runs them offline in CI.

---

[◀ Back to the TOC](./README.md)
