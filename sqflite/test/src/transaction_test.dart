import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/src/batch.dart';
import 'package:sqflite/src/constant.dart';
import 'package:sqflite/src/factory_impl.dart';
import 'package:sqflite/src/mixin.dart';
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

  group('Transaction', () {
    test('should wrap the action between BEGIN IMMEDIATE and COMMIT',
        () async {
      final String? seenTxnClass = await db.transaction<String?>(
          (Transaction txn) async {
        await txn.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
        await txn.insert('test', <String, Object?>{'name': 'a'});
        return txn.runtimeType.toString();
      });
      expect(seenTxnClass, 'SqfliteTransaction');
      expect(engine.sqlsFor('execute'),
          containsAllInOrder(<String>['BEGIN IMMEDIATE', 'COMMIT']));
      // Insert and execute were sent inside the transaction.
      expect(engine.sqlsFor('execute'),
          contains('CREATE TABLE test (id INTEGER PRIMARY KEY)'));
      expect(engine.sqlsFor('insert'), hasLength(1));
    });

    test('should rollback when the action throws', () async {
      try {
        await db.transaction((Transaction txn) async {
          await txn.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
          throw StateError('action failed');
        });
        fail('should fail');
      } on StateError catch (e) {
        expect(e.message, 'action failed');
      }
      expect(engine.sqlsFor('execute').last, 'ROLLBACK');
    });

    test('should begin an exclusive transaction when requested', () async {
      await db.transaction((Transaction txn) async {
        await txn.rawQuery('SELECT * FROM test');
      }, exclusive: true);
      expect(engine.sqlsFor('execute'),
          containsAllInOrder(<String>['BEGIN EXCLUSIVE', 'COMMIT']));
    });

    test('should expose the transaction object inside the action', () async {
      await db.transaction((Transaction txn) async {
        final SqfliteTransaction sqfliteTxn = txn as SqfliteTransaction;
        expect(sqfliteTxn.db, same(db));
        expect(sqfliteTxn.database, same(db));
        expect(sqfliteTxn.txn, same(sqfliteTxn));
        expect(sqfliteTxn.transactionId, isNull);
        expect(sqfliteTxn.successful, isNull);
        expect(sqfliteTxn.batch(), isA<SqfliteTransactionBatch>());
      });
    });

    test('should mark transaction boundaries in the execute arguments',
        () async {
      await db.transaction((Transaction txn) async {
        await txn.execute('CREATE TABLE test (id INTEGER PRIMARY KEY)');
      });
      final executes = engine.callsFor('execute');
      expect(executes, hasLength(3));
      // BEGIN reports entering a transaction, COMMIT leaving it.
      expect((executes.first.arguments as Map)['inTransaction'], isTrue);
      expect(
          (executes[1].arguments as Map).containsKey('inTransaction'), isFalse);
      expect((executes.last.arguments as Map)['inTransaction'], isFalse);
    });
  });

  group('SqfliteTransactionParam', () {
    test('should hold an optional native transaction id', () {
      final SqfliteTransactionParam param = SqfliteTransactionParam(42);
      expect(param.transactionId, 42);
      expect(SqfliteTransactionParam(null).transactionId, isNull);
    });

    test('should build a forced transaction with the force id', () {
      final dbMixin = db as SqfliteDatabaseMixin;
      final SqfliteTransaction forced = getForcedSqfliteTransaction(dbMixin);
      expect(forced.transactionId, paramTransactionIdValueForce);
      expect(forced.db, same(db));
    });
  });
}
