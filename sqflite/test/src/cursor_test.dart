import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/src/factory_impl.dart';
import 'package:sqflite_common/src/collection_utils.dart';
import 'package:sqflite_common/src/cursor.dart';

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

  group('QueryCursor', () {
    test('should iterate over all rows across pages with a small buffer size',
        () async {
      final cursor = await db.rawQueryCursor(
          'SELECT id, name FROM test', <Object?>[], bufferSize: 2);
      final names = <String>[];
      while (await cursor.moveNext()) {
        names.add(cursor.current['name']! as String);
      }
      expect(names, <String>['a', 'b', 'c']);
      // Two pages: 2 rows then 1 row.
      expect(engine.callsFor('queryCursorNext'), hasLength(1));
    });

    test('should iterate over table rows using queryCursor', () async {
      final cursor = await db.queryCursor('test',
          columns: <String>['id', 'name'], bufferSize: 2);
      final ids = <Object?>[];
      while (await cursor.moveNext()) {
        ids.add(cursor.current['id']);
      }
      expect(ids, <Object?>[1, 2, 3]);
    });

    test('should cancel the native cursor when closed before the end',
        () async {
      final cursor = await db.rawQueryCursor('SELECT * FROM test', null, bufferSize: 2);
      expect(await cursor.moveNext(), isTrue);
      await cursor.close();
      // Moving next on a closed cursor simply returns false.
      expect(await cursor.moveNext(), isFalse);

      final cancelCalls = engine.callsFor('queryCursorNext');
      expect(cancelCalls, hasLength(1));
      expect((cancelCalls.first.arguments as Map)['cancel'], isTrue);
    });

    test('should expose the cursor internal state', () async {
      final QueryCursor queryCursor =
          await db.rawQueryCursor('SELECT * FROM test', null, bufferSize: 2);
      final SqfliteQueryCursor cursor = queryCursor as SqfliteQueryCursor;
      expect(cursor.closed, isFalse);
      expect(cursor.cursorId, isNotNull);
      expect(cursor.txn, isNull);
      expect(cursor.currentIndex, -1);
      // The first page was loaded eagerly.
      expect(cursor.resultList, hasLength(2));
      cursor.currentIndex = 0;
      expect(cursor.current['name'], isNotNull);
      await cursor.close();
      expect(cursor.closed, isTrue);
    });
  });

  group('QueryResultSet and QueryRow', () {
    test('should expose rows as maps and column names', () {
      final resultSet = QueryResultSet(<String>['id', 'name'], <List<Object?>>[
        <Object?>[1, 'a'],
        <Object?>[2, 'b'],
      ]);
      expect(resultSet.keys, <String>['id', 'name']);
      expect(resultSet, hasLength(2));
      expect(resultSet.first, <String, Object?>{'id': 1, 'name': 'a'});
      expect(resultSet.last['name'], 'b');
      expect(resultSet.columnIndex('name'), 1);
      expect(resultSet.columnIndex('missing'), isNull);

      final QueryRow row = QueryRow(resultSet, <dynamic>[2, 'b']);
      expect(row.queryResultSet, same(resultSet));
      expect(row.row, <dynamic>[2, 'b']);
      expect(row['id'], 2);
      expect(row['missing'], isNull);
      expect(row.keys, <String>['id', 'name']);
      expect(row.values, <dynamic>[2, 'b']);
      expect(row.length, 2);
    });

    test('should throw when modifying an immutable row or result set', () {
      final resultSet = QueryResultSet(<String>['id'], <List<Object?>>[
        <Object?>[1],
      ]);
      final row = QueryRow(resultSet, <dynamic>[1]);
      expect(() => row['id'] = 2, throwsUnsupportedError);
      expect(() => row.remove('id'), throwsUnsupportedError);
      expect(() => row.clear(), throwsUnsupportedError);
      expect(() => resultSet[0] = <String, Object?>{'id': 2},
          throwsUnsupportedError);
      expect(() => resultSet.length = 2, throwsUnsupportedError);
    });

    test('should keep the last value when column names are duplicated', () {
      final resultSet = QueryResultSet(<String>['id', 'id'], <List<Object?>>[
        <Object?>[1, 2],
      ]);
      expect(resultSet.keys, <String>['id']);
      expect(resultSet.first, <String, Object?>{'id': 2});
    });

    test('should expose the raw list of PluginList helpers', () {
      final rows = Rows.from(<dynamic>[
        <String, Object?>{'id': 1},
        <String, Object?>{'id': 2},
      ]);
      expect(rows.rawList, hasLength(2));
      expect(rows.rawElementAt(1), <String, Object?>{'id': 2});
      expect(rows, hasLength(2));
      expect(rows[0]['id'], 1);
      expect(() => rows[0] = <String, Object?>{'id': 3},
          throwsUnsupportedError);
      expect(() => rows.add(<String, Object?>{'id': 3}), throwsUnsupportedError);
      expect(() => rows.length = 3, throwsUnsupportedError);
    });
  });
}
