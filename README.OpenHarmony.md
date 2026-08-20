<p align="center">
  <h1 align="center">sqflite</h1>
</p>

This project is based on  [sqflite@2.2.8+3](https://pub.dev/packages/sqflite/versions/2.2.8+3).

## Introduction

SQLite plugin for [Flutter](https://flutter.io), providing embedded SQL database capabilities.
* Support transactions and batches
* Automatic version management during open
* Helpers for insert/query/update/delete queries

## Installation

Go to the project directory and add the following dependencies in pubspec.yaml:

```yaml
dependencies:
  sqflite:
    git:
      url: "https://gitcode.com/CPF-Flutter/flutter_sqflite.git"
      # ref: Please select the TAG to the TAG Version Mapping
      ref: 2.2.8-ohos-1.0.0   
      path: sqflite
```

Execute Command

```bash
flutter pub get
```

### TAG Version Mapping

| Flutter Framework Version | TAG               | Branch         |
|---------------------------|-------------------|----------------|
| 3.7                       | 2.2.8-ohos-1.0.0  | master         |
| 3.22                      | 2.2.8-ohos-1.0.0  | master         |
| 3.27                      | 2.4.2-ohos-1.0.0  | br_v2.4.2_ohos |
| 3.35                      | 2.4.2-ohos-1.0.0  | br_v2.4.2_ohos |

## Constraints

### Compatibility

This document is verified based on the following versions:

1. Flutter: 3.7.12-ohos-1.0.6; SDK: 5.0.0(12); IDE: DevEco Studio: 5.0.13.200; ROM: 5.1.0.120 SP3;
2. Flutter: oh-3.22.0-dev; SDK: 5.0.0(12); DevEco Studio: 6.1.1.280; ROM: 5.1.0.53 SP3;

### **Permission Requirements**

> The following permissions include the `system_basic` permission, but the default application permission is `normal`. Only the `normal` permission can be used. Therefore, the error **9568289** may be reported during the installation of the HAP package. For details, see [Document](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/bm-tool-V5#EN_TOPIC_0000001884757326__%E5%AE%89%E8%A3%85hap%E6%97%B6%E6%8F%90%E7%A4%BAcode9568289-error-install-failed-due-to-grant-request-permissions-failed) Change the application level to `system_basic`.

## Example

```dart
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

Future<void> runDemo() async {
  final String dbPath = p.join(await getDatabasesPath(), 'demo.db');
  final Database db = await openDatabase(
    dbPath,
    version: 1,
    onCreate: (Database db, int version) async {
      await db.execute(
        'CREATE TABLE user(id INTEGER PRIMARY KEY, name TEXT, age INTEGER)',
      );
    },
  );

  final int id = await db.insert('user', <String, Object?>{
    'name': 'Alice',
    'age': 18,
  });

  final List<Map<String, Object?>> rows = await db.query(
    'user',
    where: 'id = ?',
    whereArgs: <Object?>[id],
  );

  print('rows: $rows'); // [{id: 1, name: Alice, age: 18}]
  await db.close();
}
```

For more examples, see [sqflite/example](./sqflite/example)

## How to Use

Import `sqflite.dart`
```dart
import 'package:sqflite/sqflite.dart';
```

### Opening a database

A SQLite database is a file in the file system identified by a path. If relative, this path is relative to the path obtained by getDatabasesPath(), which is the default database directory on OpenHarmony.

```dart
var db = await openDatabase('my_db.db');
```

There is a basic migration mechanism to handle schema changes during opening.

Many applications use one database and would never need to close it (it will be closed when the application is terminated). If you want to release resources, you can close the database.

```dart
await db.close();
```

* See [more information on opening a database](https://github.com/tekartik/sqflite/blob/master/sqflite/doc/opening_db.md)
* Full [migration example](https://github.com/tekartik/sqflite/blob/master/sqflite/doc/migration_example.md)

### CRUD operations

In the following example, `db` is an open Database instance.

```dart
await db.insert('user', <String, Object?>{'name': 'Bob', 'age': 20});
final List<Map<String, Object?>> list = await db.query('user');
await db.update('user', <String, Object?>{'age': 21}, where: 'name = ?', whereArgs: <Object?>['Bob']);
await db.delete('user', where: 'name = ?', whereArgs: <Object?>['Bob']);
```

For placeholder parameters, it is recommended to consistently use `?` + `whereArgs`/`arguments` to avoid string concatenation.

For SQL details and common pitfalls, please see [sql.md](https://github.com/tekartik/sqflite/blob/master/sqflite/doc/sql.md).

### Transaction

```dart
await db.transaction((txn) async {
  await txn.insert('user', <String, Object?>{'name': 'Tom', 'age': 19});
  await txn.update(
    'user',
    <String, Object?>{'age': 20},
    where: 'name = ?',
    whereArgs: <Object?>['Tom'],
  );
});
```

Within a transaction, `txn` should be used to access the database; using `db` directly within a transaction callback may result in a deadlock.

### Batch 

```dart
final Batch batch = db.batch();
batch.insert('user', <String, Object?>{'name': 'Cathy', 'age': 22});
batch.update('user', <String, Object?>{'age': 23}, where: 'name = ?', whereArgs: <Object?>['Cathy']);
await batch.commit();
```

This can be used when writing large batches of data and not caring about each individual result:

```dart
await batch.commit(noResult: true);
```

To continue execution after failure, you can use:

```dart
await batch.commit(continueOnError: true);
```

### Explanation of Reading Results

The result list and its elements returned by `query`/`rawQuery` are read-only Map objects.

If you need to modify them in memory, please copy them first:

```dart
final List<Map<String, Object?>> rows = await db.query('user');
final Map<String, Object?> mutable = Map<String, Object?>.from(rows.first);
mutable['age'] = 30;
```

### Supported SQLite types

No validity check is done on values yet so please avoid non supported types. [https://www.sqlite.org/datatype3.html](https://www.sqlite.org/datatype3.html)

`DateTime` is not a supported SQLite type. It is recommended to store them as int (millisSinceEpoch) or string (iso8601)

`bool` is not a supported SQLite type. Use INTEGER and 0 and 1 values.

More information on supported types [here](https://github.com/tekartik/sqflite/blob/master/sqflite/doc/supported_types.md).


| Name | Description | Type | OpenHarmony Support |
| --- | --- | --- | --- |
| INTEGER | Store integer values | int | yes |
| REAL | Store floating-point values | num/double | yes |
| TEXT | Store string values | String | yes |
| BLOB | Storing binary values | Uint8List | yes |
| NULL | Store null values  | null | yes |

## API

> [!TIP] If the value of **OpenHarmony Platform Support** is **yes**, it means that the ohos platform supports this property; **no** means the opposite; **partially** means some capabilities of this property are supported. The usage method is the same on different platforms and the effect is the same as that of iOS or Android.

| Name                 | Type | Parameter Type                                                   | Return Value                  | OpenHarmony Platform Support | Description                                                                           |
|----------------------| --- |-------------------------------------------------------------------|-------------------------------| --- |---------------------------------------------------------------------------------------|
| openDatabase         | Function | String path, [OpenDatabaseOptions](#opendatabaseoptions)? options | Future<[Database](#database)> | yes | Open the database with the specified path, and you can configure the opening options. |
| openReadOnlyDatabase | Function | String path, {bool singleInstance = true}                         | Future<[Database](#database)> | yes | Open the database at the specified path in read-only mode.                            |
| getDatabasesPath     | Function | -                                                                 | Future\<String\>              | yes | Obtain the default storage path of the database.                                      |
| deleteDatabase       | Function | String path                                                       | Future\<void\>                | yes | Deletes the database for the specified path.                                          |
| databaseExists       | Function | String path                                                       | Future\<bool\>                | yes | Check whether the database for the specified path exists.                             |


#### Batch

| Name       | Type | Parameter Type                                          | Return Value         | OpenHarmony Platform Support | Description |
|------------| --- |----------------------------------------------------------|-----------------------|------------------| --- |
| get length | Function | -                                                        | int                   | yes              | Get the total number of queued operations. |
| apply      | Function | {bool? noResult, bool? continueOnError}                  | Future<List<Object?>> | yes              | Execute and apply batched operations; prefer [commit] for running a batch. |
| commit     | Function | {bool? exclusive, bool? noResult, bool? continueOnError} | Future<List<Object?>> | yes              | Commit and execute batched operations, returning each result item. |
| delete     | Function | String table, String? where, List<Object?>? whereArgs    | void                  | yes              | Queue a delete operation in the batch. |
| execute    | Function | String sql, List<Object?>? arguments                     | void                  | yes              | Queue execution of an arbitrary SQL statement in the batch. |
| insert     | Function | [InsertOption](#insertoption)                            | void                  | yes              | Queue an insert operation in the batch. |
| query      | Function | [QueryOption](#queryoption)                              | void                  | yes              | Queue a query operation in the batch. |
| rawDelete  | Function | String sql, List<Object?>? arguments                     | void                  | yes              | Queue a raw delete statement in the batch. |
| rawInsert  | Function | String sql, List<Object?>? arguments                     | void                  | yes              | Queue a raw insert statement in the batch. |
| rawQuery   | Function | String sql, List<Object?>? arguments                     | void                  | yes              | Queue a raw query statement in the batch. |
| rawUpdate  | Function | String sql, List<Object?>? arguments                     | void                  | yes              | Queue a raw update statement in the batch. |
| update     | Function | [UpdateOption](#updateoption)                            | void                  | yes              | Queue an update operation in the batch. |

#### Database
Inherited from [DatabaseExecutor](#databaseexecutortransaction), repeated methods will not be described again.

| Name               | Type            | Parameter Type                                                          | Return Value     | OpenHarmony Platform Support | Description |
|--------------------|-----------------|-----------------------------------------------------------------------------------------------|----------------| --- | --- |
| path               | Attribute              | -                                                                                             | String         | yes | Database path. |
| isOpen             | Attribute              | -                                                                                             | bool           | yes | Whether the database is open; returns false after calling `close()`. |
| close              | Function              | -                                                                                             | Future\<void\> | yes | Close the database. |
| transaction        | Function              | Future\<T\> Function([Transaction](#databaseexecutortransaction) txn) action, bool? exclusive | Future\<T\>    | yes | Entry point for transaction execution. |
| devInvokeMethod    | Function (Deprecated) | String method, [Object? arguments]                                                            | Future\<T\>    | yes | Dev/test method; intended for development only in source code (`@Deprecated('Dev only')`). |
| devInvokeSqlMethod | Function (Deprecated) | String method, String sql, [List<Object?>? arguments]                                         | Future\<T\>    | yes | Dev/test SQL helper; intended for development only (`@Deprecated('Dev only')`). |

#### DatabaseExecutor/Transaction

| Name           | Type | Parameter Type                                       | Return Value                        | OpenHarmony Platform Support | Description |
|----------------| --- |-------------------------------------------------------|-------------------------------------| --- | --- |
| batch          | Function | -                                                     | Batch                               | yes | Get a batch operation object. |
| delete         | Function | String table, String? where, List<Object?>? whereArgs | Future\<int\>                       | yes | Delete rows that match the condition. |
| execute        | Function | String sql, List<Object?>? arguments                  | Future\<void\>                      | yes | Execute an SQL statement. |
| getVersion     | Function | /                                                     | Future\<int\>                       | yes | Get the internal database version. |
| insert         | Function | [InsertOption](#insertoption)                         | Future\<int\>                       | yes | Execute insert SQL and returns the id of the last inserted row. |
| query          | Function | [QueryOption](#queryoption)                           | Future<List<Map<String, Object?>>>  | yes | Query and return a result-set list. |
| queryCursor    | Function | [QueryCursor](#querycursoroption)                     | Future<[QueryCursor](#querycursor)> | yes | Query and return a cursor object. |
| rawDelete      | Function | String sql, List<Object?>? arguments                  | Future\<int\>                       | yes | Directly execute SQL delete and return affected row count. |
| rawInsert      | Function | String sql, List<Object?>? arguments                  | Future\<int\>                       | yes | Executes a raw SQL INSERT query and returns the last inserted row ID. |
| rawQuery       | Function | String sql, List<Object?>? arguments                  | Future<List<Map<String, Object?>>>  | yes | Directly execute SQL query and return a result-set list. |
| rawQueryCursor | Function | String sql, List<Object?>? arguments, int? bufferSize | Future<[QueryCursor](#querycursor)> | yes | Execute a raw SQL query and return a cursor object. |
| rawUpdate      | Function | String sql, List<Object?>? arguments                  | Future\<int\>                       | yes | Directly execute SQL update and return affected row count. |
| setVersion     | Function | int version                                           | Future\<void\>                      | yes | Set the internal database version for open helpers and automatic version control. |
| update         | Function | [UpdateOption](#updateoption)                         | Future\<int\>                       | yes | Execute update SQL and return affected row count. |

#### DatabaseFactory

| Name             | Type     | Parameter Type                                                   | Return Value         | OpenHarmony Platform Support | Description |
|------------------|----------|-------------------------------------------------------------------|----------------------| --- | --- |
| openDatabase     | Function       | String path, [OpenDatabaseOptions](#opendatabaseoptions)? options | Future\<Database\>   | yes | Open the database with the specified path, and you can configure the opening options.  |
| getDatabasesPath | Function       | -                                                                 | Future\<String\>     | yes | Obtain the default storage path of the database.  |
| setDatabasesPath | Function       | String path                                                       | Future\<void\>       | yes | Set the default database storage path. |
| deleteDatabase   | Function       | String path                                                       | Future\<void\>       | yes | Deletes the database for the specified path.  |
| databaseExists   | Function | String path                                                       | Future\<bool\>       | yes | Check whether the database for the specified path exists. |

#### QueryCursor

| Name      | Type   | Parameter Type | Return Value           | OpenHarmony Platform Support | Description |
|-----------|------|---|----------------------| --- | --- |
| current   | Attribute   | - | Map<String, Object?> | yes | Data of the current row. |
| close     | Function   | - | Future\<void\>       | yes | Close the cursor manually. |
| moveNext  | Function   | - | Future\<bool\>       | yes | Move to the next row; when false is returned, the cursor closes automatically. |

#### DatabaseException

`DatabaseException` is an abstract class (implementing `Exception`) and sqflite's unified wrapper for native SQLite errors; the OpenHarmony platform uses the concrete implementation `SqfliteDatabaseException`. Any inner exception is thrown wrapped in a `DatabaseException`.

| Name                      | Type | Parameter Type   | Return Value | OpenHarmony Platform Support | Description |
|---------------------------| --- |---------------|-------| --- | --- |
| result                    | Attribute | -             | Object? | yes | Platform-specific native error result; content depends on the platform, used internally and for diagnostics. |
| getResultCode             | Function | -             | int?  | yes | Returns the SQLite result code; Android/FFI return extended codes, iOS returns normal codes, handle both. |
| isNoSuchTableError        | Function | [String? table] | bool  | yes | Whether it is a "no such table" error; an optional table name can be matched. |
| isDuplicateColumnError    | Function | [String? column] | bool  | yes | Whether it is a "duplicate column name" error; an optional column name can be matched. |
| isSyntaxError             | Function | -             | bool  | yes | Whether it is an SQL syntax error. |
| isOpenFailedError         | Function | -             | bool  | yes | Whether it is a database open-failed error (contains `open_failed`). |
| isDatabaseClosedError     | Function | -             | bool  | yes | Whether it is a database-closed error. |
| isReadOnlyError           | Function | -             | bool  | yes | Whether it is a read-only error (contains `readonly`). |
| isUniqueConstraintError   | Function | [String? field] | bool  | yes | Whether it is a UNIQUE constraint violation; an optional field can be matched. |
| isNotNullConstraintError  | Function | [String? field] | bool  | yes | Whether it is a NOT NULL constraint violation; an optional field can be matched. |

### Properties
#### OpenDatabaseOptions

| Name           | Parameter Type                      | Require | OpenHarmony Platform Support | Description                        |
|----------------|-------------------------------------|---------|--------------|---------------------------------------------------------|
| version        | int?                                | no      | yes          | Database version, must be a 32-bit integer greater than 0. |
| onConfigure    | [OnDatabaseConfigureFn](#callback-types)?     | no       | yes          | Database configuration callback, parameters: `Database db` |
| onCreate       | [OnDatabaseCreateFn](#callback-types)?        | no       | yes          | Callback triggered when the database is created for the first time, parameters: `Database db, int version` |
| onUpgrade      | [OnDatabaseVersionChangeFn](#callback-types)? | no       | yes          | Callback for database version upgrade, parameters: `Database db, int oldVersion, int newVersion` |
| onDowngrade    | [OnDatabaseVersionChangeFn](#callback-types)? | no       | yes          | Callback for database version downgrade, parameters: `Database db, int oldVersion, int newVersion` |
| onOpen         | [OnDatabaseOpenFn](#callback-types)?          | no       | yes          | Callback triggered after the database is successfully opened, parameters: `Database db` |
| readOnly       | bool?                               | no       | yes          | Whether to open the database in read-only mode. Default: `false` |
| singleInstance | bool?                               | no       | yes          | Whether to enforce the singleton pattern. Default: `true` |

#### InsertOption

| Name                | Parameter Type                      | Require  | OpenHarmony Platform Support | Description |
|-------------------|---------------------------|-----| --- | --- |
| table             | String                    | yes   | yes | Target table name for insertion. |
| values            | Map<String, Object?>      | yes   | yes | Column-to-value mapping to insert. |
| nullColumnHack    | String?                   | no   | yes | Optional column name used to insert NULL when `values` is empty. |
| conflictAlgorithm | [ConflictAlgorithm](#conflictalgorithm)? | no   | yes | Conflict resolution strategy (formerly `ConflictAlgorithm`). |

#### QueryOption

| Name        | Parameter Type           | Require | OpenHarmony Platform Support | Description |
|-----------|----------------| --- | --- | --- |
| table     | String         | yes | yes | Table name to query. |
| distinct  | bool?          | no | yes | Whether to return distinct rows only. |
| columns   | List<String>?  | no | yes | List of columns to return; defaults to all columns. |
| where     | String?        | no | yes | WHERE clause (without the `WHERE` keyword). |
| whereArgs | List<Object?>? | no | yes | Argument list for placeholders in the WHERE clause. |
| groupBy   | String?        | no | yes | GROUP BY clause (without the keyword). |
| having    | String?        | no | yes | HAVING clause (without the keyword). |
| orderBy   | String?        | no | yes | ORDER BY clause (without the keyword). |
| limit     | int?           | no | yes | Maximum number of rows to return. |
| offset    | int?           | no | yes | Row offset for the returned results. |

#### QueryCursorOption

| Name         | Parameter Type           | Require | OpenHarmony Platform Support | Description |
|------------|----------------| --- | --- | --- |
| table      | String         | yes | yes | Table name to query. |
| distinct   | bool?          | no | yes | Whether to return distinct rows only. |
| columns    | List<String>?  | no | yes | List of columns to return. |
| where      | String?        | no | yes | WHERE clause (without the keyword). |
| whereArgs  | List<Object?>? | no | yes | Argument list for placeholders in the WHERE clause. |
| groupBy    | String?        | no | yes | GROUP BY clause. |
| having     | String?        | no | yes | HAVING clause. |
| orderBy    | String?        | no | yes | ORDER BY clause. |
| limit      | int?           | no | yes | Maximum number of rows to return. |
| offset     | int?           | no | yes | Row offset for the returned results. |
| bufferSize | int?           | no | yes | Cursor buffer size, affecting low-level batch fetch behavior. |

#### UpdateOption

| Name                | Parameter Type                      | Require | OpenHarmony Platform Support | Description |
|-------------------|---------------------------| --- | --- | --- |
| table             | String                    | yes | yes | Target table name to update. |
| values            | Map<String, Object?>      | yes | yes | Column-to-value mapping. |
| where             | String?                   | no | yes | WHERE clause (without the keyword). |
| whereArgs         | List<Object?>?            | no | yes | Argument list for placeholders in the WHERE clause. |
| conflictAlgorithm | [ConflictAlgorithm](#conflictalgorithm)? | no | yes | Conflict resolution strategy. |

#### ConflictAlgorithm

| Name       | Parameter Type | OpenHarmony Platform Support | Description |
|------------| --- |---| --- |
| rollback   | Enum value | yes | Roll back the transaction and terminate when a conflict occurs. |
| abort      | Enum value | yes | Terminate the current statement when a conflict occurs. |
| fail       | Enum value | yes | Terminate the statement but keep prior changes when a conflict occurs. |
| ignore     | Enum value | yes | Ignore the current row and continue when a conflict occurs. |
| replace    | Enum value | yes | Replace the existing row when a conflict occurs. |

#### Callback Types

| Callback                    | Parameter Type                                                                            | OpenHarmony Platform Support | Description |
|---------------------------|--------------------------------------------------------------------------------------| --- | --- |
| OnDatabaseConfigureFn     | FutureOr\<void\> Function([Database](#database) db)                                  | yes | Params: `Database db`; Returns: `FutureOr<void>`; triggered after database open starts and before other callbacks. |
| OnDatabaseCreateFn        | FutureOr\<void\> Function([Database](#database) db, int version)                     | yes | Params: `Database db, int version`; Returns: `FutureOr<void>`; triggered when the database is created for the first time. |
| OnDatabaseVersionChangeFn | FutureOr\<void\> Function([Database](#database) db, int oldVersion, int newVersion); | yes | Params: `Database db, int oldVersion, int newVersion`; Returns: `FutureOr<void>`; triggered on database upgrade or downgrade. |
| OnDatabaseOpenFn          | FutureOr\<void\> Function([Database](#database) db)                                  | yes | Params: `Database db`; Returns: `FutureOr<void>`; triggered after the database is fully opened. |

## Known Issues

- [ ]  ohos  When query results contain excessively large datasets, serialization failures occur due to taskPool limitations, preventing normal data return. : [issue#75](https://gitcode.com/CPF-Flutter/flutter_sqflite/issues/75).

## Directory Structure
```
sqflite
├── packages/                   # Extension packages and tool examples (such as console test apps)
├── packages_web/               # Web-related implementations and tests
├── sqflite/                    # Main Flutter sqflite plugin module
│   └── android/ios             # Native implementations for Android/iOS platforms
│   └── doc/                    # Plugin usage docs and development notes
│   └── example/                # Example project
│   └── lib/                    # Dart API and core implementation
│   └── ohos/                   # OpenHarmony platform adaptation implementation
├── sqflite_common/             # Cross-platform common implementation
├── sqflite_common_ffi/         # FFI-related implementation and tests
├── sqflite_common_test/        # Shared test cases
├── sqflite_support/            # Support library and auxiliary test code
├── sqflite_test_app/           # Plugin integration test app
├── README.OpenHarmony_CN.md   # Chinese documentation
├── README.OpenHarmony.md      # English documentation
```

## How to Contribute

If you find any problem when using sqflite, submit an [Issue](https://gitcode.com/CPF-Flutter/flutter_sqflite/issues) or a [PR](https://gitcode.com/CPF-Flutter/flutter_sqflite/pulls).

## License

The repository is based on [BSD 2-Clause License](https://gitcode.com/CPF-Flutter/flutter_sqflite/blob/master/LICENSE).

