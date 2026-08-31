import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';
// ignore: implementation_imports
import 'package:sqflite_common/src/internals.dart';

/// 检视问题验证页：针对稳定性 / 内存泄露 / 一致性检视修复的 demo 级验证。
///
/// 覆盖 6 个修复点：
/// 1. 分页游标（ResultSet）随库关闭回收
/// 2. detach / 热重启资源清理（关闭全部库后重开验证）
/// 3. 关键入口参数校验（非法 path / ATTACH 缺参）
/// 4. 事务错误契约（异常带 code/message、失败回滚、库可继续使用）
/// 5. 零行查询返回结构
/// 6. 关闭/回执边界压力（循环开关库 + 异常查询 + 不消费游标）
///
/// 说明：泄漏量与时序类问题（1/2/6）的最终佐证需配合 hilog /
/// DevEco Profiler 观察；本页面验证功能面不回归、异常路径不挂起。
class InspectionVerifyPage extends StatefulWidget {
  /// Inspection verify test page.
  const InspectionVerifyPage({super.key});

  /// Create the inspection verify page state.
  @override
  State<InspectionVerifyPage> createState() => _InspectionVerifyPageState();
}

enum _VerifyState { idle, running, passed, failed }

class _VerifyItem {
  _VerifyItem({required this.title, required this.expected});

  final String title;
  final String expected;
  _VerifyState state = _VerifyState.idle;
  String details = '尚未执行';
}

class _InspectionVerifyPageState extends State<InspectionVerifyPage> {
  final _cursorLeakItem = _VerifyItem(
    title: '1. 分页游标随库关闭回收',
    expected: '反复"建游标→不消费→关库"后数据库可正常重开，数据完好，'
        '完整消费游标正常；泄漏量请配合 hilog 观察。',
  );

  final _detachCleanupItem = _VerifyItem(
    title: '2. detach / 热重启资源清理',
    expected: '打开多个数据库（含内存库）→ 全部关闭 → 重开验证数据完好、'
        'deleteDatabase 正常；随后可热重启验证 worker 清理日志。',
  );

  final _paramCheckItem = _VerifyItem(
    title: '3. 参数校验（非法 path / ATTACH 缺参）',
    expected: '空 path 的 openDatabase / databaseExists / deleteDatabase'
        '（经 internalsInvokeMethod 直发 channel）与 ATTACH 缺参均快速'
        '抛出含明确错误信息的异常，不挂起、不崩溃。',
  );

  final _txnErrorItem = _VerifyItem(
    title: '4. 事务错误契约',
    expected: '事务内约束冲突抛出带错误信息的 DatabaseException；'
        'batch 失败整体回滚；事务失败后库仍可正常使用（无残留锁）。',
  );

  final _emptyQueryItem = _VerifyItem(
    title: '5. 零行查询返回结构',
    expected: '空表 / WHERE 不命中的 query、rawQuery 返回空 List 而非抛异常；'
        '有数据时字段名映射正确。',
  );

  final _pressureItem = _VerifyItem(
    title: '6. 边界压力（循环开关库+异常查询+不消费游标）',
    expected: '全部轮次成功完成；每轮的异常查询都收到 DatabaseException'
        '（非空回复、非超时）。运行中可热重启验证回执防护。',
  );

  /// 简化 COUNT(*) 结果读取（sqflite 主包的 Sqflite.firstIntValue
  /// 不在 sqflite_common 中，demo 内自行实现）。
  int? _firstIntValue(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return null;
    }
    return rows.first.values.first as int?;
  }

  Future<String> _newDbPath(String prefix) async {
    final factory = databaseFactory;
    return p.join(
      await factory.getDatabasesPath(),
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}.db',
    );
  }

  /// 问题 1：分页游标随库关闭回收。
  /// 反复"建游标→只消费一页→不关游标直接关库"，修复后关库会统一回收
  /// 该库未消费游标；随后重开库验证数据完好、完整消费游标正常。
  Future<void> _runCursorLeakCheck() async {
    if (_cursorLeakItem.state == _VerifyState.running) {
      return;
    }
    _setStatus(_cursorLeakItem, _VerifyState.running, '正在准备数据库...');
    const rounds = 30;
    final buffer = <String>[];
    final dbPath = await _newDbPath('insp_cursor');
    final sw = Stopwatch()..start();
    try {
      var db = await databaseFactory.deleteDatabase(dbPath).then(
            (_) => databaseFactory.openDatabase(dbPath),
          );
      await db.execute('CREATE TABLE Test (id INTEGER PRIMARY KEY, value TEXT)');
      await db.insert('Test', {'id': 1, 'value': 'a'});
      await db.close();
      buffer.add('已建库并写入 1 行（$dbPath）');

      for (var i = 0; i < rounds; i++) {
        db = await databaseFactory.openDatabase(dbPath);
        // 只消费一页，不 close、不消费完 —— 修复前这些游标在关库后无人回收
        final cursor = await db.rawQueryCursor(
          'SELECT * FROM Test',
          <Object?>[],
          bufferSize: 1,
        );
        await cursor.moveNext();
        await db.close();
      }
      sw.stop();
      buffer.add('已完成 $rounds 轮"建游标→不消费→关库"，'
          '耗时 ${sw.elapsedMilliseconds}ms');

      // 关库回收后重开：数据完好
      db = await databaseFactory.openDatabase(dbPath);
      final count =
          _firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM Test'));
      final rows = await db.query('Test');
      // 完整消费一个游标验证游标路径正常
      final fullCursor = await db.rawQueryCursor(
        'SELECT * FROM Test',
        <Object?>[],
        bufferSize: 1,
      );
      var consumed = 0;
      while (await fullCursor.moveNext()) {
        consumed++;
      }
      await db.close();

      final passed =
          count == 1 && rows.length == 1 && consumed == 1 && rows.first['value'] == 'a';
      buffer.add('重开后 COUNT=$count，query 行数=${rows.length}，'
          '完整消费游标行数=$consumed');
      await databaseFactory.deleteDatabase(dbPath);
      _setStatus(
        _cursorLeakItem,
        passed ? _VerifyState.passed : _VerifyState.failed,
        buffer.join('\n'),
      );
    } catch (e, st) {
      sw.stop();
      _setStatus(
        _cursorLeakItem,
        _VerifyState.failed,
        '${buffer.join('\n')}\n非预期错误：$e\n$st',
      );
    }
  }

  /// 问题 2：detach / 热重启资源清理。
  /// 打开多个库（含内存库）→ 操作 → 全部关闭 → 重开验证。
  /// 全部关闭后可热重启应用，hilog 中应出现 RdbStore close /
  /// 内存库临时文件删除 / worker 退出日志，重启后回本页重跑应通过。
  Future<void> _runDetachCleanupCheck() async {
    if (_detachCleanupItem.state == _VerifyState.running) {
      return;
    }
    _setStatus(_detachCleanupItem, _VerifyState.running, '正在打开多个数据库...');
    final buffer = <String>[];
    final path1 = await _newDbPath('insp_detach1');
    final path2 = await _newDbPath('insp_detach2');
    try {
      final db1 = await databaseFactory.deleteDatabase(path1).then(
            (_) => databaseFactory.openDatabase(path1),
          );
      final db2 = await databaseFactory.openDatabase(path2);
      // 内存库：OHOS 侧落地为临时文件，dispose 时应被删除
      final memDb = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db1.execute('CREATE TABLE T (id INTEGER PRIMARY KEY)');
      await db2.execute('CREATE TABLE T (id INTEGER PRIMARY KEY)');
      await memDb.execute('CREATE TABLE T (id INTEGER PRIMARY KEY)');
      await db1.insert('T', {'id': 1});
      await db2.insert('T', {'id': 2});
      await memDb.insert('T', {'id': 3});
      buffer.add('已打开 2 个文件库 + 1 个内存库并各写入 1 行');

      await memDb.close();
      await db2.close();
      await db1.close();
      buffer.add('已全部关闭（此时可热重启应用，观察 hilog 清理日志）');

      // 重开验证：文件库数据完好；内存库可重新打开使用
      final reopen1 = await databaseFactory.openDatabase(path1);
      final reopen2 = await databaseFactory.openDatabase(path2);
      final reopenMem = await databaseFactory.openDatabase(inMemoryDatabasePath);
      // ':memory:' 重开是全新空库（原生每次生成唯一临时文件），需重新建表
      await reopenMem.execute('CREATE TABLE T (id INTEGER PRIMARY KEY)');
      final c1 =
          _firstIntValue(await reopen1.rawQuery('SELECT COUNT(*) FROM T'));
      final c2 =
          _firstIntValue(await reopen2.rawQuery('SELECT COUNT(*) FROM T'));
      await reopenMem.insert('T', {'id': 9});
      final cm =
          _firstIntValue(await reopenMem.rawQuery('SELECT COUNT(*) FROM T'));
      await reopenMem.close();
      await reopen1.close();
      await reopen2.close();
      await databaseFactory.deleteDatabase(path1);
      await databaseFactory.deleteDatabase(path2);
      buffer.add('重开后文件库 COUNT=$c1/$c2（预期 1/1），内存库重新可用 COUNT=$cm');

      final passed = c1 == 1 && c2 == 1 && cm == 1;
      _setStatus(
        _detachCleanupItem,
        passed ? _VerifyState.passed : _VerifyState.failed,
        buffer.join('\n'),
      );
    } catch (e, st) {
      _setStatus(
        _detachCleanupItem,
        _VerifyState.failed,
        '${buffer.join('\n')}\n非预期错误：$e\n$st',
      );
    }
  }

  /// 问题 3：关键入口参数校验。
  /// 空 path 三入口 + ATTACH '?' 占位缺参，均应快速收到异常（含明确错误信息）。
  ///
  /// 说明：Dart 公开 API 的 fixPath 会把空 path 规范化为 databasesPath
  /// （join(databasesPath, '')），空字符串到不了原生校验，因此前三个
  /// 用例经 internalsInvokeMethod 直发 method channel 验证原生参数校验
  /// （与 multi_db_transaction / open_database_behavior 页用法一致）。
  /// 直发路径抛出的是 PlatformException；公开 API 路径包装为
  /// DatabaseException。
  Future<void> _runParamCheck() async {
    if (_paramCheckItem.state == _VerifyState.running) {
      return;
    }
    _setStatus(_paramCheckItem, _VerifyState.running, '正在执行非法入参校验...');
    final buffer = <String>[];
    var passed = true;

    Future<void> check(
      String name,
      String expectedFragment,
      Future<void> Function() action,
    ) async {
      try {
        await action().timeout(const Duration(seconds: 5));
        passed = false;
        buffer.add('$name：异常 —— 竟然成功返回（预期抛异常）');
      } on TimeoutException {
        passed = false;
        buffer.add('$name：异常 —— 调用超时（疑似原生侧挂起）');
      } on DatabaseException catch (e) {
        final ok = e.toString().contains(expectedFragment);
        if (!ok) {
          passed = false;
        }
        buffer.add(
            '$name：${ok ? '通过' : '错误信息不含预期片段 "$expectedFragment"'}\n  $e');
      } on PlatformException catch (e) {
        final ok = (e.message ?? '').contains(expectedFragment);
        if (!ok) {
          passed = false;
        }
        buffer.add(
            '$name：${ok ? '通过' : '错误信息不含预期片段 "$expectedFragment"'}\n  PlatformException(${e.code}, ${e.message})');
      } catch (e) {
        passed = false;
        buffer.add('$name：异常 —— 出现非预期类型错误：$e');
      }
    }

    final dbPath = await _newDbPath('insp_param');
    try {
      await check('openDatabase(空 path)', 'invalid path', () async {
        // ignore: invalid_use_of_visible_for_testing_member
        await databaseFactory.internalsInvokeMethod<Map<Object?, Object?>>(
          'openDatabase',
          <String, Object?>{'path': ''},
        );
      });
      await check('databaseExists(空 path)', 'invalid path', () async {
        // ignore: invalid_use_of_visible_for_testing_member
        await databaseFactory.internalsInvokeMethod<Map<Object?, Object?>>(
          'databaseExists',
          <String, Object?>{'path': ''},
        );
      });
      await check('deleteDatabase(空 path)', 'invalid path', () async {
        // ignore: invalid_use_of_visible_for_testing_member
        await databaseFactory.internalsInvokeMethod<Map<Object?, Object?>>(
          'deleteDatabase',
          <String, Object?>{'path': ''},
        );
      });
      // ATTACH '?' 占位符但缺参数：修复前原生非空断言抛 TypeError，
      // 只能靠 worker 顶层兜底转成通用 error
      await check('ATTACH 缺参', 'attach', () async {
        final db =
            await databaseFactory.deleteDatabase(dbPath).then(
                  (_) => databaseFactory.openDatabase(dbPath),
                );
        try {
          await db.execute('ATTACH DATABASE ? AS ?', <Object?>[]);
        } finally {
          await db.close();
        }
      });
      await databaseFactory.deleteDatabase(dbPath);
      _setStatus(
        _paramCheckItem,
        passed ? _VerifyState.passed : _VerifyState.failed,
        buffer.join('\n'),
      );
    } catch (e, st) {
      _setStatus(
        _paramCheckItem,
        _VerifyState.failed,
        '${buffer.join('\n')}\n非预期错误：$e\n$st',
      );
    }
  }

  /// 问题 4：事务错误契约。
  /// 事务内约束冲突 → 异常带错误信息；batch 失败整体回滚；
  /// 事务失败后库仍可正常使用。
  Future<void> _runTxnErrorCheck() async {
    if (_txnErrorItem.state == _VerifyState.running) {
      return;
    }
    _setStatus(_txnErrorItem, _VerifyState.running, '正在验证事务错误路径...');
    final buffer = <String>[];
    var passed = true;
    final dbPath = await _newDbPath('insp_txn');
    try {
      final db = await databaseFactory.deleteDatabase(dbPath).then(
            (_) => databaseFactory.openDatabase(dbPath),
          );
      await db.execute('CREATE TABLE Test (id INTEGER PRIMARY KEY, value TEXT)');

      // 事务内唯一约束冲突
      try {
        await db.transaction((txn) async {
          await txn.insert('Test', {'id': 1, 'value': 'a'});
          await txn.insert('Test', {'id': 1, 'value': 'dup'});
        });
        passed = false;
        buffer.add('事务约束冲突：异常 —— 竟然成功提交');
      } on DatabaseException catch (e) {
        // 修复前：error 信封迟到导致 Dart 侧收到空回复（null），
        // 表现为 MissingPluginException 或静默
        buffer.add('事务约束冲突：收到 DatabaseException\n  $e');
      } catch (e) {
        passed = false;
        buffer.add('事务约束冲突：异常 —— 非 DatabaseException：$e');
      }

      // 事务失败后库可继续使用（无残留事务锁）
      try {
        await db.transaction((txn) async {
          await txn.insert('Test', {'id': 2, 'value': 'b'});
        });
        buffer.add('事务失败后新事务提交：正常');
      } catch (e) {
        passed = false;
        buffer.add('事务失败后新事务提交：异常 —— $e');
      }

      // batch 失败整体回滚（第一条也不应残留）
      final batch = db.batch();
      batch.insert('Test', {'id': 3, 'value': 'c'});
      batch.insert('Test', {'id': 2, 'value': 'conflict'});
      try {
        await batch.commit(noResult: true);
        passed = false;
        buffer.add('batch 约束冲突：异常 —— 竟然成功提交');
      } on DatabaseException catch (e) {
        buffer.add('batch 约束冲突：收到 DatabaseException\n  $e');
      } catch (e) {
        passed = false;
        buffer.add('batch 约束冲突：异常 —— 非 DatabaseException：$e');
      }
      final count =
          _firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM Test'));
      buffer.add('batch 失败后 COUNT=$count（预期 1：冲突事务与 batch 均已'
          '回滚，仅事务失败后新事务提交的 id=2 存在）');
      if (count != 1) {
        passed = false;
      }

      await db.close();
      await databaseFactory.deleteDatabase(dbPath);
      _setStatus(
        _txnErrorItem,
        passed ? _VerifyState.passed : _VerifyState.failed,
        buffer.join('\n'),
      );
    } catch (e, st) {
      _setStatus(
        _txnErrorItem,
        _VerifyState.failed,
        '${buffer.join('\n')}\n非预期错误：$e\n$st',
      );
    }
  }

  /// 问题 5：零行查询返回结构。
  /// 修复前空结果的原生信封缺 columns/rows 键，靠 Dart 解析层容错侥幸
  /// 兼容；demo 层验证空查询返回空 List 不抛异常、有数据时映射正确。
  Future<void> _runEmptyQueryCheck() async {
    if (_emptyQueryItem.state == _VerifyState.running) {
      return;
    }
    _setStatus(_emptyQueryItem, _VerifyState.running, '正在验证零行查询...');
    final buffer = <String>[];
    var passed = true;
    final dbPath = await _newDbPath('insp_empty');
    try {
      final db = await databaseFactory.deleteDatabase(dbPath).then(
            (_) => databaseFactory.openDatabase(dbPath),
          );
      await db.execute(
        'CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)',
      );

      final emptyQuery = await db.query('Test');
      final emptyRaw = await db.rawQuery(
        'SELECT * FROM Test WHERE id = ?',
        <Object?>[99],
      );
      final emptyColumns = await db.rawQuery(
        'SELECT id, name, age FROM Test WHERE id = ?',
        <Object?>[99],
      );
      buffer.add('空表 query 行数=${emptyQuery.length}（预期 0）');
      buffer.add('WHERE 不命中 rawQuery 行数=${emptyRaw.length}（预期 0）');
      if (emptyQuery.isNotEmpty || emptyRaw.isNotEmpty || emptyColumns.isNotEmpty) {
        passed = false;
      }

      // 有数据时字段名映射正确（列元数据路径未被零行修复影响）
      await db.insert('Test', {'id': 1, 'name': 'n', 'age': 10});
      final row = (await db.query('Test')).first;
      final mappedOk =
          row.keys.contains('id') && row.keys.contains('name') && row['age'] == 10;
      buffer.add('有数据时字段映射：${mappedOk ? '正确' : '异常'} $row');
      if (!mappedOk) {
        passed = false;
      }

      await db.close();
      await databaseFactory.deleteDatabase(dbPath);
      _setStatus(
        _emptyQueryItem,
        passed ? _VerifyState.passed : _VerifyState.failed,
        buffer.join('\n'),
      );
    } catch (e, st) {
      _setStatus(
        _emptyQueryItem,
        _VerifyState.failed,
        '${buffer.join('\n')}\n非预期错误：$e\n$st',
      );
    }
  }

  /// 问题 6：关闭/回执边界压力。
  /// 循环"开库→batch 写入→正常查询→异常查询→建游标不消费→关库"，
  /// 验证异常路径回执不丢失（每轮都应收到 DatabaseException 而非
  /// null/超时）、关库与游标回收不互相干扰。
  Future<void> _runPressureCheck() async {
    if (_pressureItem.state == _VerifyState.running) {
      return;
    }
    _setStatus(_pressureItem, _VerifyState.running, '正在执行压力循环...');
    const rounds = 30;
    final buffer = <String>[];
    final dbPath = await _newDbPath('insp_press');
    final sw = Stopwatch()..start();
    var successRounds = 0;
    var errorReplyRounds = 0;
    try {
      await databaseFactory.deleteDatabase(dbPath);
      for (var i = 0; i < rounds; i++) {
        var failed = false;
        final db = await databaseFactory.openDatabase(dbPath);
        try {
          if (i == 0) {
            await db.execute('CREATE TABLE Test (id INTEGER PRIMARY KEY, v TEXT)');
          }
          final batch = db.batch();
          for (var j = 0; j < 50; j++) {
            batch.insert('Test', {'id': i * 50 + j + 1, 'v': 'v$i-$j'});
          }
          await batch.commit(noResult: true);

          final count = _firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM Test'),
          );
          if (count != (i + 1) * 50) {
            failed = true;
            buffer.add('第 $i 轮 COUNT 异常：$count（预期 ${(i + 1) * 50}）');
          }

          // 异常查询：应收到 DatabaseException（修复前该路径存在空回复风险）
          try {
            await db.rawQuery('SELECT * FROM NotExistTable');
            failed = true;
            buffer.add('第 $i 轮异常查询竟然成功');
          } on DatabaseException {
            errorReplyRounds++;
          } catch (e) {
            failed = true;
            buffer.add('第 $i 轮异常查询收到非预期错误：$e');
          }

          // 建游标不消费（触发关库时游标回收路径）
          await db.rawQueryCursor(
            'SELECT * FROM Test',
            <Object?>[],
            bufferSize: 10,
          );
        } catch (e) {
          failed = true;
          buffer.add('第 $i 轮非预期错误：$e');
        } finally {
          await db.close();
        }
        if (!failed) {
          successRounds++;
        }
      }
      sw.stop();
      await databaseFactory.deleteDatabase(dbPath);
      buffer.insert(0, '$rounds 轮完成：成功 $successRounds 轮，'
          '异常查询收到 DatabaseException $errorReplyRounds 次（预期 $rounds），'
          '耗时 ${sw.elapsedMilliseconds}ms');
      final passed =
          successRounds == rounds && errorReplyRounds == rounds;
      _setStatus(
        _pressureItem,
        passed ? _VerifyState.passed : _VerifyState.failed,
        buffer.join('\n'),
      );
    } catch (e, st) {
      sw.stop();
      _setStatus(
        _pressureItem,
        _VerifyState.failed,
        '${buffer.join('\n')}\n非预期错误：$e\n$st',
      );
    }
  }

  void _setStatus(_VerifyItem item, _VerifyState state, String details) {
    if (!mounted) {
      return;
    }
    setState(() {
      item.state = state;
      item.details = details;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = <_VerifyItem>[
      _cursorLeakItem,
      _detachCleanupItem,
      _paramCheckItem,
      _txnErrorItem,
      _emptyQueryItem,
      _pressureItem,
    ];
    // 防重复触发：单项运行中禁用自身按钮（其余单项仍可独立执行）
    return Scaffold(
      appBar: AppBar(title: const Text('检视问题验证页')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '验证稳定性 / 内存泄露 / 一致性检视修复：游标回收、detach 清理、'
              '参数校验、事务错误契约、零行查询、边界压力。'
              '泄漏量与时序佐证请配合 hilog / DevEco Profiler 观察。',
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildItemCard(
                  item: items[i],
                  onPressed: items[i].state == _VerifyState.running
                      ? null
                      : _onPressedFor(i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  VoidCallback? _onPressedFor(int index) {
    switch (index) {
      case 0:
        return _runCursorLeakCheck;
      case 1:
        return _runDetachCleanupCheck;
      case 2:
        return _runParamCheck;
      case 3:
        return _runTxnErrorCheck;
      case 4:
        return _runEmptyQueryCheck;
      case 5:
        return _runPressureCheck;
    }
    return null;
  }

  Widget _buildItemCard({
    required _VerifyItem item,
    required VoidCallback? onPressed,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('预期结果：${item.expected}'),
            const SizedBox(height: 8),
            Text(
              '当前状态：${_labelForState(item.state)}',
              style: TextStyle(
                color: _colorForState(item.state),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onPressed,
              child: const Text('执行本项校验'),
            ),
            const SizedBox(height: 12),
            SelectableText(item.details),
          ],
        ),
      ),
    );
  }

  String _labelForState(_VerifyState state) {
    switch (state) {
      case _VerifyState.idle:
        return '未执行';
      case _VerifyState.running:
        return '执行中';
      case _VerifyState.passed:
        return '通过';
      case _VerifyState.failed:
        return '失败';
    }
  }

  Color _colorForState(_VerifyState state) {
    switch (state) {
      case _VerifyState.idle:
        return Colors.grey;
      case _VerifyState.running:
        return Colors.blue;
      case _VerifyState.passed:
        return Colors.green;
      case _VerifyState.failed:
        return Colors.red;
    }
  }
}
