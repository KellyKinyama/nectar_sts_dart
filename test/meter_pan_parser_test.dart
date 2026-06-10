// Tests for the MeterPrimaryAccountNumber string-parsing constructor.
// Mirrors the Java
//   src/test/java/ke/co/nectar/token/domain/token/
//     STSComplianceTests_STS_531_1_0_02_CTSA17.java
// vector plus a handful of round-trip / legacy-IIN positive cases used
// throughout the other CTSA suites in NO_METER_PAN_VALIDATION mode.
import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:test/test.dart';

void main() {
  group('MeterPrimaryAccountNumber.fromString', () {
    test('legacy 600727 prefix → 2-digit mfg, 6-digit IIN', () {
      final pan = MeterPrimaryAccountNumber.fromString(
        '600727000000000009',
        validate: MeterPanValidation.skip,
      );
      expect(pan.issuerIdentificationNumber.value, equals('600727'));
      expect(
        pan.individualAccountIdentificationNumber.value,
        equals('00000000000'),
      );
      expect(pan.meterPanValue, equals('600727000000000009'));
    });

    test('non-legacy prefix collapses to "0000" IIN + 4-digit mfg', () {
      final pan = MeterPrimaryAccountNumber.fromString(
        '000001000000000082',
        validate: MeterPanValidation.skip,
      );
      expect(pan.issuerIdentificationNumber.value, equals('0000'));
      expect(
        pan.individualAccountIdentificationNumber.value,
        equals('0100000000008'),
      );
      expect(pan.meterPanValue, equals('000001000000000082'));
    });

    test(
      'validate mode accepts a self-consistent PAN built from components',
      () {
        final built = MeterPrimaryAccountNumber(
          issuerIdentificationNumber: IssuerIdentificationNumber('600727'),
          individualAccountIdentificationNumber:
              IndividualAccountIdentificationNumber.fromComponents(
                manufacturerCode: '12',
                decoderSerialNumber: '34567890',
              ),
        );
        final reparsed = MeterPrimaryAccountNumber.fromString(
          built.meterPanValue,
        );
        expect(reparsed.meterPanValue, equals(built.meterPanValue));
      },
    );

    // CTSA17 — InvalidIAINNumberException on a malformed 22-digit string
    // whose extracted DRN check digit (`"1"`) does not match the Luhn
    // checksum of the recovered manufacturer code + DSN.
    test(
      'CTSA17 step1: "1234567890411111111113" → InvalidIAINNumberException',
      () {
        expect(
          () => MeterPrimaryAccountNumber.fromString(
            '1234567890411111111113',
          ),
          throwsA(
            isA<InvalidIAINNumberException>().having(
              (e) => e.message,
              'message',
              contains('Invalid Individual Account Identification Number'),
            ),
          ),
        );
      },
    );

    test('shorter than 18 characters is rejected', () {
      expect(
        () => MeterPrimaryAccountNumber.fromString('600727'),
        throwsA(isA<InvalidMeterPrimaryAccountNumberException>()),
      );
    });

    test('non-digit characters are rejected', () {
      expect(
        () => MeterPrimaryAccountNumber.fromString('60072700000000000X'),
        throwsA(isA<InvalidMeterPrimaryAccountNumberException>()),
      );
    });
  });
}
