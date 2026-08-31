import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/src/constant.dart';
import 'package:sqflite/src/sqflite_impl.dart' show channel;

/// In-memory engine emulating the native `com.tekartik.sqflite` method
/// channel protocol just enough to drive the whole Dart layer (factory,
/// database, executor, batch and cursor) in unit tests.
///
/// It records every [MethodCall] and answers with deterministic responses.
/// Specific responses can be overridden per method (or globally with
/// [errorResponder]) to simulate error scenarios.
class MockSqfliteEngine {
  MockSqfliteEngine() {
    install();
  }

  /// All method calls received so far.
  final List<MethodCall> calls = <MethodCall>[];

  /// Optional per-method response override.
  final Map<String, dynamic Function(MethodCall call)> responders =
      <String, dynamic Function(MethodCall call)>{};

  /// Optional error override, throwing for any call when set.
  Object Function(MethodCall call)? errorResponder;

  int _nextDatabaseId = 1;
  int _nextCursorId = 1;
  int _lastInsertId = 0;

  /// path -> PRAGMA user_version persisted value.
  final Map<String, int> pathVersions = <String, int>{};

  /// database id -> path (to resolve PRAGMA queries).
  final Map<int, String> databasePaths = <int, String>{};

  /// Paths reported as existing by `databaseExists`.
  final Set<String> existingDatabasePaths = <String>{};

  /// cursor id -> remaining pages (each page holds columns and rows).
  final Map<int, List<Map<String, Object?>>> cursorNextPages =
      <int, List<Map<String, Object?>>>{};

  /// Default rows answered to any non pragma select.
  List<List<Object?>> selectRows = <List<Object?>>[
    <Object?>[1, 'a'],
    <Object?>[2, 'b'],
    <Object?>[3, 'c'],
  ];

  /// Default columns answered to any non pragma select.
  List<String> selectColumns = <String>['id', 'name'];

  /// Install the mock method call handler on the sqflite channel.
  void install() {
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  /// Remove the mock handler.
  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }

  /// The recorded calls for a given method.
  List<MethodCall> callsFor(String method) =>
      calls.where((call) => call.method == method).toList(growable: false);

  /// The sql arguments of the calls for a given method.
  List<String> sqlsFor(String method) => callsFor(method)
      .map((call) => (call.arguments as Map?)?[paramSql] as String?)
      .whereType<String>()
      .toList(growable: false);

  Future<dynamic> handler(MethodCall call) async {
    calls.add(call);
    if (errorResponder != null) {
      throw errorResponder!(call);
    }
    final override = responders[call.method];
    if (override != null) {
      return override(call);
    }
    return defaultResponse(call);
  }

  Map<String, Object?> _columnsRows(
      List<String> columns, List<List<Object?>> rows) {
    return <String, Object?>{
      'columns': List<String>.from(columns),
      'rows': List<List<Object?>>.from(rows),
    };
  }

  /// Standard deterministic answer for each protocol method.
  dynamic defaultResponse(MethodCall call) {
    final Map arguments =
        call.arguments is Map ? call.arguments as Map : const <String, Object?>{};
    final databaseId = arguments[paramId] as int?;
    switch (call.method) {
      case methodOpenDatabase:
        final path = arguments[paramPath] as String;
        final id = _nextDatabaseId++;
        databasePaths[id] = path;
        pathVersions.putIfAbsent(path, () => 0);
        return <String, Object?>{
          paramId: id,
          paramRecoveredInTransaction: false,
        };
      case methodCloseDatabase:
        return null;
      case methodExecute:
        _tryApplyPragma(databaseId, arguments[paramSql] as String?);
        return null;
      case methodInsert:
        return ++_lastInsertId;
      case methodUpdate:
        return 1;
      case methodQuery:
        final sql = arguments[paramSql] as String?;
        if (sql == 'PRAGMA user_version') {
          final path = databasePaths[databaseId];
          return _columnsRows(<String>['user_version'], <List<Object?>>[
            <Object?>[pathVersions[path] ?? 0],
          ]);
        }
        if (arguments[paramCursorPageSize] != null) {
          final cursorId = _nextCursorId++;
          // First page holds the first two rows, next pages one row each.
          cursorNextPages[cursorId] = <Map<String, Object?>>[
            _columnsRows(selectColumns, <List<Object?>>[selectRows[2]]),
          ];
          return <String, Object?>{paramCursorId: cursorId}
            ..addAll(_columnsRows(selectColumns, selectRows.sublist(0, 2)));
        }
        return _columnsRows(selectColumns, selectRows);
      case methodQueryCursorNext:
        final cursorId = arguments[paramCursorId] as int;
        if (arguments[paramCursorCancel] == true) {
          cursorNextPages.remove(cursorId);
          return null;
        }
        final pages =
            cursorNextPages[cursorId] ?? const <Map<String, Object?>>[];
        if (pages.isEmpty) {
          return <String, Object?>{paramCursorId: null}
            ..addAll(_columnsRows(<String>[], <List<Object?>>[]));
        }
        final page = pages.removeAt(0);
        return <String, Object?>{paramCursorId: pages.isEmpty ? null : cursorId}
          ..addAll(page);
      case methodBatch:
        final operations =
            arguments[paramOperations] as List<dynamic>? ?? const <dynamic>[];
        if (arguments[paramNoResult] == true) {
          return null;
        }
        return operations.map((dynamic operation) {
          final map = operation as Map;
          final method = map[paramMethod] as String?;
          if (method == methodInsert) {
            return <String, Object?>{'result': ++_lastInsertId};
          } else if (method == methodQuery) {
            return <String, Object?>{
              'result': _columnsRows(selectColumns, selectRows),
            };
          } else if (arguments[paramContinueOnError] == true) {
            // Simulate a failing operation when continueOnError is set.
            return <String, Object?>{
              'error': <String, Object?>{
                'message': 'UNIQUE constraint failed: test.id',
                'data': <String, Object?>{'sql': map[paramSql]},
              },
            };
          }
          return <String, Object?>{'result': 1};
        }).toList();
      case methodGetDatabasesPath:
        return 'mock_databases_path';
      case methodDatabaseExists:
        return existingDatabasePaths.contains(arguments[paramPath]);
      case methodDeleteDatabase:
        existingDatabasePaths.remove(arguments[paramPath]);
        pathVersions.remove(arguments[paramPath]);
        return null;
      case methodDebug:
        return <String, Object?>{
          'databases': <String, Object?>{
            '1': <String, Object?>{
              'path': 'debug_path.db',
              'singleInstance': true,
              'logLevel': 1,
            },
          },
          'logLevel': 1,
        };
      case methodOptions:
      case 'debugMode':
        return null;
    }
    return null;
  }

  void _tryApplyPragma(int? databaseId, String? sql) {
    if (databaseId == null || sql == null) {
      return;
    }
    if (sql.startsWith('PRAGMA user_version = ')) {
      final version = int.tryParse(sql.split(' ').last);
      final path = databasePaths[databaseId];
      if (version != null && path != null) {
        pathVersions[path] = version;
      }
    }
  }
}
