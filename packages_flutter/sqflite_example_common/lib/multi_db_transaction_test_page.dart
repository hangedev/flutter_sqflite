// 多数据库事务隔离测试页面
// 用于验证问题4、6的修复：静态事务变量在多数据库场景下的隔离性

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite_common/sqflite.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/internals.dart';
import 'package:sqflite_example_common/database/database.dart';

/// 多数据库事务隔离测试路由
const String testMultiDbTransactionRoute = '/test/multi_db_transaction';

/// 多数据库事务隔离测试页面
class MultiDbTransactionTestPage extends StatefulWidget {
  /// 构造函数
  const MultiDbTransactionTestPage({super.key});

  @override
  State<MultiDbTransactionTestPage> createState() =>
      _MultiDbTransactionTestPageState();
}

class _MultiDbTransactionTestPageState
    extends State<MultiDbTransactionTestPage> {
  final List<String> _logs = [];
  final Set<String> _runningScenes = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('多数据库事务隔离测试'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildButtonSection(),
            const Divider(),
            Container(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 200,
              ),
              color: Colors.black87,
              child: _buildLogSection(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtonSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTestButton(
            '场景1: 多数据库并发操作 - 基础隔离',
            _runScenario1,
            Colors.blue,
          ),
          const SizedBox(height: 8),
          _buildTestButton(
            '场景2: 多数据库并发操作 - 交叉事务',
            _runScenario2,
            Colors.green,
          ),
          const SizedBox(height: 8),
          _buildTestButton(
            '场景3: 数据库关闭不影响其他数据库事务',
            _runScenario3,
            Colors.orange,
          ),
          const SizedBox(height: 8),
          _buildTestButton(
            '场景4: 高并发多数据库操作',
            _runScenario4,
            Colors.red,
          ),
          const SizedBox(height: 8),
          _buildTestButton(
            '运行所有场景',
            _runAllScenarios,
            Colors.teal,
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _clearLogs,
            child: const Text('清空日志'),
          ),
        ],
      ),
    );
  }

  Widget _buildTestButton(String text, VoidCallback onPressed, Color color) {
    return ElevatedButton(
      onPressed: _runningScenes.contains(text) ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      child: Text(text),
    );
  }

  Widget _buildLogSection() {
    return Column(
      children: _logs.map((log) {
        Color textColor = Colors.white;
        if (log.contains('❌')) {
          textColor = Colors.red;
        } else if (log.contains('✅')) {
          textColor = Colors.green;
        } else if (log.contains('⚠️')) {
          textColor = Colors.orange;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(
            log,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: textColor,
            ),
          ),
        );
      }).toList(),
    );
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
    });
    // 输出到控制台便于调试
    print(message);
  }

  void _clearLogs() => setState(() => _logs.clear());

  // ========== 以下是四个测试场景 ==========
  Future<void> _runScenario1() async {
    _addLog('========== 场景1: 多数据库并发操作 - 基础隔离========== ');
    final scene = '场景1: 多数据库并发操作 - 基础隔离';
    _runningScenes.add(scene);
    try {
      // 清理旧数据库
      await _deleteDatabase('db_a.db');
      await _deleteDatabase('db_b.db');

      // 1. 打开数据库 A
      _addLog('步骤1: 打开数据库 A');
      Database dbA = await openDatabase('db_a.db');
      await dbA.execute(
          'CREATE TABLE test_a (id INTEGER PRIMARY KEY, value TEXT)');
      _addLog('✅ 数据库 A 打开成功');

      // 2. 打开数据库 B
      _addLog('步骤2: 打开数据库 B');
      Database dbB = await openDatabase('db_b.db');
      await dbB.execute(
          'CREATE TABLE test_b (id INTEGER PRIMARY KEY, value TEXT)');
      _addLog('✅ 数据库 B 打开成功');

      // 3. 在数据库 A 开始事务
      _addLog('步骤3: 在数据库 A 开始事务');
      await dbA.transaction((txn) async {
        await txn.insert('test_a', {'value': 'in_transaction_a'});
        _addLog('  插入数据到 A: in_transaction_a');

        // 4. 在数据库 B 也开始事务
        _addLog('步骤4: 在数据库 B 开始事务');
        await dbB.transaction((txnB) async {
          await txnB.insert('test_b', {'value': 'in_transaction_b'});
          _addLog('  插入数据到 B: in_transaction_b');

          // 5. 继续在数据库 A 的事务中操作
          await txn.insert('test_a', {'value': 'second_insert_a'});
          _addLog('  继续插入数据到 A: second_insert_a');

          // 6. 提交数据库 B 的事务
        });
        _addLog('✅ 数据库 B 事务提交');

        // 7. 提交数据库 A 的事务
      });
      _addLog('✅ 数据库 A 事务提交');

      // 8. 验证两个数据库的数据
      _addLog('步骤5: 验证数据');
      List<Map> rowsA = await dbA.query('test_a');
      List<Map> rowsB = await dbB.query('test_b');

      _addLog('数据库 A 记录数: ${rowsA.length}');
      _addLog('数据库 B 记录数: ${rowsB.length}');

      bool success = true;
      if (rowsA.length != 2) {
        _addLog('❌ 数据库 A 应该有 2 条记录，实际有 ${rowsA.length} 条');
        success = false;
      }
      if (rowsB.length != 1) {
        _addLog('❌ 数据库 B 应该有 1 条记录，实际有 ${rowsB.length} 条');
        success = false;
      }

      if (success) {
        _addLog('✅ 场景1 测试通过！');
      }

      await dbA.close();
      await dbB.close();
    } catch (e, stackTrace) {
      _addLog('❌ 场景1 测试失败: $e');
      _addLog('堆栈: $stackTrace');
    } finally {
      _runningScenes.remove(scene);
    }
  }

  // 场景2: 多数据库并发操作 - 交叉事务
  Future<void> _runScenario2() async {
    _addLog('========== 场景2: 多数据库并发操作 - 交叉事务========== ');
    final scene = '场景2: 多数据库并发操作 - 交叉事务';
    _runningScenes.add(scene);
    try {
      // 清理旧数据库
      await _deleteDatabase('db_a.db');
      await _deleteDatabase('db_b.db');

      _addLog('步骤1: 打开数据库 A 和 B');
      Database dbA = await openDatabase('db_a.db');
      Database dbB = await openDatabase('db_b.db');

      await dbA.execute(
          'CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)');
      await dbB.execute(
          'CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)');
      _addLog('✅ 数据库创建成功');

      // 使用 Completer 控制时序
      Completer<void> blockerA = Completer();
      Completer<void> blockerB = Completer();

      _addLog('步骤2: 并发启动两个事务');

      // 并发启动两个事务
      Future<void> txA = dbA.transaction((txn) async {
        await txn.insert('test', {'value': 'A_start'});
        _addLog('  数据库 A: 插入 A_start');
        await blockerA.future; // 等待信号
        await txn.insert('test', {'value': 'A_end'});
        _addLog('  数据库 A: 插入 A_end');
      });

      Future<void> txB = dbB.transaction((txn) async {
        await txn.insert('test', {'value': 'B_start'});
        _addLog('  数据库 B: 插入 B_start');
        await blockerB.future; // 等待信号
        await txn.insert('test', {'value': 'B_end'});
        _addLog('  数据库 B: 插入 B_end');
      });

      // 解除阻塞
      await Future.delayed(const Duration(milliseconds: 100));
      _addLog('步骤3: 解除阻塞');
      blockerA.complete();
      blockerB.complete();

      await Future.wait([txA, txB]);
      _addLog('✅ 两个事务都已完成');

      // 验证
      _addLog('步骤4: 验证数据');
      List<Map> rowsA = await dbA.query('test');
      List<Map> rowsB = await dbB.query('test');

      _addLog('数据库 A 记录数: ${rowsA.length}');
      _addLog('数据库 B 记录数: ${rowsB.length}');

      bool success = true;
      if (rowsA.length != 2) {
        _addLog('❌ 数据库 A 应该有 2 条记录，实际有 ${rowsA.length} 条');
        success = false;
      }
      if (rowsB.length != 2) {
        _addLog('❌ 数据库 B 应该有 2 条记录，实际有 ${rowsB.length} 条');
        success = false;
      }

      if (success) {
        _addLog('✅ 场景2 测试通过！');
      }

      await dbA.close();
      await dbB.close();
    } catch (e, stackTrace) {
      _addLog('❌ 场景2 测试失败: $e');
      _addLog('堆栈: $stackTrace');
    } finally {
      _runningScenes.remove(scene);
    }
  }

  // 场景3: 数据库关闭不影响其他数据库事务
  Future<void> _runScenario3() async {
    _addLog('========== 场景3: 数据库关闭不影响其他数据库事务========== ');
    final scene = '场景3: 数据库关闭不影响其他数据库事务';
    _runningScenes.add(scene);
    try {
      // 清理旧数据库
      await _deleteDatabase('db_a.db');
      await _deleteDatabase('db_b.db');

      // 1. 打开数据库 A 和 B
      _addLog('步骤1: 打开数据库 A 和 B');
      Database dbA = await openDatabase('db_a.db');
      Database dbB = await openDatabase('db_b.db');

      await dbA.execute(
          'CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)');
      await dbB.execute(
          'CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)');
      _addLog('✅ 数据库创建成功');

      // 打印初始事务深度
      Map<String, int> depths1 = await _getTransactionDepths();
      _addLog('  初始事务深度: db_a=${depths1['db_a.db'] ?? 0}, db_b=${depths1['db_b.db'] ?? 0}');

      // 2. 在数据库 A 开始事务
      _addLog('步骤2: 在数据库 A 开始事务（使用 BEGIN IMMEDIATE）');
      await dbA.execute('BEGIN IMMEDIATE');
      await dbA.insert('test', {'value': 'in_tx_a'});
      _addLog('  插入数据到 A: in_tx_a');

      // 打印事务开始后的深度
      Map<String, int> depths2 = await _getTransactionDepths();
      _addLog('  事务开始后深度: db_a=${depths2['db_a.db'] ?? 0}, db_b=${depths2['db_b.db'] ?? 0}');

      // 3. 关闭数据库 B
      _addLog('步骤3: 关闭数据库 B');
      await dbB.close();
      _addLog('✅ 数据库 B 已关闭');

      // 关键测试点：关闭数据库B后，数据库A的事务深度应该保持不变
      Map<String, int> depths3 = await _getTransactionDepths();
      _addLog('  关闭B后深度: db_a=${depths3['db_a.db'] ?? 0}');
      if (depths3['db_a.db'] != 1) {
        _addLog('⚠️ 警告: 数据库A的事务深度应该在关闭B后保持为1！');
      } else {
        _addLog('✅ 正常: 数据库A的事务深度保持为1，未受关闭B的影响');
      }

      // 4. 继续操作数据库 A 的事务
      _addLog('步骤4: 继续操作数据库 A 的事务');
      await dbA.insert('test', {'value': 'still_in_tx_a'});
      _addLog('  插入数据到 A: still_in_tx_a');

      // 打印继续操作后的深度
      Map<String, int> depths4 = await _getTransactionDepths();
      _addLog('  继续操作后深度: db_a=${depths4['db_a.db'] ?? 0}');

      // 5. 提交数据库 A 的事务
      _addLog('步骤5: 提交数据库 A 的事务');
      await dbA.execute('COMMIT');
      _addLog('✅ 事务提交成功');

      // 打印提交后的深度
      Map<String, int> depths5 = await _getTransactionDepths();
      _addLog('  提交后深度: db_a=${depths5['db_a.db'] ?? 0}');

      // 6. 验证
      _addLog('步骤6: 验证数据');
      List<Map> rows = await dbA.query('test');
      _addLog('数据库 A 记录数: ${rows.length}');

      bool success = true;
      if (rows.length != 2) {
        _addLog('❌ 数据库 A 应该有 2 条记录，实际有 ${rows.length} 条');
        success = false;
      }

      if (success) {
        _addLog('✅ 场景3 测试通过！');
      }

      await dbA.close();
    } catch (e, stackTrace) {
      _addLog('❌ 场景3 测试失败: $e');
      _addLog('堆栈: $stackTrace');
    } finally {
      _runningScenes.remove(scene);
    }
  }

  // 场景4: 高并发多数据库操作
  Future<void> _runScenario4() async {
    _addLog('========== 场景4: 高并发多数据库操作========== ');
    final scene = '场景4: 高并发多数据库操作';
    _runningScenes.add(scene);
    try {
      _addLog('步骤1: 创建 5 个数据库');

      // 清理旧数据库
      for (int i = 0; i < 5; i++) {
        await _deleteDatabase('db_$i.db');
      }

      // 创建 5 个数据库
      List<Database> dbs = [];
      for (int i = 0; i < 5; i++) {
        Database db = await openDatabase('db_$i.db');
        await db.execute(
            'CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)');
        dbs.add(db);
        _addLog('  数据库 $i 创建成功');
      }
      _addLog('✅ 所有数据库创建成功');

      _addLog('步骤2: 并发执行事务（每个数据库 10 次事务，每次插入 10 条记录）');

      // 每个数据库并发执行 10 次事务，每次插入 10 条记录
      List<Future<void>> futures = [];
      for (int dbIndex = 0; dbIndex < 5; dbIndex++) {
        final index = dbIndex;
        futures.add(Future(() async {
          for (int txIndex = 0; txIndex < 10; txIndex++) {
            await dbs[index].transaction((txn) async {
              for (int i = 0; i < 10; i++) {
                await txn.insert('test', {
                  'value': 'db${index}_tx${txIndex}_$i',
                });
              }
            });
          }
        }));
      }

      await Future.wait(futures);
      _addLog('✅ 所有事务完成');

      // 验证每个数据库
      _addLog('步骤3: 验证数据');
      bool success = true;
      for (int i = 0; i < 5; i++) {
        List<Map> rows = await dbs[i].query('test');
        _addLog('数据库 $i 记录数: ${rows.length}');

        if (rows.length != 100) {
          _addLog('❌ 数据库 $i 应该有 100 条记录，实际有 ${rows.length} 条');
          success = false;
        }

        await dbs[i].close();
      }

      if (success) {
        _addLog('✅ 场景4 测试通过！');
      }
    } catch (e, stackTrace) {
      _addLog('❌ 场景4 测试失败: $e');
      _addLog('堆栈: $stackTrace');
    } finally {
      _runningScenes.remove(scene);
    }
  }

  // 运行所有场景
  Future<void> _runAllScenarios() async {
    _addLog('========== 开始运行所有场景 ==========');

    await _runScenario1();
    await Future.delayed(const Duration(seconds: 1));

    await _runScenario2();
    await Future.delayed(const Duration(seconds: 1));

    await _runScenario3();
    await Future.delayed(const Duration(seconds: 1));

    await _runScenario4();
    _addLog('========== 所有场景运行完成 ==========');
  }

  // 辅助方法：删除数据库
  Future<void> _deleteDatabase(String name) async {
    try {
      final path = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$path/$name');
    } catch (e) {
      // 忽略删除失败
    }
  }

  // 辅助方法：获取所有数据库的事务深度（调试用）
  Future<Map<String, int>> _getTransactionDepths() async {
    try {
      // 使用 internalsInvokeMethod 直接调用原生的 debug 方法
      final result = await databaseFactory.internalsInvokeMethod<Map<Object?, Object?>>(
        'debug',
        <String, Object?>{'cmd': 'get'},
      );

      Map<String, int> depths = {};
      if (result != null && result['databases'] != null) {
        final databases = result['databases'] as Map<Object?, Object?>;
        databases.forEach((dbId, info) {
          if (info is Map<Object?, Object?>) {
            final dbPath = info['path'] as String?;
            final depth = info['transactionDepth'] as int?;
            if (dbPath != null && depth != null) {
              // 使用路径的最后部分作为键（如 'db_a.db'）
              // 同时保留完整路径作为键，以便两种查找方式都能工作
              final shortName = dbPath.split('/').last;
              depths[shortName] = depth;
              depths[dbPath] = depth;
            }
          }
        });
      }
      return depths;
    } catch (e) {
      _addLog('⚠️ 获取事务深度失败: $e');
      return {};
    }
  }
}
