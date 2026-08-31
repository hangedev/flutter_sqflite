import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/src/batch.dart';
import 'package:sqflite/src/factory_impl.dart';
import 'package:sqflite/src/transaction.dart';

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

  group('Batch', () {
    test('should record operations and commit them in a transaction',
        () async {
      final Batch batch = db.batch();
      batch.execute('CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)');
      batch.insert('test', <String, Object?>{'name': 'a'});
      batch.rawInsert('INSERT INTO test (name) VALUES (?)', <Object?>['b']);
      batch.update('test', <String, Object?>{'name': 'c'});
      batch.rawUpdate('UPDATE test SET name = ?', <Object?>['d']);
      batch.delete('test', where: 'id = ?', whereArgs: <Object?>[1]);
      batch.rawDelete('DELETE FROM test WHERE id = ?', <Object?>[2]);
      batch.query('test', columns: <String>['name']);
      batch.rawQuery('SELECT name FROM test');
      expect(batch.length, 9);

      final results = await batch.commit();
      expect(results, hasLength(9));

      // The whole batch is wrapped in a transaction.
      expect(engine.sqlsFor('execute'),
          containsAllInOrder(<String>['BEGIN IMMEDIATE', 'COMMIT']));
      expect(engine.callsFor('batch'), hasLength(1));
    });

    test('should not return results when committing with noResult',
        () async {
      final Batch batch = db.batch();
      batch.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
      batch.insert('test', <String, Object?>{'name': 'a'});
      final results = await batch.commit(noResult: true);
      expect(results, isEmpty);
    });

    test('should report per operation errors when committing with '
        'continueOnError', () async {
      final Batch batch = db.batch();
      batch.update('test', <String, Object?>{'name': 'a'});
      final results = await batch.commit(continueOnError: true);
      expect(results, hasLength(1));
      expect(results.first, isA<DatabaseException>());
    });

    test('should apply the operations without starting a transaction',
        () async {
      final Batch batch = db.batch();
      batch.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
      batch.insert('test', <String, Object?>{'name': 'a'});
      final results = await batch.apply();
      expect(results, hasLength(2));
      // No BEGIN/COMMIT wrapping and no separate execute call: all the
      // operations travel in a single batch method call.
      expect(engine.sqlsFor('execute'), isEmpty);
      expect(engine.callsFor('batch'), hasLength(1));
    });

    test('should expose the recorded operations of the internal batch api',
        () async {
      final SqfliteBatch sqfliteBatch = db.batch() as SqfliteBatch;
      expect(sqfliteBatch.length, 0);
      sqfliteBatch.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
      sqfliteBatch.rawInsert('INSERT INTO test (name) VALUES (?)',
          <Object?>['a']);
      sqfliteBatch.rawUpdate('UPDATE test SET name = ?', <Object?>['b']);
      sqfliteBatch.rawDelete('DELETE FROM test', null);
      sqfliteBatch.rawQuery('SELECT * FROM test');
      expect(sqfliteBatch.length, 5);
      expect(sqfliteBatch.getOperationsParam(), hasLength(5));

      // The batch mixin helper methods build the proper statements.
      final SqfliteBatchMixin batchMixin = sqfliteBatch;
      batchMixin.insert('test', <String, Object?>{'name': 'c'});
      batchMixin.update('test', <String, Object?>{'name': 'd'},
          where: 'id = ?', whereArgs: <Object?>[1]);
      batchMixin.delete('test', where: 'id = ?', whereArgs: <Object?>[2]);
      batchMixin.query('test', columns: <String>['name']);
      expect(sqfliteBatch.length, 9);
      final operations = sqfliteBatch.getOperationsParam();
      expect(operations[5]['sql'], 'INSERT INTO test (name) VALUES (?)');
      expect(operations[6]['sql'], 'UPDATE test SET name = ? WHERE id = ?');
      expect(operations[7]['sql'], 'DELETE FROM test WHERE id = ?');
      expect(operations[8]['sql'], 'SELECT name FROM test');
    });

    test('should commit a database batch exclusively when requested',
        () async {
      final SqfliteDatabaseBatch databaseBatch = db.batch()
          as SqfliteDatabaseBatch;
      databaseBatch.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
      await databaseBatch.commit(exclusive: true);
      expect(engine.sqlsFor('execute').first, 'BEGIN EXCLUSIVE');
    });
  });

  group('Batch in a transaction', () {
    test('should apply the operations within the current transaction',
        () async {
      await db.transaction((Transaction txn) async {
        final SqfliteTransactionBatch txnBatch =
            txn.batch() as SqfliteTransactionBatch;
        txnBatch.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
        txnBatch.insert('test', <String, Object?>{'name': 'a'});
        final results = await txnBatch.apply();
        expect(results, hasLength(2));

        // Committing in a transaction is the same as applying: it re-sends
        // every recorded operation.
        txnBatch.execute('CREATE TABLE test2 (id INTEGER PRIMARY KEY)');
        final commitResults = await txnBatch.commit();
        expect(commitResults, hasLength(3));
      });
      // Only the outer transaction begin/end.
      expect(engine.sqlsFor('execute'),
          containsAllInOrder(<String>['BEGIN IMMEDIATE', 'COMMIT']));
      expect(engine.callsFor('batch'), hasLength(2));
    });

    test('should reject an exclusive commit within a transaction', () async {
      await db.transaction((Transaction txn) async {
        final SqfliteTransactionBatch txnBatch =
            txn.batch() as SqfliteTransactionBatch;
        txnBatch.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
        try {
          await txnBatch.commit(exclusive: true);
          fail('should fail');
        } on ArgumentError catch (_) {}
      });
    });
  });
}
