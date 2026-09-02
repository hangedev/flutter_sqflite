import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/src/batch.dart';
import 'package:sqflite/src/database.dart';
import 'package:sqflite/src/factory_impl.dart';
import 'package:sqflite/src/mixin.dart';
import 'package:sqflite/src/transaction.dart';

import 'mock_sqflite_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;

  late MockSqfliteEngine engine;

  setUp(() {
    engine = MockSqfliteEngine();
  });

  tearDown(() {
    engine.uninstall();
  });

  group('DatabaseExecutor crud facade', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(inMemoryDatabasePath);
    });

    tearDown(() async {
      if (db.isOpen) {
        await db.close();
      }
    });

    test('should send execute statements to the method channel', () async {
      await db.execute('CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)');
      expect(engine.sqlsFor('execute'),
          <String>['CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)']);
    });

    test('should send execute statements with binded arguments', () async {
      await db.execute('INSERT INTO test (name) VALUES (?)', <Object?>['a']);
      final call = engine.callsFor('execute').first;
      expect((call.arguments as Map)['arguments'], <Object?>['a']);
    });

    test('should return the inserted id when calling rawInsert', () async {
      final id = await db.rawInsert('INSERT INTO test (name) VALUES (?)',
          <Object?>['a']);
      expect(id, greaterThan(0));
      expect(engine.sqlsFor('insert'),
          <String>['INSERT INTO test (name) VALUES (?)']);
    });

    test('should build an insert statement when calling insert', () async {
      final id = await db
          .insert('test', <String, Object?>{'name': 'a', 'other': null});
      expect(id, greaterThan(0));
      expect(engine.sqlsFor('insert'),
          <String>['INSERT INTO test (name, other) VALUES (?, NULL)']);
    });

    test('should build an insert or replace statement when specifying a '
        'conflict algorithm', () async {
      await db.insert('test', <String, Object?>{'name': 'a'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      expect(engine.sqlsFor('insert').first,
          startsWith('INSERT OR REPLACE INTO test'));
    });

    test('should return 0 when an insert or ignore inserts no row', () async {
      // OHOS 对齐 Android changes() == 0 语义：IGNORE 冲突未插入时原生回 null，
      // Dart 层契约（sqflite_common txnRawInsert）将 null 转为 0
      engine.responders['insert'] = (call) => null;
      final id = await db.insert('test', <String, Object?>{'name': 'a'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      expect(id, 0);
      expect(engine.sqlsFor('insert').first,
          startsWith('INSERT OR IGNORE INTO test'));
    });

    test('should return the changed count when calling rawUpdate', () async {
      final count = await db
          .rawUpdate('UPDATE test SET name = ?', <Object?>['b']);
      expect(count, 1);
      expect(engine.sqlsFor('update'), <String>['UPDATE test SET name = ?']);
    });

    test('should build an update statement when calling update', () async {
      final count = await db.update('test', <String, Object?>{'name': 'b'},
          where: 'id = ?', whereArgs: <Object?>[1]);
      expect(count, 1);
      expect(engine.sqlsFor('update'),
          <String>['UPDATE test SET name = ? WHERE id = ?']);
      final call = engine.callsFor('update').first;
      expect((call.arguments as Map)['arguments'], <Object?>['b', 1]);
    });

    test('should return the deleted count when calling rawDelete', () async {
      final count = await db
          .rawDelete('DELETE FROM test WHERE id = ?', <Object?>[1]);
      expect(count, 1);
      expect(
          engine.sqlsFor('update'), <String>['DELETE FROM test WHERE id = ?']);
    });

    test('should build a delete statement when calling delete', () async {
      final count = await db
          .delete('test', where: 'id = ?', whereArgs: <Object?>[1]);
      expect(count, 1);
      expect(
          engine.sqlsFor('update'), <String>['DELETE FROM test WHERE id = ?']);
    });

    test('should return mapped rows when calling query', () async {
      final rows = await db.query('test',
          columns: <String>['id', 'name'],
          where: 'id > ?',
          whereArgs: <Object?>[0],
          orderBy: 'id');
      expect(rows, <Map<String, Object?>>[
        <String, Object?>{'id': 1, 'name': 'a'},
        <String, Object?>{'id': 2, 'name': 'b'},
        <String, Object?>{'id': 3, 'name': 'c'},
      ]);
    });

    test('should return mapped rows when calling rawQuery', () async {
      final rows =
          await db.rawQuery('SELECT id, name FROM test', <Object?>[]);
      expect(rows.first['name'], 'a');
      expect(rows.last['id'], 3);
    });

    test('should read and write the inner version with getVersion and '
        'setVersion', () async {
      expect(await db.getVersion(), 0);
      await db.setVersion(3);
      expect(await db.getVersion(), 3);
      expect(engine.sqlsFor('execute'), <String>['PRAGMA user_version = 3']);
    });

    test('should return itself when accessing the database property',
        () async {
      final SqfliteDatabase sqfliteDatabase = db as SqfliteDatabase;
      expect(sqfliteDatabase.database, same(sqfliteDatabase));
      expect(sqfliteDatabase.db, same(sqfliteDatabase));
    });
  });

  group('SqfliteDatabase internal api', () {
    late SqfliteDatabase sqfliteDatabase;
    late SqfliteDatabaseMixin dbMixin;
    late SqfliteDatabaseExecutor executor;
    late SqfliteDatabaseExecutorMixin executorMixin;

    setUp(() async {
      sqfliteDatabase =
          (await openDatabase(inMemoryDatabasePath)) as SqfliteDatabase;
      dbMixin = sqfliteDatabase as SqfliteDatabaseMixin;
      executor = sqfliteDatabase;
      executorMixin = sqfliteDatabase as SqfliteDatabaseExecutorMixin;
    });

    tearDown(() async {
      if (dbMixin.isOpen) {
        await sqfliteDatabase.close();
      }
    });

    test('should expose the executor database and transaction', () async {
      expect(executor.db, same(sqfliteDatabase));
      expect(executor.txn, isNull);
      expect(executorMixin.db, same(sqfliteDatabase));
      expect(dbMixin.db, same(sqfliteDatabase));
      expect(dbMixin.txn, isNull);
    });

    test('should report open state through isOpen and isClosed', () async {
      expect(dbMixin.isOpen, isTrue);
      expect(dbMixin.isClosed, isFalse);
      await sqfliteDatabase.close();
      expect(dbMixin.isOpen, isFalse);
      expect(dbMixin.isClosed, isTrue);
    });

    test('should route crud calls through the executor mixin', () async {
      await executorMixin.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
      await executorMixin.rawInsert('INSERT INTO test (name) VALUES (?)',
          <Object?>['a']);
      await executorMixin.insert('test', <String, Object?>{'name': 'b'});
      await executorMixin
          .rawUpdate('UPDATE test SET name = ?', <Object?>['c']);
      await executorMixin.update('test', <String, Object?>{'name': 'd'});
      await executorMixin
          .rawDelete('DELETE FROM test WHERE id = ?', <Object?>[1]);
      await executorMixin.delete('test');
      await executorMixin.query('test');
      await executorMixin.rawQuery('SELECT * FROM test');
      await executorMixin.rawQueryCursor('SELECT * FROM test', null);
      await executorMixin.queryCursor('test');
      expect(engine.sqlsFor('execute'), isNotEmpty);
      expect(engine.sqlsFor('insert'), hasLength(2));
      expect(engine.sqlsFor('update'), hasLength(4));
      expect(engine.callsFor('query'), hasLength(4));
    });

    test('should begin and end a transaction with the proper sql commands',
        () async {
      final SqfliteTransaction exclusiveTxn =
          await sqfliteDatabase.beginTransaction(exclusive: true);
      expect(engine.sqlsFor('execute'), <String>['BEGIN EXCLUSIVE']);
      exclusiveTxn.successful = true;
      await sqfliteDatabase.endTransaction(exclusiveTxn);
      expect(engine.sqlsFor('execute'),
          <String>['BEGIN EXCLUSIVE', 'COMMIT']);

      final SqfliteTransaction immediateTxn =
          await sqfliteDatabase.beginTransaction();
      expect(engine.sqlsFor('execute').last, 'BEGIN IMMEDIATE');
      immediateTxn.successful = false;
      await sqfliteDatabase.endTransaction(immediateTxn);
      expect(engine.sqlsFor('execute').last, 'ROLLBACK');
    });

    test('should create a new transaction object without sql command',
        () async {
      final SqfliteTransaction txn = dbMixin.newTransaction();
      expect(txn, isNotNull);
      expect(txn.db, same(sqfliteDatabase));
      expect(txn.txn, same(txn));
      // No begin sql was sent.
      expect(engine.sqlsFor('execute'), isEmpty);
    });

    test('should run raw commands within a given transaction', () async {
      final SqfliteTransaction txn = dbMixin.newTransaction();
      final insertedId = await sqfliteDatabase.txnRawInsert(
          txn, 'INSERT INTO test VALUES (?)', <Object?>[1]);
      final updatedCount = await sqfliteDatabase
          .txnRawUpdate(txn, 'UPDATE test SET id = 2', null);
      final deletedCount =
          await sqfliteDatabase.txnRawDelete(txn, 'DELETE FROM test', null);
      final rows = await sqfliteDatabase
          .txnRawQuery(txn, 'SELECT * FROM test', null);
      expect(insertedId, greaterThan(0));
      expect(updatedCount, 1);
      expect(deletedCount, 1);
      expect(rows, hasLength(3));
      expect(
          engine.sqlsFor('insert'), <String>['INSERT INTO test VALUES (?)']);
      expect(engine.sqlsFor('update'),
          <String>['UPDATE test SET id = 2', 'DELETE FROM test']);
    });

    test('should apply a batch within a given transaction', () async {
      final SqfliteBatch batch = dbMixin.batch() as SqfliteBatch;
      batch.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
      batch.rawInsert('INSERT INTO test (name) VALUES (?)', <Object?>['a']);
      final results = await sqfliteDatabase
          .txnApplyBatch(dbMixin.newTransaction(), batch);
      expect(results, hasLength(2));
      expect(engine.callsFor('batch'), hasLength(1));
    });

    test('should open and close the database through doOpen and doClose',
        () async {
      final options = OpenDatabaseOptions(
          version: 1, onCreate: (Database db, int version) async {});
      final SqfliteDatabase opened =
          await sqfliteDatabase.doOpen(options);
      expect(opened.id, isNotNull);
      expect(engine.sqlsFor('execute'),
          containsAll(<String>['BEGIN EXCLUSIVE', 'COMMIT']));
      await sqfliteDatabase.doClose();
      expect(dbMixin.isClosed, isTrue);
      // doClose should not send the closeDatabase method twice on re-open.
      final databaseId = await dbMixin.openDatabase();
      expect(databaseId, greaterThan(0));
    });

    test('should not throw when checking an open database is not closed',
        () async {
      sqfliteDatabase.checkNotClosed();
      expect(dbMixin.isOpen, isTrue);
    });

    test('should allow bypassing the internal lock when requested',
        () async {
      dbMixin.doNotUseSynchronized = true;
      await dbMixin.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
      await dbMixin.execute('CREATE TABLE test2 (id INTEGER PRIMARY KEY)');
      expect(engine.sqlsFor('execute'), hasLength(2));
      dbMixin.doNotUseSynchronized = false;
    });
  });
}
