import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      // SCREENSHOT_DIR lets a second device (the iPad set) land elsewhere
      // without overwriting the iPhone captures.
      final dir = Platform.environment['SCREENSHOT_DIR'] ?? 'screenshots';
      final file = File('$dir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      return true;
    },
  );
}
