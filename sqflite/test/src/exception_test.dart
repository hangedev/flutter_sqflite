import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/src/factory_impl.dart';
import 'package:sqflite/src/mixin.dart' show SqfliteDatabaseMixin;
import 'package:sqflite/src/sql_builder.dart';
import 'package:sqflite_common/src/value_utils.dart' show checkThrowException;

import 'mock_sqflite_engine.dart';

/// Matches a [DatabaseException] flagged as a database closed error.
final Matcher throwsDatabaseClosed = throwsA(
    isA<DatabaseException>()
        .having((DatabaseException e) => e.isDatabaseClosedError(),
            'isDatabaseClosedError', isTrue));

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

  group('openDatabase 参数校验', () {
    test('should reject a version of 0', () {
      expect(
          openDatabase('arg_version0_test.db',
              version: 0, onCreate: (Database db, int version) async {}),
          throwsArgumentError);
    });

    test('should reject onCreate without a version', () {
      expect(
          openDatabase('arg_oncreate_test.db',
              onCreate: (Database db, int version) async {}),
          throwsArgumentError);
    });

    test('should reject onUpgrade without a version', () {
      expect(
          openDatabase('arg_onupgrade_test.db',
              onUpgrade:
                  (Database db, int oldVersion, int newVersion) async {}),
          throwsArgumentError);
    });

    test('should reject onDowngrade without a version', () {
      expect(
          openDatabase('arg_ondowngrade_test.db',
              onDowngrade:
                  (Database db, int oldVersion, int newVersion) async {}),
          throwsArgumentError);
    });

    test('should reject a null path', () {
      expect(() => openDatabase(null as dynamic), throwsA(isA<TypeError>()));
    });
  });

  group('SqlBuilder 参数校验', () {
    test('should reject a having clause without groupBy', () {
      expect(
          () => SqlBuilder.query('test', having: 'count(*) > 1'),
          throwsArgumentError);
    });

    test('should reject an update without values', () {
      expect(() => SqlBuilder.update('test', <String, Object?>{}),
          throwsArgumentError);
    });

    test('should reject an empty insert without nullColumnHack', () {
      expect(() => SqlBuilder.insert('test', <String, Object?>{}),
          throwsArgumentError);
    });

    test('should insert an explicit null when using nullColumnHack', () {
      final builder =
          SqlBuilder.insert('test', <String, Object?>{}, nullColumnHack: 'a');
      expect(builder.sql, 'INSERT INTO test (a) VALUES (NULL)');
      expect(builder.arguments, isNull);
    });

    test('should build a delete with an optional where clause', () {
      final builder = SqlBuilder.delete('test',
          where: 'id = ?', whereArgs: <Object?>[1]);
      expect(builder.sql, 'DELETE FROM test WHERE id = ?');
      expect(builder.arguments, <Object?>[1]);
    });

    test('should build a query with limit and offset', () {
      final withLimitOnly =
          SqlBuilder.query('test', limit: 10, orderBy: 'id');
      expect(withLimitOnly.sql, 'SELECT * FROM test ORDER BY id LIMIT 10');

      final withOffsetOnly = SqlBuilder.query('test', offset: 5);
      expect(withOffsetOnly.sql, 'SELECT * FROM test LIMIT -1 OFFSET 5');

      final distinct =
          SqlBuilder.query('test', distinct: true, columns: <String>['a', 'b']);
      expect(distinct.sql, 'SELECT DISTINCT a, b FROM test');
    });
  });

  group('无效参数类型', () {
    setUp(() {
      checkThrowException = true;
    });

    tearDown(() {
      checkThrowException = false;
    });

    test('should reject unsupported values in insert', () {
      expect(
          () => db.insert('test', <String, Object?>{
                'name': DateTime.fromMillisecondsSinceEpoch(0)
              }),
          throwsArgumentError);
    });

    test('should reject unsupported raw query arguments', () {
      expect(
          () => db.rawQuery('SELECT * FROM test WHERE id = ?', <Object?>[true]),
          throwsArgumentError);
    });

    test('should reject unsupported where arguments', () {
      expect(
          () => db.update('test', <String, Object?>{'name': 'a'},
              where: 'id = ?', whereArgs: <Object?>[<String, Object?>{}]),
          throwsArgumentError);
    });
  });

  group('状态异常：数据库已关闭', () {
    test('should reject crud operations on a closed database', () async {
      await db.close();
      expect(() async {
        await db.execute('SELECT 1');
      }, throwsDatabaseClosed);
      expect(() async {
        await db.rawInsert('INSERT INTO test VALUES (1)');
      }, throwsDatabaseClosed);
      expect(() async {
        await db.query('test');
      }, throwsDatabaseClosed);
      expect(() async {
        await db.getVersion();
      }, throwsDatabaseClosed);
      expect(() async {
        await db.transaction((Transaction txn) async {});
      }, throwsDatabaseClosed);
      expect(() => db.batch().commit(), throwsDatabaseClosed);
    });

    test('should expose the closed state through the mixin api', () async {
      final dbMixin = db as SqfliteDatabaseMixin;
      expect(dbMixin.isClosed, isFalse);
      await db.close();
      expect(dbMixin.isClosed, isTrue);
      expect(dbMixin.checkNotClosed, throwsDatabaseClosed);
    });
  });

  group('原生 sqlite 异常', () {
    test('should wrap a syntax error into a DatabaseException', () async {
      engine.responders['query'] = (MethodCall call) {
        throw PlatformException(
            code: 'sqlite_error', message: 'near "FROMS": syntax error (code 1)');
      };
      try {
        await db.rawQuery('SELECT * FROMS test');
        fail('should fail');
      } on DatabaseException catch (e) {
        expect(e.isSyntaxError(), isTrue);
        expect(e.getResultCode(), 1);
        expect(e.toString(), contains('syntax error'));
      }
    });

    test('should wrap a unique constraint error', () async {
      engine.responders['insert'] = (MethodCall call) {
        throw PlatformException(
            code: 'sqlite_error',
            message: 'UNIQUE constraint failed: test.id (code 1555)');
      };
      try {
        await db.insert('test', <String, Object?>{'id': 1});
        fail('should fail');
      } on DatabaseException catch (e) {
        expect(e.isUniqueConstraintError('test.id'), isTrue);
        expect(e.isUniqueConstraintError('other.id'), isFalse);
        expect(e.getResultCode(), 1555);
      }
    });

    test('should keep non sqlite platform errors untouched', () async {
      engine.responders['query'] = (MethodCall call) {
        throw PlatformException(code: 'other_error', message: 'boom');
      };
      try {
        await db.rawQuery('SELECT 1');
        fail('should fail');
      } on PlatformException catch (e) {
        expect(e.code, 'other_error');
      }
    });

    test('should report batch operation errors when continuing on error',
        () async {
      final Batch batch = db.batch();
      batch.update('test', <String, Object?>{'name': 'a'});
      batch.update('test', <String, Object?>{'name': 'b'});
      final results = await batch.commit(continueOnError: true);
      expect(results, hasLength(2));
      final failure = results.first as DatabaseException;
      expect(failure.isUniqueConstraintError('test.id'), isTrue);
    });
  });

  group('只读数据库异常', () {
    test('should fail when writing a read-only database', () async {
      final readOnlyDb =
          await openReadOnlyDatabase('readonly_test.db');
      engine.responders['execute'] = (MethodCall call) {
        throw PlatformException(
            code: 'sqlite_error',
            message: 'attempt to write a readonly database (code 8)');
      };
      try {
        await readOnlyDb.execute('INSERT INTO test VALUES (1)');
        fail('should fail');
      } on DatabaseException catch (e) {
        expect(e.isReadOnlyError(), isTrue);
        expect(e.getResultCode(), 8);
      } finally {
        engine.responders.remove('execute');
        // Read-only databases are closed without a transaction.
        await readOnlyDb.close();
      }
    });

    test('should not start a transaction on a read-only database', () async {
      final readOnlyDb = await openReadOnlyDatabase('readonly_txn_test.db');
      await readOnlyDb.rawQuery('SELECT * FROM test');
      expect(engine.sqlsFor('execute'), isEmpty);
      await readOnlyDb.close();
    });
  });
}
