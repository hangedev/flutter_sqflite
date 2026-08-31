import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/src/constant.dart';
import 'package:sqflite/src/factory_impl.dart';
import 'package:sqflite/src/sqflite_android.dart';
import 'package:sqflite_common/src/internals.dart' show DatabaseInternalsExt;

import 'mock_sqflite_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;

  late MockSqfliteEngine engine;
  late Database db;

  setUp(() async {
    engine = MockSqfliteEngine();
    db = await openDatabase(inMemoryDatabasePath);
  });

  tearDown(() async {
    if (db.isOpen) {
      await db.close();
    }
    engine.uninstall();
  });

  group('SqfliteDatabaseAndroidExt', () {
    test('should send the locale over the method channel', () async {
      await SqfliteDatabaseAndroidExt(db).androidSetLocale('zh-CN');

      final calls = engine.callsFor(methodAndroidSetLocale);
      expect(calls, hasLength(1));
      expect(calls.first.arguments, <String, Object?>{
        paramId: db.databaseId,
        paramLocale: 'zh-CN',
      });
    });
  });

  group('SqfliteDatabaseAndroidExtImpl', () {
    test('should send the database id and the locale', () async {
      await SqfliteDatabaseAndroidExtImpl(db).androidSetLocale('en-US');

      final calls = engine.callsFor(methodAndroidSetLocale);
      expect(calls, hasLength(1));
      expect(calls.first.arguments, <String, Object?>{
        paramId: db.databaseId,
        paramLocale: 'en-US',
      });
    });

    test('should wrap a channel error into a DatabaseException', () async {
      engine.responders[methodAndroidSetLocale] = (MethodCall call) {
        throw PlatformException(
            code: 'sqlite_error', message: 'failed setting locale (code 1)');
      };

      try {
        await SqfliteDatabaseAndroidExtImpl(db).androidSetLocale('zh-CN');
        fail('should fail');
      } on DatabaseException catch (e) {
        expect(e.toString(), contains('failed setting locale'));
      }
    });
  });
}
