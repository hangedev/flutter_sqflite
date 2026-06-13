import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite_common/sqflite.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/constant.dart'
    show
        methodOpenDatabase,
        paramId,
        paramPath,
        paramRecovered,
        paramRecoveredInTransaction,
        paramSingleInstance;
// ignore: implementation_imports
import 'package:sqflite_common/src/database_mixin.dart'
    show SqfliteDatabaseMixin;
// ignore: implementation_imports
import 'package:sqflite_common/src/factory_mixin.dart'
    show SqfliteDatabaseFactoryMixin;
// ignore: implementation_imports
import 'package:sqflite_common/src/internals.dart';
import 'package:sqflite_common/utils/utils.dart';

class SingleInstanceRecoveryPage extends StatefulWidget {
  const SingleInstanceRecoveryPage({super.key});

  @override
  State<SingleInstanceRecoveryPage> createState() =>
      _SingleInstanceRecoveryPageState();
}

class _SingleInstanceRecoveryPageState
    extends State<SingleInstanceRecoveryPage> {
  final List<String> _logs = <String>[];
  String? _runningAction;

  Future<String> _dbPath(String name) async {
    final databasesPath = await databaseFactory.getDatabasesPath();
    return join(databasesPath, name);
  }

  void _appendLog(String message) {
    final now = DateTime.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    final line = '[$timestamp] $message';
    debugPrint(line);
    if (!mounted) {
      return;
    }
    setState(() {
      _logs.add(line);
    });
  }

  Future<void> _safeDelete(String path) async {
    try {
      await databaseFactory.deleteDatabase(path);
    } catch (e) {
      _appendLog('删除数据库失败: $e');
    }
  }

  Future<void> _safeClose(Database? db, String name) async {
    if (db == null) {
      return;
    }
    try {
      await db.close();
    } catch (e) {
      _appendLog('$name 关闭失败: $e');
    }
  }

  Future<Database> _openSingleInstanceDatabase(String path) {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: true,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS Demo('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'value TEXT NOT NULL'
            ')',
          );
        },
      ),
    );
  }

  void _removeOpenHelper(String path) {
    final factory = databaseFactory as SqfliteDatabaseFactoryMixin;
    factory.databaseOpenHelpers.remove(path);
  }

  Future<Map<Object?, Object?>?> _invokeNativeOpen(String path) async {
    return await databaseFactory.internalsInvokeMethod<Map<Object?, Object?>>(
      methodOpenDatabase,
      <String, Object?>{
        paramPath: path,
        paramSingleInstance: true,
      },
    );
  }

  Future<void> _runScenario(
    String actionKey,
    String title,
    Future<void> Function() action,
  ) async {
    if (_runningAction != null) {
      return;
    }
    setState(() {
      _runningAction = actionKey;
      _logs.clear();
    });
    _appendLog('=== $title ===');
    try {
      await action();
      _appendLog('=== 执行完成 ===');
    } catch (e, st) {
      _appendLog('场景执行失败: $e');
      _appendLog(st.toString());
    } finally {
      if (mounted) {
        setState(() {
          _runningAction = null;
        });
      }
    }
  }

  Widget _buildActionButton({
    required String actionKey,
    required String label,
    required VoidCallback onPressed,
  }) {
    final isRunning = _runningAction == actionKey;
    return ElevatedButton(
      onPressed: isRunning ? null : onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isRunning) ...<Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          Text(label),
        ],
      ),
    );
  }

  Future<void> _runRecoveredScenario() async {
    final path = await _dbPath('ohos_single_instance_recovered_demo.db');
    Database? db1;
    Database? db2;
    // 说明: 先删除旧数据库，确保本次验证从干净状态开始，避免历史数据干扰结果
    await _safeDelete(path);
    try {
      db1 = await _openSingleInstanceDatabase(path);
      final id1 = (db1 as SqfliteDatabaseMixin).id;
      _appendLog('首次打开的 native id=$id1');

      _removeOpenHelper(db1.path);

      final nativeOpenResult = await _invokeNativeOpen(path);
      _appendLog(
        '原生 openDatabase 返回: '
        'id=${nativeOpenResult?[paramId]}, '
        'recovered=${nativeOpenResult?[paramRecovered]}, '
        'recoveredInTransaction=${nativeOpenResult?[paramRecoveredInTransaction]}',
      );

      db2 = await _openSingleInstanceDatabase(path);
      final id2 = (db2 as SqfliteDatabaseMixin).id;
      _appendLog('再次打开的 native id=$id2');
      _appendLog('已重新创建 Dart 包装对象: ${!identical(db1, db2)}');
      await db2.insert('Demo', <String, Object?>{'value': '恢复后写入'});
      final count =
          firstIntValue(await db2.rawQuery('SELECT COUNT(*) FROM Demo'));
      _appendLog('再次打开后 Demo 表记录数=$count');
      _appendLog('结论: recovered 验证结果');
      _appendLog(' - native id 是否复用: ${id1 == id2}');
      _appendLog(' - 原生返回 recovered: ${nativeOpenResult?[paramRecovered] == true}');
      _appendLog(' - Dart 包装对象是否重新创建: ${!identical(db1, db2)}');
      _appendLog(' - Demo 表是否可正常读写: ${count == 1}');
      _appendLog(
        (id1 == id2) &&
                (nativeOpenResult?[paramRecovered] == true) &&
                (!identical(db1, db2)) &&
                (count == 1)
            ? '最终结论: 通过，单实例恢复逻辑正常'
            : '最终结论: 失败，单实例恢复逻辑存在异常',
      );
    } finally {
      await _safeClose(db2, 'db2');
      await _safeClose(db1, 'db1');
    }
  }

  Future<void> _runRecoveredInTransactionScenario() async {
    final path =
        await _dbPath('ohos_single_instance_recovered_in_transaction_demo.db');
    Database? db1;
    Database? db2;
    // 说明: 先删除旧数据库，确保本次验证从干净状态开始，避免历史数据干扰结果
    await _safeDelete(path);
    try {
      db1 = await _openSingleInstanceDatabase(path);
      final id1 = (db1 as SqfliteDatabaseMixin).id;
      _appendLog('首次打开的 native id=$id1');

      await db1.execute('BEGIN IMMEDIATE');
      _appendLog('BEGIN IMMEDIATE 执行成功');
      // 说明: 这条插入数据是已经执行了插入语句，但还没有 COMMIT 落盘确认的那条记录，用来验证恢复后是否会被自动回滚
      await db1.insert(
        'Demo',
        <String, Object?>{'value': '恢复前的未提交数据'},
      );
      _appendLog('已写入 1 条事务内未提交记录');

      _removeOpenHelper(db1.path);

      final nativeOpenResult = await _invokeNativeOpen(path);
      _appendLog(
        '原生 openDatabase 返回: '
        'id=${nativeOpenResult?[paramId]}, '
        'recovered=${nativeOpenResult?[paramRecovered]}, '
        'recoveredInTransaction=${nativeOpenResult?[paramRecoveredInTransaction]}',
      );

      db2 = await _openSingleInstanceDatabase(path);
      final id2 = (db2 as SqfliteDatabaseMixin).id;
      final countAfterRecovery =
          firstIntValue(await db2.rawQuery('SELECT COUNT(*) FROM Demo'));
      _appendLog('再次打开的 native id=$id2');
      _appendLog('恢复后再次打开时 Demo 表记录数=$countAfterRecovery');
      _appendLog('结论: recoveredInTransaction 验证结果');
      _appendLog(' - native id 是否复用: ${id1 == id2}');
      _appendLog(' - 原生返回 recovered: ${nativeOpenResult?[paramRecovered] == true}');
      _appendLog(
        ' - 原生返回 recoveredInTransaction: ${nativeOpenResult?[paramRecoveredInTransaction] == true}',
      );
      _appendLog(' - 未提交事务数据是否已回滚: ${countAfterRecovery == 0}');
      _appendLog(
        (id1 == id2) &&
                (nativeOpenResult?[paramRecovered] == true) &&
                (nativeOpenResult?[paramRecoveredInTransaction] == true) &&
                (countAfterRecovery == 0)
            ? '最终结论: 通过，事务中的恢复逻辑正常'
            : '最终结论: 失败，事务中的恢复逻辑存在异常',
      );
    } finally {
      await _safeClose(db2, 'db2');
      await _safeClose(db1, 'db1');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OHOS 单实例恢复验证')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildActionButton(
                  actionKey: 'recovered',
                  label: '验证 recovered',
                  onPressed: () => _runScenario(
                    'recovered',
                    '单实例恢复验证',
                    _runRecoveredScenario,
                  ),
                ),
                const SizedBox(height: 12),
                _buildActionButton(
                  actionKey: 'recoveredInTransaction',
                  label: '验证 recoveredInTransaction',
                  onPressed: () => _runScenario(
                    'recoveredInTransaction',
                    '事务中单实例恢复验证',
                    _runRecoveredInTransactionScenario,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: SelectableText(_logs[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
