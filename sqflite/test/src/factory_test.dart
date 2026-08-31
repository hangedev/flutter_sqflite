import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/src/database.dart'
    show SqfliteDatabase, SqfliteDatabaseOpenHelper;
import 'package:sqflite/src/factory_impl.dart';
import 'package:sqflite_common/sqflite_dev.dart';
import 'package:sqflite_common/src/factory.dart' show SqfliteDatabaseFactory;
import 'package:sqflite_common/src/factory_mixin.dart'
    show
        SqfliteDatabaseDebugInfo,
        SqfliteDatabaseFactoryMixin,
        SqfliteDebugInfo;
import 'package:sqflite_common/src/internals.dart' show DatabaseInternalsExt;
import 'package:sqflite_common/src/platform/platform_io.dart' show platform;

import 'mock_sqflite_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;

  late MockSqfliteEngine engine;
  final SqfliteDatabaseFactory factory =
      databaseFactorySqflitePlugin as SqfliteDatabaseFactory;

  setUp(() {
    engine = MockSqfliteEngine();
  });

  tearDown(() {
    engine.uninstall();
  });

  group('DatabaseFactory', () {
    test('should return the mocked databases path', () async {
      final String path = await databaseFactory.getDatabasesPath();
      expect(path, 'mock_databases_path');
    });

    test('should override the databases path with setDatabasesPath',
        () async {
      await databaseFactory.setDatabasesPath('custom_databases_path');
      expect(await databaseFactory.getDatabasesPath(), 'custom_databases_path');
      // Restore the default behavior for the other tests.
      (databaseFactory as SqfliteDatabaseFactoryMixin)
          .setDatabasesPathOrNull(null);
      expect(await databaseFactory.getDatabasesPath(), 'mock_databases_path');
    });

    test('should open and close a database through the factory', () async {
      final Database db =
          await databaseFactory.openDatabase('factory_open_test.db');
      expect(db.isOpen, isTrue);
      await db.close();
      expect(db.isOpen, isFalse);
    });

    test('should report database existence from the engine', () async {
      final Database db =
          await databaseFactory.openDatabase('factory_exists_test.db');
      final String fixedPath =
          (engine.callsFor('openDatabase').last.arguments as Map)['path']
              as String;
      await db.close();

      expect(await databaseFactory.databaseExists(fixedPath), isFalse);
      engine.existingDatabasePaths.add(fixedPath);
      expect(await databaseFactory.databaseExists(fixedPath), isTrue);
    });

    test('should delete a database through the factory', () async {
      final Database db =
          await databaseFactory.openDatabase('factory_delete_test.db');
      final String fixedPath =
          (engine.callsFor('openDatabase').last.arguments as Map)['path']
              as String;
      await db.close();

      engine.existingDatabasePaths.add(fixedPath);
      await databaseFactory.deleteDatabase(fixedPath);
      expect(engine.sqlsFor('deleteDatabase'), isEmpty);
      expect(engine.callsFor('deleteDatabase'), hasLength(1));
      expect(engine.existingDatabasePaths, isNot(contains(fixedPath)));
    });
  });

  group('SqfliteDatabaseFactory internal api', () {
    test('should create database objects and manage open helpers', () {
      final helper = SqfliteDatabaseOpenHelper(
          factory, 'helper_test.db', OpenDatabaseOptions());
      final SqfliteDatabase db = factory.newDatabase(helper, 'helper_test.db');
      expect(db.path, 'helper_test.db');

      final mixin = factory as SqfliteDatabaseFactoryMixin;
      mixin.databaseOpenHelpers['helper_test.db'] = helper;
      expect(mixin.databaseOpenHelpers, contains('helper_test.db'));
      factory.removeDatabaseOpenHelper('helper_test.db');
      expect(mixin.databaseOpenHelpers, isEmpty);
    });

    test('should close a single instance database and forget its helper',
        () async {
      final Database db = await factory
          .openDatabase('factory_close_test.db', options: OpenDatabaseOptions());
      expect(
          (factory as SqfliteDatabaseFactoryMixin).databaseOpenHelpers.length, 1);
      await factory.closeDatabase(db as SqfliteDatabase);
      expect(db.isOpen, isFalse);
      expect((factory as SqfliteDatabaseFactoryMixin).databaseOpenHelpers,
          isEmpty);
    });

    test('should describe itself in toString', () {
      expect(factory.toString(), 'SqfliteDatabaseFactory(sqflite)');
    });
  });

  group('SqfliteDatabaseOpenHelper', () {
    test('should open once and expose the opened database', () async {
      final helper = SqfliteDatabaseOpenHelper(factory, inMemoryDatabasePath,
          OpenDatabaseOptions(version: 1));
      expect(helper.isOpen, isFalse);
      expect(helper.sqfliteDatabase, isNull);

      final SqfliteDatabase db = await helper.openDatabase();
      expect(helper.isOpen, isTrue);
      expect(helper.sqfliteDatabase, same(db));
      // A second open returns the same instance.
      expect(await helper.openDatabase(), same(db));

      await helper.closeDatabase(db);
      expect(helper.isOpen, isFalse);
      expect(helper.sqfliteDatabase, isNull);
      // Closing twice is a no-op.
      await helper.closeDatabase(db);
    });
  });

  group('debug and dev options', () {
    test('should read the debug info from the engine', () async {
      final SqfliteDebugInfo info =
          await (factory as SqfliteDatabaseFactoryMixin).getDebugInfo();
      expect(info.logLevel, 1);
      expect(info.databases, isNotNull);
      final debugDb = info.databases!['1']!;
      expect(debugDb.path, 'debug_path.db');
      expect(debugDb.singleInstance, isTrue);
      expect(debugDb.logLevel, 1);
    });

    test('should deserialize a database debug info from a map', () {
      final dbInfo = SqfliteDatabaseDebugInfo();
      dbInfo.fromMap(<dynamic, dynamic>{
        'path': 'some_path.db',
        'singleInstance': false,
        'logLevel': 2,
      });
      expect(dbInfo.path, 'some_path.db');
      expect(dbInfo.singleInstance, isFalse);
      expect(dbInfo.logLevel, 2);
      expect(dbInfo.toString(), contains('some_path.db'));
    });

    test('should send dev options to the engine', () async {
      // ignore: deprecated_member_use
      await factory.setLogLevel(1);
      expect(engine.callsFor('options'), hasLength(1));

      final options = SqfliteOptions();
      // ignore: deprecated_member_use
      options.logLevel = 1;
      // ignore: deprecated_member_use
      options.queryAsMapList = true;
      // ignore: deprecated_member_use
      options.androidThreadPriority = 4;
      // ignore: deprecated_member_use
      options.androidThreadCount = 2;
      expect(options.toMap(), <String, Object?>{
        'queryAsMapList': true,
        'androidThreadPriority': 4,
        'androidThreadCount': 2,
        'logLevel': 1,
      });

      final other = SqfliteOptions();
      // ignore: deprecated_member_use
      other.fromMap(<String, Object?>{
        'queryAsMapList': true,
        'androidThreadPriority': 1,
        'androidThreadCount': 3,
        'logLevel': 2,
      });
      expect(other.logLevel, 2);
      expect(other.queryAsMapList, isTrue);
      expect(other.androidThreadPriority, 1);
      expect(other.androidThreadCount, 3);

      // ignore: deprecated_member_use
      await factory.setOptions(other);
      expect(engine.callsFor('options'), hasLength(2));
    });

    test('should expose the sqflite dev statics', () async {
      // ignore: deprecated_member_use
      expect(await Sqflite.getDebugModeOn(), isFalse);
      // ignore: deprecated_member_use
      await Sqflite.devSetOptions(SqfliteOptions(logLevel: 1));
      expect(engine.callsFor('options'), hasLength(1));
      // ignore: deprecated_member_use
      await Sqflite.devInvokeMethod('debugMode', true);
      expect(engine.callsFor('debugMode'), hasLength(1));
    });
  });

  group('DatabaseInternalsExt', () {
    test('should expose the internal database id', () async {
      final Database db = await openDatabase(inMemoryDatabasePath);
      expect(db.databaseId, greaterThan(0));
      await db.close();
    });
  });

  group('Platform', () {
    test('should report the host platform properties', () {
      expect(platform.isWeb, isFalse);
      expect(platform.isWindows, isTrue);
      expect(platform.isAndroid, isFalse);
      expect(platform.isIOS, isFalse);
      expect(platform.isLinux, isFalse);
      expect(platform.isMacOS, isFalse);
    });
  });

  group('database migration', () {
    tearDown(() async {
      await databaseFactory.deleteDatabase('migration_test.db');
    });

    test('should call onCreate when the database is new', () async {
      var createdCount = 0;
      var configuredCount = 0;
      var openedCount = 0;
      final db = await openDatabase('migration_test.db',
          version: 1,
          onConfigure: (Database db) => configuredCount++,
          onCreate: (Database db, int version) async {
            createdCount++;
            expect(version, 1);
          },
          onOpen: (Database db) => openedCount++);
      expect(createdCount, 1);
      expect(configuredCount, 1);
      expect(openedCount, 1);
      expect(await db.getVersion(), 1);
      await db.close();

      // Reopening at the same version does not call onCreate again.
      final reopened = await openDatabase('migration_test.db',
          version: 1,
          onConfigure: (Database db) => configuredCount++,
          onCreate: (Database db, int version) => createdCount++);
      expect(createdCount, 1);
      expect(configuredCount, 2);
      expect(await reopened.getVersion(), 1);
      await reopened.close();
    });

    test('should call onUpgrade when the version increases', () async {
      final first = await openDatabase('migration_test.db',
          version: 1,
          onCreate: (Database db, int version) async {});
      await first.close();

      var upgradedFrom = -1;
      var upgradedTo = -1;
      final second = await openDatabase('migration_test.db',
          version: 2,
          onUpgrade: (Database db, int oldVersion, int newVersion) async {
            upgradedFrom = oldVersion;
            upgradedTo = newVersion;
          });
      expect(upgradedFrom, 1);
      expect(upgradedTo, 2);
      expect(await second.getVersion(), 2);
      await second.close();
    });

    test('should call onDowngrade when the version decreases', () async {
      final first = await openDatabase('migration_test.db',
          version: 2,
          onCreate: (Database db, int version) async {});
      await first.close();

      var downgradedFrom = -1;
      var downgradedTo = -1;
      final second = await openDatabase('migration_test.db',
          version: 1,
          onDowngrade: (Database db, int oldVersion, int newVersion) async {
            downgradedFrom = oldVersion;
            downgradedTo = newVersion;
          });
      expect(downgradedFrom, 2);
      expect(downgradedTo, 1);
      expect(await second.getVersion(), 1);
      await second.close();
    });

    test('should fail on a downgrade when using the version change error '
        'handler', () async {
      final first = await openDatabase('migration_test.db',
          version: 2,
          onCreate: (Database db, int version) async {});
      await first.close();

      try {
        await openDatabase('migration_test.db',
            version: 1, onDowngrade: onDatabaseVersionChangeError);
        fail('should fail');
      } on ArgumentError catch (e) {
        expect(e.toString(), contains("can't change version from 2 to 1"));
      }
    });

    test('should delete and recreate the database on a downgrade when using '
        'onDatabaseDowngradeDelete', () async {
      final first = await openDatabase('migration_test.db',
          version: 2,
          onCreate: (Database db, int version) async {});
      await first.close();

      var createdCount = 0;
      final second = await openDatabase('migration_test.db',
          version: 1,
          onDowngrade: onDatabaseDowngradeDelete,
          onCreate: (Database db, int version) => createdCount++);
      expect(createdCount, 1);
      expect(await second.getVersion(), 1);
      await second.close();
    });
  });
}
