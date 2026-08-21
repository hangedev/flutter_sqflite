/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

/// 事务功能验收测试页。
///
/// 验证 OHOS 平台事务命令（BEGIN/COMMIT/ROLLBACK TRANSACTION）是否正常工作。
/// 每个用例自包含、互不干扰，点"运行"后直接给出【通过/未通过】判定，
/// 并展示"期望 vs 实际"对照，方便测试人员一眼对比。
class TransactionReproPage extends StatefulWidget {
  /// 验收测试页。
  const TransactionReproPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _TransactionReproPageState createState() => _TransactionReproPageState();
}

/// 单个用例的运行结果。
class _CaseResult {
  _CaseResult({this.passed, this.detail});

  /// null = 未运行；true = 通过；false = 未通过
  final bool? passed;
  /// 人类可读的实际结果描述（含期望 vs 实际）
  final String? detail;
}

/// 日志条目级别。
enum _LogLevel { info, ok, err }

class _TransactionReproPageState extends State<TransactionReproPage> {
  /// 三个用例的运行结果，按 index 存取。
  final List<_CaseResult> _results =
      List<_CaseResult>.generate(3, (_) => _CaseResult(), growable: false);

  /// 每个用例独立的内存库实例（隔离，避免相互污染/残留事务）。
  final List<Database?> _dbs = List<Database?>.filled(3, null, growable: false);

  /// 每个用例是否正在运行（防止连点导致并发竞态）。
  final List<bool> _running = List<bool>.filled(3, false, growable: false);

  final List<String> _logs = [];

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    for (final db in _dbs) {
      // close 返回 Future，dispose 是同步方法，用 unawaited 避免挂起与 lint 警告。
      unawaited(db?.close());
    }
    super.dispose();
  }

  /// 打开（或复用）某用例的内存库。每次运行前都会重开，保证干净。
  Future<Database> _freshDb(int caseIndex) async {
    final old = _dbs[caseIndex];
    _dbs[caseIndex] = null;
    await old?.close();
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT)');
      },
    );
    await db.execute('DELETE FROM Test');
    // await 期间页面可能已被销毁：把新库交给 dispose 负责 close，这里不保留引用。
    if (_disposed) {
      unawaited(db.close());
    } else {
      _dbs[caseIndex] = db;
    }
    return db;
  }

  Future<int> _count(Database db) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM Test')) ??
      0;

  void _log(String message, {_LogLevel level = _LogLevel.info}) {
    final prefix = level == _LogLevel.ok
        ? '✅'
        : (level == _LogLevel.err ? '❌' : '•');
    final line = '[TransactionRepro] $prefix $message';
    debugPrint(line);
    if (!mounted) return;
    setState(() => _logs.add('$prefix $message'));
  }

  void _setResult(int caseIndex, bool passed, String detail) {
    if (!mounted || _disposed) return;
    setState(() {
      _results[caseIndex] = _CaseResult(passed: passed, detail: detail);
    });
  }

  // ───────────────────────── 用例 1：事务提交 ─────────────────────────

  Future<void> _runCase1() => _guarded(0, _doCase1);

  Future<void> _doCase1(String name) async {
    final db = await _freshDb(0);
    final before = await _count(db);
    _log('$name | 起始行数 $before');
    _log('$name | 步骤1: BEGIN TRANSACTION');
    await db.execute('BEGIN TRANSACTION');
    _log('$name | 步骤2: INSERT INTO Test (name) VALUES (?)');
    await db.execute('INSERT INTO Test (name) VALUES (?)', ['row1']);
    _log('$name | 步骤3: COMMIT TRANSACTION');
    await db.execute('COMMIT TRANSACTION');
    final after = await _count(db);
    final delta = after - before;
    final passed = delta == 1;
    final detail = '期望：无异常，行数 +1\n'
        '实际：行数 $before → $after（+$delta），无异常';
    _log('$name | 行数 $before → $after（+$delta）',
        level: passed ? _LogLevel.ok : _LogLevel.err);
    _setResult(0, passed, detail);
  }

  // ───────────────────────── 用例 2：事务回滚 ─────────────────────────

  Future<void> _runCase2() => _guarded(1, _doCase2);

  Future<void> _doCase2(String name) async {
    final db = await _freshDb(1);
    final before = await _count(db);
    _log('$name | 起始行数 $before');
    _log('$name | 步骤1: BEGIN TRANSACTION');
    await db.execute('BEGIN TRANSACTION');
    _log('$name | 步骤2: INSERT INTO Test (name) VALUES (?)');
    await db.execute('INSERT INTO Test (name) VALUES (?)', ['will-rollback']);
    _log('$name | 步骤3: ROLLBACK TRANSACTION');
    await db.execute('ROLLBACK TRANSACTION');
    final after = await _count(db);
    final passed = after == before;
    final detail = '期望：无异常，回滚后行数不变（=$before）\n'
        '实际：行数 $before → $after，无异常';
    _log('$name | 行数 $before → $after',
        level: passed ? _LogLevel.ok : _LogLevel.err);
    _setResult(1, passed, detail);
  }

  // ───────────────────── 用例 3：drift 批量插入 ─────────────────────

  Future<void> _runCase3() => _guarded(2, _doCase3);

  Future<void> _doCase3(String name) async {
    final db = await _freshDb(2);
    final before = await _count(db);
    _log('$name | 起始行数 $before');
    _log('$name | 步骤1: BEGIN TRANSACTION');
    await db.execute('BEGIN TRANSACTION');
    _log('$name | 步骤2: 批量 INSERT 3 行');
    for (var i = 0; i < 3; i++) {
      await db.execute('INSERT INTO Test (name) VALUES (?)', ['row $i']);
    }
    _log('$name | 步骤3: COMMIT TRANSACTION');
    await db.execute('COMMIT TRANSACTION');
    final after = await _count(db);
    final delta = after - before;
    final passed = delta == 3;
    final detail = '期望：无异常，行数 +3\n'
        '实际：行数 $before → $after（+$delta），无异常';
    _log('$name | 行数 $before → $after（+$delta）',
        level: passed ? _LogLevel.ok : _LogLevel.err);
    _setResult(2, passed, detail);
  }

  /// 统一的运行守卫：防止同一用例被连点导致并发竞态，
  /// 统一捕获异常并写入失败结果，结束时释放运行锁。
  Future<void> _guarded(int caseIndex, Future<void> Function(String) body) async {
    if (_running[caseIndex] || _disposed) return;
    _running[caseIndex] = true;
    if (mounted) setState(() {});
    final name = '用例${caseIndex + 1}';
    try {
      await body(name);
    } catch (e) {
      final detail = '实际：抛出异常 $e';
      _log('$name | 异常: $e', level: _LogLevel.err);
      _setResult(caseIndex, false, detail);
    } finally {
      _running[caseIndex] = false;
      if (mounted) setState(() {});
    }
  }

  /// 三个用例是否都已运行。
  bool get _allRun => _results.every((r) => r.passed != null);

  /// 已运行用例中是否有失败。
  bool get _hasFail => _results.any((r) => r.passed == false);

  /// 已通过用例数。
  int get _passedCount => _results.where((r) => r.passed == true).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('事务功能验收')),
      body: Column(
        children: [
          // 顶部说明
          Container(
            width: double.infinity,
            color: Colors.blue.shade50,
            padding: const EdgeInsets.all(10),
            child: const Text(
              '验证 OHOS 平台事务功能是否正常。点击每个用例的"运行"按钮，'
              '对照"期望"与"实际"判断是否通过。',
              style: TextStyle(fontSize: 12),
            ),
          ),
          // 顶部摘要：有任一用例运行过就显示，但区分"进行中"和"已完成"
          if (_passedCount > 0 || _hasFail) _buildSummary(),
          // 用例列表 + 日志（各自滚动）
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  _buildCase(
                    index: 0,
                    title: '用例 1：事务提交',
                    operation: 'BEGIN TRANSACTION → 插入 1 行 → COMMIT TRANSACTION',
                    expect: '不报错，且提交后行数 +1',
                    run: _runCase1,
                  ),
                  _buildCase(
                    index: 1,
                    title: '用例 2：事务回滚',
                    operation:
                        'BEGIN TRANSACTION → 插入 1 行 → ROLLBACK TRANSACTION',
                    expect: '不报错，且回滚后行数不变',
                    run: _runCase2,
                  ),
                  _buildCase(
                    index: 2,
                    title: '用例 3：批量插入（drift 场景）',
                    operation: 'BEGIN TRANSACTION → 插入 3 行 → COMMIT TRANSACTION',
                    expect: '不报错，且提交后行数 +3',
                    run: _runCase3,
                  ),
                ],
              ),
            ),
          ),
          // 日志标题栏
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('日志', style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () => setState(_logs.clear),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清空'),
                ),
              ],
            ),
          ),
          // 日志区
          Expanded(
            flex: 4,
            child: _buildLogPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final Color color;
    final Color bg;
    final IconData icon;
    final String text;
    if (!_allRun) {
      // 进行中：还没全部跑完，只显示进度，不下结论
      color = Colors.blue;
      bg = const Color(0x1F2196F3);
      icon = Icons.pending_actions;
      text = '测试进行中：已通过 $_passedCount / 3';
    } else if (_hasFail) {
      color = Colors.red;
      bg = const Color(0x1FF44336);
      icon = Icons.error;
      text = '存在未通过用例，请查看下方详情';
    } else {
      color = Colors.green;
      bg = const Color(0x1F4CAF50);
      icon = Icons.check_circle;
      text = '全部通过：事务功能正常';
    }
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _buildCase({
    required int index,
    required String title,
    required String operation,
    required String expect,
    required Future<void> Function() run,
  }) {
    final running = _running[index];
    final result = _results[index];
    final hasRun = result.passed != null;
    final isPass = result.passed == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                if (hasRun)
                  Text(
                    isPass ? '✅ 通过' : '❌ 未通过',
                    style: TextStyle(
                      color: isPass ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _kv('操作', operation),
            _kv('期望', expect),
            if (hasRun) ...[
              const Divider(height: 16),
              Text(result.detail ?? '',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: running ? null : run,
                icon: running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow, size: 18),
                label: Text(running ? '运行中…' : '运行'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '$label：',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          TextSpan(text: value, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _buildLogPanel() {
    if (_logs.isEmpty) {
      return const Center(
        child: Text('点击"运行"按钮查看日志', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final line = _logs[index];
        final color = line.startsWith('❌')
            ? Colors.red
            : (line.startsWith('✅') ? Colors.green : Colors.black87);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(line,
              style: TextStyle(color: color, fontSize: 12, fontFamily: 'monospace')),
        );
      },
    );
  }
}
