import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:expnd/services/receipts.dart';

void main() {
  late Directory docs;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('expnd_receipts');
    Receipts.init(docs);
  });

  tearDown(() => docs.deleteSync(recursive: true));

  test('stores only the file name', () {
    expect(
      Receipts.storedName('/a/b/Documents/receipt_1.jpg'),
      'receipt_1.jpg',
    );
  });

  test('resolves a bare file name inside Documents', () {
    File('${docs.path}/receipt_1.jpg').writeAsBytesSync([1]);
    expect(
      Receipts.fileFor('receipt_1.jpg')?.path,
      '${docs.path}/receipt_1.jpg',
    );
  });

  test('re-roots an absolute path from a moved container', () {
    File('${docs.path}/receipt_2.jpg').writeAsBytesSync([1]);
    const stale =
        '/var/mobile/Containers/Data/Application/OLD/Documents/'
        'receipt_2.jpg';
    expect(Receipts.fileFor(stale)?.path, '${docs.path}/receipt_2.jpg');
  });

  test('a missing receipt resolves to null', () {
    expect(Receipts.fileFor('receipt_3.jpg'), isNull);
    expect(Receipts.fileFor(null), isNull);
  });
}
