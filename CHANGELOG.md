## 0.1.0

Initial release.

* DKGA-02 and DKGA-04 decoder-key derivation (HMAC-SHA-256 based).
* EA07 (`StandardTransferAlgorithm`), EA09 (`DataEncryptionAlgorithm`,
  single-DES) and EA11 (`Misty1EncryptionAlgorithm` + raw `Misty1`)
  block ciphers, all pure-Dart.
* Class 0 SubClass 0 (electricity credit), Class 1 SubClasses 0/1
  (meter test / display) and Class 2 SubClasses 0/1/2/5/6 register
  family plus Class 2 SubClasses 3/4/8/9 key-change tokens with
  generators, decoders and `TokenDecoderDispatcher`.
* `VirtualHsm` with both the typed `deriveDecoderKey*` API and the
  NectarAPI-compatible `generateToken` / `decodeToken` param maps.
* `VirtualMeter` customer-side simulator (STA path) with JSON
  persistence and a `bin/meter.dart` CLI.
* Optional `shelf`-based HTTP server (`bin/server.dart`) exposing a
  NectarAPI-compatible REST surface — scoped to Class 0/0 electricity
  tokens for the MVP.
* Optional MySQL-backed meter registry and vending audit log
  (`lib/src/server/database.dart`) sharing the schema written by the
  Laravel `sts-vending` dashboard.
* DES + HMAC-SHA-256 primitives are vendored into
  `lib/src/_internal/` so the package has no `path:` dependencies.
