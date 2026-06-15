import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite_common/sqflite.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/factory_mixin.dart'
    show SqfliteDatabaseFactoryMixin;
// ignore: deprecated_member_use
import 'package:sqflite_common/sqflite_logger.dart';
// ignore: deprecated_member_use
import 'package:sqflite_common/sqflite_dev.dart';

/// Debug 信息验证测试页面
/// 验证 debug 方法返回完整路径、singleInstance 和 logLevel 信息
class DebugInfoTestPage extends StatefulWidget {
  const DebugInfoTestPage({super.key});

  @override
  State<DebugInfoTestPage> createState() => _DebugInfoTestPageState();
}

class _DebugInfoTestPageState extends State<DebugInfoTestPage> {
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
      // 忽略删除失败
    }
  }

  Future<void> _testDebugInfo() async {
    setState(() {
      _runningAction = '测试 debug 信息';
    });
    _logs.clear();

    try {
      final path1 = await _dbPath('debug_test_single.db');
      final path2 = await _dbPath('debug_test_multi.db');

      await _safeDelete(path1);
      await _safeDelete(path2);

      _appendLog('=== Debug 信息验证测试 ===');

      // 测试0：全局 logLevel 设置
      _appendLog('0. 测试全局 logLevel 设置');
      final factory = databaseFactory as SqfliteDatabaseFactoryMixin;
      
      // 设置全局 logLevel（使用 SqfliteDatabaseFactoryDev 扩展方法）
      // ignore: deprecated_member_use
      await databaseFactory.setLogLevel(sqfliteLogLevelSql);
      _appendLog('   设置全局 logLevel: ${sqfliteLogLevelSql} (sql)');
      
      // 获取 debug 信息验证全局 logLevel
      final debugInfo0 = await factory.getDebugInfo();
      final globalLogLevel = debugInfo0.logLevel;
      _appendLog('   返回的全局 logLevel: $globalLogLevel');
      bool globalLogLevelCorrect = false;
      if (globalLogLevel == sqfliteLogLevelSql) {
        _appendLog('   ✅ 全局 logLevel 正确');
        globalLogLevelCorrect = true;
      } else {
        _appendLog('   ❌ 全局 logLevel 不匹配，期望 ${sqfliteLogLevelSql}，实际 $globalLogLevel');
      }

      // 测试1：单实例数据库
      _appendLog('');
      _appendLog('1. 测试单实例数据库（singleInstance=true）');
      final db1 = await databaseFactory.openDatabase(
        path1,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: true,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT)',
            );
          },
        ),
      );

      final debugInfo1 = await factory.getDebugInfo();

      // 只查找本次测试的数据库
      bool pathCorrect = false;
      bool singleInstanceCorrect = false;
      debugInfo1.databases?.forEach((id, info) {
        if (info.path?.contains('debug_test_single.db') == true) {
          final dbPath = info.path ?? '';
          // 验证 path：应为完整路径（包含目录）
          _appendLog('   path: $dbPath');
          if (dbPath.contains('/') && dbPath.endsWith('debug_test_single.db')) {
            _appendLog('   ✅ path: 完整路径');
            pathCorrect = true;
          } else {
            _appendLog('   ❌ path: 应为完整路径');
          }
          // 验证 singleInstance
          final singleInst = info.singleInstance;
          _appendLog('   singleInstance: $singleInst');
          if (singleInst == true) {
            _appendLog('   ✅ singleInstance: true');
            singleInstanceCorrect = true;
          } else {
            _appendLog('   ❌ singleInstance: 期望 true，实际 $singleInst');
          }
          // 验证 logLevel
          final logLevel = info.logLevel;
          if (logLevel != null) {
            _appendLog('   logLevel: $logLevel');
          } else {
            _appendLog('   logLevel: 未返回（默认值为 0）');
          }
        }
      });

      if (!pathCorrect) {
        _appendLog('   ❌ 未找到 debug_test_single.db');
      }
      if (!singleInstanceCorrect) {
        _appendLog('   ❌ singleInstance 验证失败');
      }

      await db1.close();

      // 测试2：非单实例数据库
      _appendLog('');
      _appendLog('2. 测试非单实例数据库（singleInstance=false）');
      final db2 = await databaseFactory.openDatabase(
        path2,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: false,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT)',
            );
          },
        ),
      );

      final debugInfo2 = await factory.getDebugInfo();

      bool foundFalseInstance = false;
      debugInfo2.databases?.forEach((id, info) {
        if (info.path?.contains('debug_test_multi.db') == true) {
          // 打印 path
          _appendLog('   path: ${info.path}');
          // 验证 singleInstance
          final singleInst = info.singleInstance;
          _appendLog('   singleInstance: $singleInst');
          if (singleInst == false) {
            _appendLog('   ✅ singleInstance: false');
            foundFalseInstance = true;
          } else {
            _appendLog('   ❌ singleInstance: 期望 false，实际 $singleInst');
          }
          // 打印 logLevel
          final logLevel = info.logLevel;
          if (logLevel != null) {
            _appendLog('   logLevel: $logLevel');
          } else {
            _appendLog('   logLevel: 未返回（默认值为 0）');
          }
        }
      });

      if (!foundFalseInstance) {
        _appendLog('   ❌ 未找到 singleInstance=false 的数据库');
      }

      await db2.close();

      // 测试3：验证数据库级 logLevel 设置
      _appendLog('');
      _appendLog('3. 测试数据库级 logLevel 设置');
      final path3 = await _dbPath('debug_test_loglevel.db');
      await _safeDelete(path3);

      // 在打开数据库前，设置全局 logLevel 为 verbose
      // ignore: deprecated_member_use
      await databaseFactory.setLogLevel(sqfliteLogLevelVerbose);
      _appendLog('   设置全局 logLevel: ${sqfliteLogLevelVerbose} (verbose)');

      // 使用 logLevel 参数打开数据库（数据库级会继承全局设置）
      final db3 = await databaseFactory.openDatabase(
        path3,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT)',
            );
          },
        ),
      );

      final debugInfo3 = await factory.getDebugInfo();
      bool dbLogLevelCorrect = false;
      debugInfo3.databases?.forEach((id, info) {
        if (info.path?.contains('debug_test_loglevel.db') == true) {
          final dbLogLevel = info.logLevel;
          _appendLog('   数据库 logLevel: $dbLogLevel');
          // 验证数据库继承的全局 logLevel 值
          if (dbLogLevel != null && dbLogLevel == sqfliteLogLevelVerbose) {
            _appendLog('   ✅ 数据库 logLevel 正确继承全局值 ($sqfliteLogLevelVerbose)');
            dbLogLevelCorrect = true;
          } else if (dbLogLevel != null && dbLogLevel > 0) {
            _appendLog('   ✅ 数据库 logLevel > 0 (值: $dbLogLevel)');
            dbLogLevelCorrect = true;
          } else {
            _appendLog('   ⚠️ 数据库 logLevel 未设置或为 0');
          }
        }
      });

      // 验证全局 logLevel 也在 debug 信息中
      final globalLogLevel3 = debugInfo3.logLevel;
      _appendLog('   全局 logLevel: $globalLogLevel3');
      if (globalLogLevel3 == sqfliteLogLevelVerbose) {
        _appendLog('   ✅ 全局 logLevel 正确');
      }

      await db3.close();
      await _safeDelete(path3);

      // 测试4：验证 deleteDatabase 后清理残留
      _appendLog('');
      _appendLog('4. 测试 deleteDatabase 后清理残留数据');
      final path4 = await _dbPath('debug_test_delete.db');
      await _safeDelete(path4);

      // 打开数据库
      final db4 = await databaseFactory.openDatabase(
        path4,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: true,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT)',
            );
          },
        ),
      );

      // 验证数据库在 debug 信息中存在
      final debugInfoBefore = await factory.getDebugInfo();
      bool foundBeforeDelete = false;
      debugInfoBefore.databases?.forEach((id, info) {
        if (info.path?.contains('debug_test_delete.db') == true) {
          foundBeforeDelete = true;
          _appendLog('   删除前：数据库存在于 debug 信息中');
        }
      });

      if (!foundBeforeDelete) {
        _appendLog('   ❌ 删除前：数据库未在 debug 信息中找到');
      }

      // 关闭并删除数据库
      await db4.close();
      await databaseFactory.deleteDatabase(path4);
      _appendLog('   已关闭并删除数据库');

      // 验证数据库在 debug 信息中已被清理
      final debugInfoAfter = await factory.getDebugInfo();
      bool foundAfterDelete = false;
      debugInfoAfter.databases?.forEach((id, info) {
        if (info.path?.contains('debug_test_delete.db') == true) {
          foundAfterDelete = true;
        }
      });

      bool cleanupCorrect = false;
      if (!foundAfterDelete) {
        _appendLog('   ✅ 删除后：数据库已从 debug 信息中清理');
        cleanupCorrect = true;
      } else {
        _appendLog('   ❌ 删除后：数据库仍在 debug 信息中（清理失败）');
      }

      // 清理
      await _safeDelete(path1);
      await _safeDelete(path2);

      // 恢复全局 logLevel
      // ignore: deprecated_member_use
      await databaseFactory.setLogLevel(sqfliteLogLevelNone);

      // 总结
      _appendLog('');
      if (globalLogLevelCorrect && pathCorrect && singleInstanceCorrect && foundFalseInstance && dbLogLevelCorrect && cleanupCorrect) {
        _appendLog('=== 测试通过 ===');
      } else {
        _appendLog('=== 测试失败 ===');
        if (!globalLogLevelCorrect) {
          _appendLog('失败项：全局 logLevel 未正确返回');
        }
        if (!pathCorrect) {
          _appendLog('失败项：path 未返回完整路径');
        }
        if (!singleInstanceCorrect) {
          _appendLog('失败项：singleInstance=true 未正确返回');
        }
        if (!foundFalseInstance) {
          _appendLog('失败项：singleInstance=false 未正确返回');
        }
        if (!dbLogLevelCorrect) {
          _appendLog('失败项：数据库级 logLevel 未正确设置');
        }
        if (!cleanupCorrect) {
          _appendLog('失败项：deleteDatabase 后残留数据未清理');
        }
      }
    } catch (e, stack) {
      _appendLog('❌ 测试异常: $e');
      _appendLog('堆栈: $stack');
    } finally {
      setState(() {
        _runningAction = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug 信息验证测试'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: _runningAction != null ? null : _testDebugInfo,
                  child: const Text('验证 debug 返回信息'),
                ),
              ],
            ),
          ),
          if (_runningAction != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                '正在执行: $_runningAction',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                final isPass = log.contains('✅');
                final isFail = log.contains('❌');
                return Text(
                  log,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: isPass
                        ? Colors.green
                        : isFail
                            ? Colors.red
                            : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
