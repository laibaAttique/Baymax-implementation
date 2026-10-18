// Host-side driver for the real-device integration tests (run with `flutter drive`, see integration_test/README.md).
// Saves each screenshot the tests take and the per-case results the tests report.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final out = Directory(Platform.environment['BAYMAX_EVIDENCE_DIR'] ?? 'build/device_evidence');
  final shots = Directory('${out.path}/screenshots')..createSync(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      File('${shots.path}/$name.png').writeAsBytesSync(bytes);
      return true;
    },
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      // Screenshot bytes are already saved as PNG files above; keep the JSON small.
      final shots = data?.remove('screenshots') as List?;
      if (shots != null) data!['_note'] = '${shots.length} screenshot byte arrays removed; images are in screenshots/';
      File('${out.path}/device_results.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    },
  );
}
