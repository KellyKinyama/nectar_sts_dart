import 'package:nectar_sts_dart/src/server/tariff.dart';
import 'package:test/test.dart';

void main() {
  group('Tariff', () {
    test('moneyFor / kwhFor are inverses (no admin fee)', () {
      final t = Tariff(currency: 'KES', pricePerKwh: 24.0);
      expect(t.moneyFor(2.5), closeTo(60.0, 1e-9));
      expect(t.kwhFor(60.0), closeTo(2.5, 1e-9));
    });

    test('admin fee is added to money cost, subtracted from kWh', () {
      final t = Tariff(currency: 'IDR', pricePerKwh: 1444, adminFee: 2500);
      // 20 000 - 2 500 = 17 500 / 1 444 = 12.118…
      expect(t.kwhFor(20000), closeTo(17500 / 1444, 1e-9));
      expect(t.moneyFor(12.118), closeTo(12.118 * 1444 + 2500, 1e-6));
    });

    test('kwhFor returns 0 when money only covers admin fee', () {
      final t = Tariff(currency: 'KES', pricePerKwh: 24.0, adminFee: 50);
      expect(t.kwhFor(50), 0.0);
      expect(t.kwhFor(30), 0.0);
    });

    test('asserts on non-positive price', () {
      expect(() => Tariff(currency: 'KES', pricePerKwh: 0), throwsA(anything));
    });
  });

  group('TariffBook.fromEnv', () {
    test('empty env yields an empty book', () {
      final b = TariffBook.fromEnv({});
      expect(b.isEmpty, isTrue);
      expect(b.lookup('01'), isNull);
    });

    test(
      'single fallback tariff via TARIFF_PRICE_PER_KWH + TARIFF_CURRENCY',
      () {
        final b = TariffBook.fromEnv({
          'TARIFF_PRICE_PER_KWH': '24.5',
          'TARIFF_CURRENCY': 'kes',
          'TARIFF_ADMIN_FEE': '5',
        });
        expect(b.isEmpty, isFalse);
        final t = b.lookup('07');
        expect(t, isNotNull);
        expect(t!.currency, 'KES'); // upper-cased
        expect(t.pricePerKwh, 24.5);
        expect(t.adminFee, 5);
      },
    );

    test('TARIFF_TABLE picks per-index entries before falling back', () {
      final b = TariffBook.fromEnv({
        'TARIFF_TABLE':
            '{"01":{"price_per_kwh":24,"currency":"KES"},'
            '"02":{"price_per_kwh":1444,"currency":"IDR","admin_fee":2500}}',
        'TARIFF_PRICE_PER_KWH': '100',
        'TARIFF_CURRENCY': 'USD',
      });
      expect(b.lookup('01')!.currency, 'KES');
      expect(b.lookup('02')!.currency, 'IDR');
      expect(b.lookup('02')!.adminFee, 2500);
      expect(b.lookup('99')!.currency, 'USD'); // fallback
    });

    test('malformed TARIFF_TABLE throws FormatException', () {
      expect(
        () => TariffBook.fromEnv({'TARIFF_TABLE': '["not", "an", "object"]'}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
