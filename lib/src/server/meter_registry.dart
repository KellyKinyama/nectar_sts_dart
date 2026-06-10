/// JSON-backed registry of provisioned meters, addressable by an
/// operator-chosen serial / asset tag.
///
/// The registry stores **identity only** (the IIN / IAIN / KEN / SGC /
/// TI / KRN / DKGA / EA tuple) — never the vending key. Token
/// generation uses the server's single global `VENDING_KEY_HEX`, so
/// the registry just spares operators from re-typing the meter's
/// identity in every `POST /v1/tokens` request.
///
/// **What is NOT persisted**:
///   - The vending key.
///   - Derived decoder keys.
///   - Per-meter balance (that lives on the meter itself; see
///     [VirtualMeter] for the customer-side simulator).
///
/// Single-utility, single-operator model: there is no per-utility
/// scoping or owner field. If you need multi-tenant scoping, run a
/// separate server (or graduate to the upstream Spring `user-service`).
library;

import 'dart:convert';
import 'dart:io';

import '../meter/virtual_meter.dart' show MeterIdentity;

/// One row in the meter registry.
class RegisteredMeter {
  /// Operator-chosen identifier. Stable, unique within the registry,
  /// case-sensitive. Used as the URL path segment and as the body
  /// field `meter_serial` on `POST /v1/tokens`.
  final String serial;
  final MeterIdentity identity;
  final String encryptionAlgorithm; // 'sta' | 'dea'
  final String? subscriberLabel;
  final DateTime registeredAt;

  const RegisteredMeter({
    required this.serial,
    required this.identity,
    this.encryptionAlgorithm = 'sta',
    this.subscriberLabel,
    required this.registeredAt,
  });

  Map<String, dynamic> toJson() => {
    'serial': serial,
    'registered_at': registeredAt.toUtc().toIso8601String(),
    'encryption_algorithm': encryptionAlgorithm,
    if (subscriberLabel != null) 'subscriber_label': subscriberLabel,
    'identity': identity.toJson(),
  };

  factory RegisteredMeter.fromJson(Map<String, dynamic> j) => RegisteredMeter(
    serial: j['serial'] as String,
    registeredAt: DateTime.parse(j['registered_at'] as String),
    encryptionAlgorithm: (j['encryption_algorithm'] as String?) ?? 'sta',
    subscriberLabel: j['subscriber_label'] as String?,
    identity: MeterIdentity.fromJson(j['identity'] as Map<String, dynamic>),
  );
}

/// Thrown by [MeterRegistry.register] when [RegisteredMeter.serial]
/// already exists.
class DuplicateMeterSerialException implements Exception {
  final String serial;
  const DuplicateMeterSerialException(this.serial);
  @override
  String toString() => 'DuplicateMeterSerialException: $serial';
}

/// Async-only surface that the REST layer consumes. Both the
/// JSON-file [MeterRegistry] and the MySQL-backed `DbMeterRegistry`
/// implement this so handlers don't have to know which is wired up.
///
/// Method names are intentionally distinct from the sync API on
/// [MeterRegistry] so the in-memory class can keep both.
abstract interface class MeterStore {
  /// Look up by serial. Returns `null` when not registered.
  Future<RegisteredMeter?> lookup(String serial);

  /// Persist [meter]. Throws [DuplicateMeterSerialException] on
  /// serial clash.
  Future<void> add(RegisteredMeter meter);

  /// Delete by serial. Returns `true` if a row was removed.
  Future<bool> delete(String serial);

  /// All meters currently registered.
  Future<List<RegisteredMeter>> list();

  /// Row count without materialising the full list.
  Future<int> total();
}

class MeterRegistry implements MeterStore {
  final List<RegisteredMeter> _meters;
  final DateTime createdAt;
  String? filePath;

  MeterRegistry({
    List<RegisteredMeter>? meters,
    DateTime? createdAt,
    this.filePath,
  }) : _meters = meters ?? <RegisteredMeter>[],
       createdAt = createdAt ?? DateTime.now().toUtc();

  List<RegisteredMeter> get meters => List.unmodifiable(_meters);
  int get length => _meters.length;

  RegisteredMeter? find(String serial) {
    for (final m in _meters) {
      if (m.serial == serial) return m;
    }
    return null;
  }

  /// Add [m]. Auto-flushes to disk if [filePath] is set.
  void register(RegisteredMeter m) {
    if (find(m.serial) != null) {
      throw DuplicateMeterSerialException(m.serial);
    }
    _meters.add(m);
    if (filePath != null) save();
  }

  /// Remove a meter by serial. Returns `true` if removed.
  bool remove(String serial) {
    final before = _meters.length;
    _meters.removeWhere((m) => m.serial == serial);
    final changed = _meters.length != before;
    if (changed && filePath != null) save();
    return changed;
  }

  // ---- MeterStore (async) -------------------------------------

  @override
  Future<RegisteredMeter?> lookup(String serial) async => find(serial);

  @override
  Future<void> add(RegisteredMeter meter) async => register(meter);

  @override
  Future<bool> delete(String serial) async => remove(serial);

  @override
  Future<List<RegisteredMeter>> list() async => meters;

  @override
  Future<int> total() async => length;

  // ---- persistence --------------------------------------------

  Map<String, dynamic> toJson() => {
    'schema': 'nectar_sts_dart.meter_registry/v1',
    'created_at': createdAt.toIso8601String(),
    'meters': _meters.map((m) => m.toJson()).toList(),
  };

  factory MeterRegistry.fromJson(Map<String, dynamic> j, {String? filePath}) {
    final schema = j['schema'];
    if (schema != null && schema != 'nectar_sts_dart.meter_registry/v1') {
      throw FormatException('Unsupported meter-registry schema: $schema');
    }
    return MeterRegistry(
      meters: ((j['meters'] as List?) ?? const [])
          .map((e) => RegisteredMeter.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: j['created_at'] is String
          ? DateTime.parse(j['created_at'] as String)
          : null,
      filePath: filePath,
    );
  }

  static MeterRegistry loadOrCreate(String filePath) {
    final f = File(filePath);
    if (!f.existsSync()) return MeterRegistry(filePath: filePath);
    final raw = f.readAsStringSync();
    if (raw.trim().isEmpty) return MeterRegistry(filePath: filePath);
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return MeterRegistry.fromJson(j, filePath: filePath);
  }

  void save([String? target]) {
    final path = target ?? filePath;
    if (path == null) {
      throw StateError('MeterRegistry.save: no path and no filePath set');
    }
    const enc = JsonEncoder.withIndent('  ');
    File(path).writeAsStringSync('${enc.convert(toJson())}\n');
    filePath = path;
  }
}
