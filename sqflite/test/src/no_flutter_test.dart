import 'package:flutter_test/flutter_test.dart';
import 'package:process_run/shell_run.dart';

void main() {
  group('no_flutter', () {
    test('should open a database without a flutter binding when using '
        'buildDatabaseFactory', () async {
      await run('dart test/src/no_flutter_main.dart');
    });
  });
}
