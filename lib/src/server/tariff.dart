/// Tariff configuration + kWh ↔ money conversion for the HTTP API.
///
/// A [Tariff] is a `(price_per_kwh, currency, admin_fee)` triple.
/// A [TariffBook] is a lookup keyed by `tariff_index` (the same
/// 2-digit field that already drives DKGA), with an optional
/// fallback applied when the requested index isn't in the table.
///
/// The API layer is currency-agnostic: a token's `amount` field is
/// always in **kWh** on the wire and inside the cipher. Money lives
/// only in the request envelope (`amount_money` + `currency`) and
/// in the response envelope (`pricing` block). The DB stores the
/// resolved kWh + the originating currency code so the dashboard
/// can render either.
///
/// `TariffBook.fromEnv` reads either:
///   - `TARIFF_TABLE='{"01":{"price_per_kwh":24.0,"currency":"KES",
///                       "admin_fee":0.0}, …}'`  (full table), OR
///   - `TARIFF_PRICE_PER_KWH=24.0`, `TARIFF_CURRENCY=KES`,
///     `TARIFF_ADMIN_FEE=0.0`  (single fallback tariff applied to
///     any tariff_index).
library;

import 'dart:convert';

/// Immutable per-`tariff_index` pricing record.
class Tariff {
  /// ISO-4217-style currency code. Not validated against any
  /// registry — passed through verbatim so the dashboard renders
  /// what the operator configured.
  final String currency;

  /// Strictly positive. Units are *currency per kWh*.
  final double pricePerKwh;

  /// Flat fee added to the cash total. Zero by default. Not
  /// subtracted from kWh — the customer pays
  /// `kWh × pricePerKwh + adminFee` and receives `kWh` units.
  final double adminFee;

  const Tariff({
    required this.currency,
    required this.pricePerKwh,
    this.adminFee = 0.0,
  }) : assert(pricePerKwh > 0, 'pricePerKwh must be > 0');

  /// kWh that `money` buys at this tariff, **net of admin fee**.
  /// Returns 0 if `money <= adminFee`.
  double kwhFor(double money) {
    final net = money - adminFee;
    if (net <= 0) return 0.0;
    return net / pricePerKwh;
  }

  /// Money cost (incl. admin fee) of `kwh` at this tariff.
  double moneyFor(double kwh) => kwh * pricePerKwh + adminFee;

  Map<String, dynamic> toJson() => {
        'currency': currency,
        'price_per_kwh': pricePerKwh,
        if (adminFee != 0.0) 'admin_fee': adminFee,
      };

  factory Tariff.fromJson(Map<String, dynamic> j) => Tariff(
        currency: (j['currency'] as String).toUpperCase(),
        pricePerKwh: _asDouble(j['price_per_kwh'], 'price_per_kwh'),
        adminFee: j['admin_fee'] == null
            ? 0.0
            : _asDouble(j['admin_fee'], 'admin_fee'),
      );

  @override
  String toString() => 'Tariff(currency: $currency, pricePerKwh: $pricePerKwh, '
      'adminFee: $adminFee)';
}

/// Lookup table keyed by `tariff_index`.
class TariffBook {
  final Map<String, Tariff> _byIndex;
  final Tariff? fallback;

  TariffBook({Map<String, Tariff>? byTariffIndex, this.fallback})
      : _byIndex = Map.unmodifiable(byTariffIndex ?? const <String, Tariff>{});

  /// `true` when the book has neither a per-index entry nor a
  /// fallback. The server treats an empty book as "no money math".
  bool get isEmpty => _byIndex.isEmpty && fallback == null;

  Map<String, Tariff> get byTariffIndex => _byIndex;

  Tariff? lookup(String? tariffIndex) {
    if (tariffIndex == null) return fallback;
    return _byIndex[tariffIndex] ?? fallback;
  }

  /// Build a book from a process-env-shaped map. Returns an empty
  /// book (`isEmpty == true`) when neither `TARIFF_TABLE` nor
  /// `TARIFF_PRICE_PER_KWH` are set.
  factory TariffBook.fromEnv(Map<String, String> env) {
    final table = env['TARIFF_TABLE']?.trim();
    if (table != null && table.isNotEmpty) {
      final decoded = jsonDecode(table);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException(
          'TARIFF_TABLE must be a JSON object keyed by tariff_index, '
          'got: ${decoded.runtimeType}',
        );
      }
      final entries = <String, Tariff>{};
      for (final e in decoded.entries) {
        final v = e.value;
        if (v is! Map<String, dynamic>) {
          throw FormatException(
            'TARIFF_TABLE["${e.key}"] must be an object, got: '
            '${v.runtimeType}',
          );
        }
        entries[e.key] = Tariff.fromJson(v);
      }
      return TariffBook(
        byTariffIndex: entries,
        fallback: _fallbackFromEnv(env),
      );
    }
    final single = _fallbackFromEnv(env);
    return TariffBook(fallback: single);
  }

  static Tariff? _fallbackFromEnv(Map<String, String> env) {
    final price = env['TARIFF_PRICE_PER_KWH']?.trim();
    final currency = env['TARIFF_CURRENCY']?.trim();
    if (price == null ||
        price.isEmpty ||
        currency == null ||
        currency.isEmpty) {
      return null;
    }
    return Tariff(
      currency: currency.toUpperCase(),
      pricePerKwh: _asDouble(price, 'TARIFF_PRICE_PER_KWH'),
      adminFee: env['TARIFF_ADMIN_FEE'] == null
          ? 0.0
          : _asDouble(env['TARIFF_ADMIN_FEE']!.trim(), 'TARIFF_ADMIN_FEE'),
    );
  }
}

/// Pricing breakdown returned alongside a successful credit-token
/// mint. All fields are present for credit tokens when a tariff is
/// in scope; null/absent otherwise.
class PricingBreakdown {
  final String tariffIndex;
  final String currency;
  final double pricePerKwh;
  final double adminFee;
  final double kwh;
  final double amountMoney;
  final double total;

  const PricingBreakdown({
    required this.tariffIndex,
    required this.currency,
    required this.pricePerKwh,
    required this.adminFee,
    required this.kwh,
    required this.amountMoney,
    required this.total,
  });

  Map<String, dynamic> toJson() => {
        'tariff_index': tariffIndex,
        'currency': currency,
        'price_per_kwh': pricePerKwh,
        if (adminFee != 0.0) 'admin_fee': adminFee,
        'kwh': kwh,
        'amount_money': amountMoney,
        'total_money': total,
      };
}

double _asDouble(Object? v, String fieldName) {
  if (v is num) return v.toDouble();
  if (v is String) {
    final parsed = double.tryParse(v);
    if (parsed != null) return parsed;
  }
  throw FormatException('$fieldName must be a number, got: $v');
}
