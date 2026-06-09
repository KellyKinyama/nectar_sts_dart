# STS Nuts and Bolts — `nectar_sts_dart` walkthrough

A holistic, narrative walkthrough of how a 20-digit prepaid-electricity
token is **built**, **encrypted**, **transported**, **decoded**, and
**applied to a meter** under [IEC 62055-41](https://webstore.iec.ch/publication/22232)
("STS6" / the *Standard Transfer Specification*), as implemented in
this pure-Dart port of [`NectarAPI/tokens-service`](https://github.com/NectarAPI/tokens-service).

This document set is modelled on the *deductive*, follow-the-bits style
of [adalkiran/webrtc-nuts-and-bolts](https://github.com/adalkiran/webrtc-nuts-and-bolts):
instead of teaching the spec atomically and then assembling it, we
follow **one specific kWh top-up** all the way through — `0.1 kWh`,
issued at `2004-03-01 13:55:00 UTC` to meter PAN
`600727000000000009` — and explain each protocol layer at the moment
the journey reaches it.

By the end, you should be able to derive the token
`23716100501183194197` by hand (with a hex calculator) from the
vending key `abababababababab`.

## Chapters

| #   | Chapter                                                            | What you'll learn                                                                                  |
| --- | ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| 00  | [Infrastructure](./00-infrastructure.md)                           | Repo layout, build/run, dependency graph, scope decisions.                                         |
| 01  | [The vending key & DKGA-02](./01-the-vending-key-and-dkga-02.md)  | How `VUDK abababababababab` becomes per-meter decoder key `6ff35b9d1f3453e6` via DES.              |
| 02  | [Building the data block](./02-data-block-and-crc.md)              | Amount, TokenIdentifier (TID), RandomNo, SubClass and the CRC-16/IBM that ties them together.     |
| 03  | [EA07 — Standard Transfer Algorithm](./03-ea07-encryption.md)      | The 16-round substitution-permutation cipher that encrypts the 64-bit data block.                  |
| 04  | [Transposition & the 20-digit token](./04-transposition-and-token-no.md) | Splicing the 2-bit class into bits 27/28, prepending the displaced bits, and the BigInt-to-decimal final step. |
| 05  | [The decode path](./05-decode-path.md)                             | What the meter does in reverse: untranspose, decrypt, verify CRC, extract fields.                  |
| 06  | [The virtual HSM & virtual meter](./06-virtual-hsm-and-meter.md)   | End-to-end demo: a software HSM mints a token, a software meter applies it, replays are rejected.  |
| 07  | [Compliance, testing & conclusion](./07-compliance-and-conclusion.md) | The STS6 reference vectors, what is and isn't tested, where to go from here.                       |

## Reference appendix

- [STS compliance vector reference](./sts_compliance.md) — concise
  tabular reference for the three CTSA01 / standalone test vectors
  ported into [test/sts_compliance_test.dart](../test/sts_compliance_test.dart).

## Conventions used in these documents

- **Bit positions** are LSB-first, the same convention the Java
  reference and this port both use. So in the 64-bit data block,
  *bit 0* is the **least-significant** bit (low end of the CRC field),
  and *bit 63* is the **most-significant** bit (high end of the
  SubClass field).
- **Byte-array hex** is shown in network order, e.g. the decoder key
  `[0x6F, 0xF3, 0x5B, 0x9D, 0x1F, 0x34, 0x53, 0xE6]` is written
  `6ff35b9d1f3453e6`.
- **Times** are written in ISO-8601 UTC. The Java reference uses Joda
  `DateTimeFormat.forPattern("dd/MM/yyyy HH:mm:ss")` in the JVM
  default time zone; we treat those literals as UTC. See
  [01-the-vending-key-and-dkga-02.md](./01-the-vending-key-and-dkga-02.md#aside-on-time-zones)
  for why this matches the upstream test vectors.
- File / line citations link to the relevant code, e.g.
  [`lib/src/decoderkey/dkga02.dart`](../lib/src/decoderkey/dkga02.dart).

---

[Next chapter: 00 — Infrastructure ▶](./00-infrastructure.md)
