/// MySQL-backed replacement for [MeterRegistry].
///
/// Same conceptual surface as the JSON-file registry, but every
/// method is async because we hit the DB. Designed to share the
/// `meters` / `supply_groups` / `vending_keys` tables with the
/// Laravel `sts-vending` dashboard.
///
/// Mapping (Dart-side `RegisteredMeter` ⇄ Laravel `meters` row):
///   serial               ⇄ meters.decoder_serial_number
///   identity.IIN         ⇄ meters.iin
///   identity.DRN (IAIN)  ⇄ meters.iain
///   identity.SGC         ⇄ supply_groups.code (FK lookup)
///   identity.KT/TI/KRN/  ⇄ vending_keys.*  (carried for context only;
///   DKGA/BD                 the secret VUDK is NOT read by the Dart
///                           server — it uses its env-var key.)
///   subscriberLabel      ⇄ meters.location
///   encryptionAlgorithm  ⇄ vending_keys.encryption_algorithm
///
/// **Pre-provisioning.** The Dart server does NOT create
/// `supply_groups` or `vending_keys` rows. Both are admin-owned in
/// the Laravel dashboard. [register] throws
/// [MissingForeignRowException] if the matching SGC row is missing,
/// telling the operator to create it in the dashboard first.
library;

import '../meter/virtual_meter.dart' show MeterIdentity;
import 'db_queries.dart';
import 'meter_registry.dart'
    show DuplicateMeterSerialException, MeterStore, RegisteredMeter;

class DbMeterRegistry implements MeterStore {
  /// Cached count, refreshed by the mutating methods. Lets sync
  /// callers (logging, status banners) read a sensible value
  /// without an extra round-trip.
  int _count = 0;

  /// Returns the cached count. Call [refreshCount] to update it.
  int get length => _count;

  Future<void> refreshCount() async {
    _count = await DbQueries.meterCount();
  }

  /// Look up by `decoder_serial_number`. Returns `null` if not found.
  @override
  Future<RegisteredMeter?> lookup(String serial) async {
    final row = await DbQueries.findMeterBySerial(serial);
    if (row == null) return null;
    return _toRegisteredMeter(row);
  }

  /// All registered meters (joined view).
  @override
  Future<List<RegisteredMeter>> list({int limit = 500}) async {
    final rows = await DbQueries.listMeters(limit: limit);
    return rows.map(_toRegisteredMeter).toList();
  }

  @override
  Future<int> total() async {
    await refreshCount();
    return _count;
  }

  /// Insert. Throws [DuplicateMeterSerialException] on serial clash
  /// and [MissingForeignRowException] when the SGC row is missing.
  @override
  Future<void> add(RegisteredMeter m) async {
    if (m.serial.isEmpty) {
      throw ArgumentError.value(m.serial, 'serial', 'must not be empty');
    }
    final existing = await DbQueries.findMeterBySerial(m.serial);
    if (existing != null) {
      throw DuplicateMeterSerialException(m.serial);
    }
    final pan = _composePan(m.identity);
    await DbQueries.registerMeter(
      pan: pan,
      iin: m.identity.issuerIdentificationNumber,
      iain: m.identity.individualAccountIdentificationNumber,
      supplyGroupCode: m.identity.supplyGroupCode,
      decoderSerialNumber: m.serial,
      location: m.subscriberLabel,
      isActive: true,
    );
    _count++;
  }

  /// Remove by serial. Returns `true` if a row was deleted.
  @override
  Future<bool> delete(String serial) async {
    final ok = await DbQueries.removeMeterBySerial(serial);
    if (ok && _count > 0) _count--;
    return ok;
  }

  // ---- mapping --------------------------------------------------

  static RegisteredMeter _toRegisteredMeter(MeterRow r) {
    final identity = MeterIdentity.fromJson({
      'issuer_identification_no': r.iin,
      'decoder_reference_number': r.iain,
      'key_type': r.keyType ?? 2,
      'supply_group_code': r.supplyGroupCode,
      'tariff_index': r.tariffIndex ?? '01',
      'key_revision_no': r.keyRevisionNumber ?? 1,
      'decoder_key_generation_algorithm': _normaliseDkga(r.algorithm) ?? '02',
      if (r.baseDate != null) 'base_date': r.baseDate.toString(),
    });
    return RegisteredMeter(
      serial: r.decoderSerialNumber ?? '#${r.id}',
      identity: identity,
      encryptionAlgorithm: _normaliseEa(r.encryptionAlgorithm) ?? 'sta',
      subscriberLabel: r.location,
      registeredAt: DateTime.now().toUtc(),
    );
  }

  /// Laravel stores `DKGA02` / `DKGA04`; the Dart side uses `02` / `04`.
  static String? _normaliseDkga(String? v) {
    if (v == null) return null;
    if (v.toUpperCase().startsWith('DKGA')) {
      return v.substring(4);
    }
    return v;
  }

  /// Laravel stores `EA07` / `EA11`; the Dart side uses `sta` / `dea`.
  static String? _normaliseEa(String? v) {
    if (v == null) return null;
    switch (v.toUpperCase()) {
      case 'EA07':
        return 'sta';
      case 'EA11':
        return 'dea';
      default:
        return v.toLowerCase();
    }
  }

  /// PAN = IIN (6 digits) + IAIN. The Laravel migration constrains
  /// the column to exactly 18 chars; if IAIN is 11 digits we pad the
  /// extra position with `0` so the IIN+IAIN concatenation fits.
  static String _composePan(MeterIdentity id) {
    var iin = id.issuerIdentificationNumber;
    var iain = id.individualAccountIdentificationNumber;
    if (iin.length != 6) {
      iin = iin.padLeft(6, '0').substring(0, 6);
    }
    final padded = iain.length == 11 ? '0$iain' : iain;
    final composed = '$iin$padded';
    if (composed.length != 18) {
      throw ArgumentError(
        'PAN must be 18 digits; got "$composed" (len=${composed.length}). '
        'IIN=$iin (${iin.length}), IAIN=$iain (${iain.length}).',
      );
    }
    return composed;
  }
}
