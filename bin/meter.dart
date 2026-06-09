/// Virtual STS meter CLI.
///
/// Three subcommands, each operating on a JSON state file (the
/// "non-volatile memory" of the simulated meter).
///
///   dart run bin/meter.dart setup --file <path> \
///     --iin 600727 --iain 12345678901 \
///     --key-type 2 --sgc 123456 --ti 07 --krn 1 \
///     --vending-key-hex 0123456789ABCDEF \
///     [--dkga 02|04] [--base-date 1993] \
///     [--ea sta|dea] [--balance 0]
///
///   dart run bin/meter.dart info --file <path>
///
///   dart run bin/meter.dart apply --file <path> --token <20digits>
///
/// All output is plain text on stdout; errors go to stderr with a
/// non-zero exit code. `setup` overwrites the file if it exists,
/// `apply` rewrites it in-place after a successful credit.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';

const _usage = '''
Virtual STS meter — JSON-persisted simulator.

Usage:
  meter setup --file <path> --iin <iin> --iain <iain> --key-type <n>
              --sgc <sgc> --ti <ti> --krn <n> --vending-key-hex <hex>
              [--dkga 02|04] [--base-date <yyyy>]
              [--ea sta|dea] [--balance <kWh>]
  meter info  --file <path>
  meter apply --file <path> --token <20-digit>

  meter help  (this message)
''';

int main(List<String> argv) {
  if (argv.isEmpty || argv.first == 'help' || argv.first == '--help') {
    stdout.write(_usage);
    return 0;
  }
  final cmd = argv.first;
  final args = _parseFlags(argv.skip(1).toList());
  try {
    switch (cmd) {
      case 'setup':
        return _cmdSetup(args);
      case 'info':
        return _cmdInfo(args);
      case 'apply':
        return _cmdApply(args);
      default:
        stderr.writeln('Unknown command: $cmd\n');
        stderr.write(_usage);
        return 64; // EX_USAGE
    }
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}');
    return 65;
  } on StsError catch (e) {
    stderr.writeln('error: ${e.runtimeType}: ${e.message}');
    return 65;
  } on FileSystemException catch (e) {
    stderr.writeln('error: ${e.message} (${e.path})');
    return 66;
  }
}

// ---- commands ---------------------------------------------------

int _cmdSetup(Map<String, String> args) {
  final file = _required(args, 'file');
  final identity = MeterIdentity(
    issuerIdentificationNumber: _required(args, 'iin'),
    individualAccountIdentificationNumber: _required(args, 'iain'),
    keyType: int.parse(_required(args, 'key-type')),
    supplyGroupCode: _required(args, 'sgc'),
    tariffIndex: _required(args, 'ti'),
    keyRevisionNumber: int.parse(_required(args, 'krn')),
    decoderKeyGenerationAlgorithm: args['dkga'] ?? '02',
    baseDate: args['base-date'],
  );
  final vendingKey = parseHexKey(_required(args, 'vending-key-hex'));
  final ea = args['ea'] ?? 'sta';
  final balance = double.parse(args['balance'] ?? '0');

  final meter = VirtualMeter.setup(
    identity: identity,
    vendingKeyBytes: vendingKey,
    encryptionAlgorithm: ea,
    initialBalanceKwh: balance,
    filePath: file,
  );
  meter.save();

  stdout.writeln('Provisioned meter -> $file');
  stdout.writeln(
    '  IIN/IAIN     : ${identity.issuerIdentificationNumber} / '
    '${identity.individualAccountIdentificationNumber}',
  );
  stdout.writeln(
    '  SGC/TI/KRN   : ${identity.supplyGroupCode} / '
    '${identity.tariffIndex} / ${identity.keyRevisionNumber}',
  );
  stdout.writeln(
    '  DKGA / EA    : '
    '${identity.decoderKeyGenerationAlgorithm} / $ea',
  );
  stdout.writeln(
    '  Decoder key  : ${_hex(meter.decoderKeyBytes)} '
    '(${meter.decoderKeyBytes.length} bytes)',
  );
  stdout.writeln('  Balance      : ${meter.balanceKwh.toStringAsFixed(3)} kWh');
  return 0;
}

int _cmdInfo(Map<String, String> args) {
  final file = _required(args, 'file');
  final meter = VirtualMeter.load(file);
  stdout.writeln('Meter @ $file');
  stdout.writeln('  Created      : ${meter.createdAt.toIso8601String()}');
  stdout.writeln(
    '  IIN/IAIN     : '
    '${meter.identity.issuerIdentificationNumber} / '
    '${meter.identity.individualAccountIdentificationNumber}',
  );
  stdout.writeln(
    '  SGC/TI/KRN   : ${meter.identity.supplyGroupCode} / '
    '${meter.identity.tariffIndex} / ${meter.identity.keyRevisionNumber}',
  );
  stdout.writeln(
    '  DKGA / EA    : '
    '${meter.identity.decoderKeyGenerationAlgorithm} / '
    '${meter.encryptionAlgorithmName}',
  );
  stdout.writeln('  Decoder key  : ${_hex(meter.decoderKeyBytes)}');
  stdout.writeln('  Balance      : ${meter.balanceKwh.toStringAsFixed(3)} kWh');
  stdout.writeln('  Tokens used  : ${meter.appliedTokens.length}');
  if (meter.appliedTokens.isNotEmpty) {
    stdout.writeln('  Recent:');
    final recent = meter.appliedTokens.reversed.take(5);
    for (final r in recent) {
      stdout.writeln(
        '    ${r.appliedAt.toIso8601String()}  '
        '+${r.amountKwh.toStringAsFixed(3)} kWh  '
        'tid=${r.tidMinutes}  ${r.tokenNo}',
      );
    }
  }
  return 0;
}

int _cmdApply(Map<String, String> args) {
  final file = _required(args, 'file');
  final tokenNo = _required(args, 'token').replaceAll(RegExp(r'\s+'), '');
  if (!RegExp(r'^\d{20}$').hasMatch(tokenNo)) {
    stderr.writeln('error: --token must be exactly 20 decimal digits');
    return 64;
  }
  final meter = VirtualMeter.load(file);
  final result = meter.applyToken(tokenNo);

  switch (result) {
    case ApplyAccepted(
      :final amountKwh,
      :final newBalanceKwh,
      :final tidMinutes,
      :final issuedAt,
    ):
      meter.save();
      stdout.writeln('ACCEPTED  +${amountKwh.toStringAsFixed(3)} kWh');
      stdout.writeln(
        '  tid          : $tidMinutes '
        '(issued ${issuedAt.toIso8601String()})',
      );
      stdout.writeln(
        '  new balance  : ${newBalanceKwh.toStringAsFixed(3)} kWh',
      );
      return 0;
    case ApplyReplay(:final tidMinutes):
      stdout.writeln(
        'REPLAY    tid=$tidMinutes already applied; '
        'balance unchanged (${meter.balanceKwh.toStringAsFixed(3)} kWh)',
      );
      return 0;
    case ApplyNonCredit(:final tokenType):
      stdout.writeln(
        'NON-CREDIT ($tokenType) — decoded successfully '
        'but does not carry a balance; not persisted',
      );
      return 0;
    case ApplyRejected(:final reason):
      stderr.writeln('REJECTED: $reason');
      return 65;
  }
}

// ---- helpers ----------------------------------------------------

Map<String, String> _parseFlags(List<String> argv) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (!a.startsWith('--')) {
      throw FormatException('Expected --flag, got "$a"');
    }
    final key = a.substring(2);
    if (i + 1 >= argv.length || argv[i + 1].startsWith('--')) {
      throw FormatException('Flag --$key has no value');
    }
    out[key] = argv[++i];
  }
  return out;
}

String _required(Map<String, String> args, String key) {
  final v = args[key];
  if (v == null || v.isEmpty) {
    throw FormatException('Missing required flag: --$key');
  }
  return v;
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
