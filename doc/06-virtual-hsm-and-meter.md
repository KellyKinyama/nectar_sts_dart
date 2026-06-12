# 06 — The virtual HSM & virtual meter

[◀ 05 — The decode path](./05-decode-path.md) · [TOC](./README.md) · [Next chapter: 07 — Compliance, testing & conclusion ▶](./07-compliance-and-conclusion.md)

---

So far we've followed a token through the algorithm in isolation.
This chapter glues the pieces into the two **stateful actors** of
a real prepaid-electricity deployment:

- the **HSM** at the utility / vendor end, which holds the vending
  key and mints tokens on request, and
- the **meter** at the customer end, which holds a personalised
  decoder key and applies tokens to a stored balance.

Both have software-only stand-ins in this port:

- [`VirtualHsm`](../lib/src/hsm/hsm.dart) +
  [`VirtualHsmDispatch`](../lib/src/hsm/virtual_hsm_dispatch.dart)
  ([`lib/src/hsm/`](../lib/src/hsm/)),
- [`VirtualMeter`](../lib/src/meter/virtual_meter.dart)
  ([`lib/src/meter/`](../lib/src/meter/)).

## The VirtualHsm

`Hsm` is a small interface — `generateToken`, `decodeToken`,
`describe` — that hides where the keys actually live. Real
deployments use a tamper-resistant Prism HSM via Thrift RPC; this
port ships [`PrismHsm`](../lib/src/hsm/hsm.dart) as a documented
stub that always throws `NotImplementedException`.

[`VirtualHsm`](../lib/src/hsm/hsm.dart) is the software equivalent:
keys live in process memory, and every operation just calls into
the generators / decoders from earlier chapters.

For end-to-end use, the recommended entry point is
[`VirtualHsmDispatch`](../lib/src/hsm/virtual_hsm_dispatch.dart),
which exposes a **flat `Map<String, dynamic>` API** mirroring the
JSON bodies the upstream Java service consumes. The same JSON that
goes to `POST /v1/tokens` in the Java service works against
`VirtualHsmDispatch.generateToken` here — so callers can swap
backends without changing wire format.

Supported via this layer:

- DKGA-02, DKGA-04
- EA07 (STA), EA09 (DEA, internal to DKGA-02), EA11 (MISTY1)
- Class 0 / SubClass 0 — `TransferElectricityCreditToken`
- Class 1 / SubClass 0 + 1 — `InitiateMeterTestOrDisplay1/2Token`
- Class 2 register family — `SetMaximumPowerLimit` (2/0),
  `ClearCredit` (2/1), `SetTariffRate` (2/2),
  `ClearTamperCondition` (2/5),
  `SetMaximumPhasePowerUnbalanceLimit` (2/6)
- Class 2 / SubClass 3 + 4 — `Set1stSection` / `Set2ndSectionDecoderKeyToken`
  (64-bit STA decoder-key rotation pair). Either side of the pair
  can also be generated under MISTY1 (the new-key splitter switches
  on the EA), but the meter currently only knows how to combine the
  STA halves.

Cleanly rejected with `NotImplementedException`:

- DKGA-01, DKGA-03
- Class 0 SubClass 1 (water), Class 0 SubClass 2 (gas)
- Class 2 / SubClass 7 — `SetWaterMeterFactor` (water only)
- Class 2 / SubClass 8 + 9 — `Set3rdSection` / `Set4thSectionDecoderKeyToken`
  (MISTY1 128-bit key-rotation path). The token classes, generators
  and decoder _are_ implemented and exported — see
  `Set3rdSectionDecoderKeyTokenGenerator` /
  `Set4thSectionDecoderKeyTokenGenerator` — but the param-map
  dispatch isn't wired yet (pending 4-section meter rotation).
- `type: "prism-thrift"` — use `PrismHsm` instead.

## The VirtualMeter

[`VirtualMeter`](../lib/src/meter/virtual_meter.dart) is a state
machine that owns:

| State                | Storage                                                  |
| -------------------- | -------------------------------------------------------- |
| Decoder key          | 8 bytes, set at construction (factory personalisation)   |
| kWh balance          | `double`, increments when credit tokens are applied      |
| Applied-tokens log   | `List<AppliedTokenRecord>` — for replay detection        |
| Last persistence     | Single JSON file on disk (`save` / `load`)               |

The single interesting method is `applyToken(String tokenNo)`, which:

1. Calls the dispatcher to **decode** the 20-digit token.
2. Returns a typed [`ApplyResult`](../lib/src/meter/virtual_meter.dart)
   — one of `ApplyAccepted`, `ApplyReplay`, `ApplyNonCredit`,
   `ApplyRejected` — depending on what came back.
3. For `ApplyAccepted`, it adds the amount to the balance, appends
   to the applied-tokens log, and saves to disk.
4. For `ApplyReplay`, the balance is left unchanged (the TID is
   already in the applied set).

That's it. The whole meter is ~250 lines of Dart, including JSON
serialisation. See [test/virtual_meter_test.dart](../test/virtual_meter_test.dart)
for a complete walk through `applyToken` happy path, replay, corrupted
token, and save → load round-trip.

## End-to-end demo

The Class 0/0 round-trip lives in
[test/virtual_hsm_dispatch_test.dart](../test/virtual_hsm_dispatch_test.dart):

```dart
// 1. The utility mints a token via the param-map API.
final genResult = virtualHsm.generateToken({
  'class':              0,
  'subclass':           0,
  'dkga':               '02',
  'ea':                 '07',
  'keyType':            2,
  'supplyGroupCode':    '123456',
  'tariffIndex':        '01',
  'keyRevisionNumber':  1,
  'iin':                '600727',
  'iain':               '00000000000',
  'vudk':               'abababababababab',
  'amount':             0.1,
  'dateOfIssue':        '2004-03-01T13:55:00Z',
  'randomNo':           5,
});
// genResult['tokenNo'] == '23716100501183194197'

// 2. The customer types it into the meter.
final apply = meter.applyToken(genResult['tokenNo'] as String);
// apply is ApplyAccepted(amountKwh: 0.1, newBalanceKwh: previous + 0.1, ...)

// 3. They type it AGAIN by mistake.
final replay = meter.applyToken(genResult['tokenNo'] as String);
// replay is ApplyReplay(tidMinutes: 5_836_875)
// balance unchanged.
```

The same flow goes over real HTTP in
[test/api_server_test.dart](../test/api_server_test.dart): a tiny
HTTP server in [`lib/src/server/`](../lib/src/server/) exposes
`POST /v1/tokens` (mint) and `POST /v1/tokens/{tokenNo}` (apply),
with bearer-token auth. The body schemas match the param-map API
above, so a JSON request that worked for the Java service drops in
unchanged.

## What this proves

Every concept from chapters 01..05 is exercised by these tests:

| Chapter                                       | Exercised by                                                         |
| --------------------------------------------- | -------------------------------------------------------------------- |
| 01 — Vending key & DKGA-02                    | `dispatch.generateToken` derives the key on every call.              |
| 02 — Data block + CRC                         | The decoder side asserts CRC; CRC errors surface as `ApplyRejected`. |
| 03 — EA07 encryption                          | Round-trip test in `encryption_test.dart` + every mint/apply pair.   |
| 04 — Transposition & 20-digit token           | The string the user types is exactly the canonical 20-digit form.    |
| 05 — Decode path                              | `applyToken` calls the dispatcher → decoder → field extraction.      |

In the final chapter we look at the STS6 reference vectors that
keep this whole stack honest, and at where to go from here.

---

[◀ 05 — The decode path](./05-decode-path.md) · [TOC](./README.md) · [Next chapter: 07 — Compliance, testing & conclusion ▶](./07-compliance-and-conclusion.md)
