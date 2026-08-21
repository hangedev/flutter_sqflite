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

// 大数据插入压力测试 —— 复现 issue #65 / DTS2026070854160
//
// 目标：验证 sqflite OHOS 在”插入大量数据”时是否触发 THREAD_BLOCK_6S appfreeze。
//  - 累计耗时、吞吐（rows/s）
//  - 两种提交策略对照：
//      * chunked 分批提交（每 5000 条一个 batch.commit）
//      * single 单次大 batch（最易触发 SharedBlock 满 / 内存堆积 / 崩溃）
//
// 说明：本页所有插入在 Dart 主 isolate 执行。worker 线程修复后此页不再触发
// appfreeze，可用于前后对比验证。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sqflite_common/sqflite.dart';

/// Stress test route name.
const String testStressRoute = '/test/stress';

/// Insert strategy.
enum StressStrategy {
  /// 分批提交：每 5000 条一个 batch.commit。
  chunked,

  /// 单次大 batch：所有行放进一个 batch，一次 commit。
  single,
}

/// Stress test page.
class StressTestPage extends StatefulWidget {
  /// Stress test page.
  const StressTestPage({Key? key}) : super(key: key);

  @override
  State<StressTestPage> createState() => _StressTestPageState();
}

class _StressTestPageState extends State<StressTestPage> {
  // ---- 可配置参数 ----
  int _total = 500000; // 总行数（默认 50 万）
  bool _useTransaction = true; // 是否包裹在单个事务里
  StressStrategy _strategy = StressStrategy.chunked;
  static const int _batchSize = 5000; // 分批提交的单批大小

  // ---- 运行状态 ----
  bool _running = false;
  int _inserted = 0;
  Stopwatch? _sw;
  String? _errorText;

  // 并发安全：每次点击生成独立库文件，避免“开始插入 + 返回上一页 + 再开始”
  // 时多轮 _run() 共享同一个 stress_test.db（默认 singleInstance 会在 native
  // 复用同一 RdbStore），导致 deleteDatabase / openDatabase / CREATE TABLE 互相竞争。
  int _runSeq = 0;
  Database? _db;
  bool _disposed = false;

  // 预设行数快捷按钮
  static const List<int> _totalPresets = [500000, 1000000];

  // 日志前缀，方便在 hdc hilog 里 grep。
  static const _tag = '[SQFLITE-STRESS]';

  void _log(String msg) {
    // ignore: avoid_print
    print('$_tag $msg');
  }

  @override
  void dispose() {
    _disposed = true;
    // 页面被弹出时立即关库，终止仍在后台的插入，避免与下一次点击的
    // _run() 同时操作同一个库文件。
    final db = _db;
    _db = null;
    if (db != null) {
      db.close().catchError((_) {});
    }
    super.dispose();
  }

  // ---- 执行插入 ----
  Future<void> _run() async {
    setState(() {
      _running = true;
      _inserted = 0;
      _errorText = null;
    });
    _sw = Stopwatch()..start();

    // 每次运行使用独立库文件，天然隔离多轮并发，无需再 initDeleteDb。
    final path = 'stress_test_${DateTime.now().microsecondsSinceEpoch}_$_runSeq.db';
    _runSeq++;
    _log('START total=$_total strategy=${_strategy.name} txn=$_useTransaction path=$path');

    Database? db;
    try {
      db = await openDatabase(path);
      _db = db;
      if (_disposed) return;

      await db.execute(
        'CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT, value INTEGER)',
      );
      if (_disposed) return;

      if (_strategy == StressStrategy.chunked) {
        await _runChunkedCommit(db);
      } else {
        await _runSingleCommit(db);
      }

      _sw!.stop();
      _log('DONE inserted=$_inserted elapsedMs=${_sw!.elapsedMilliseconds} '
          'throughput=${_sw!.elapsedMilliseconds > 0 ? (_inserted * 1000 / _sw!.elapsedMilliseconds).toStringAsFixed(0) : 0}rows/s');
      if (mounted) {
        setState(() => _running = false);
      }
    } catch (e, st) {
      _sw?.stop();
      if (_disposed) {
        // 返回上一页导致的后台插入中断，不是被测插件的崩溃。
        _log('CANCELLED (page disposed) inserted=$_inserted '
            'elapsedMs=${_sw?.elapsedMilliseconds} : $e');
      } else {
        _log('CRASH/ERROR inserted=$_inserted '
            'elapsedMs=${_sw?.elapsedMilliseconds} : $e');
        if (mounted) {
          setState(() {
            _errorText = '$e\n$st';
            _running = false;
          });
        }
      }
    } finally {
      _db = null;
      // 统一关库（dispose 已关则忽略异常），再清理本次库文件。
      if (db != null) {
        try {
          await db.close();
        } catch (_) {
          // ignore: dispose 已关闭或已损坏
        }
      }
      try {
        await deleteDatabase(path);
      } catch (_) {
        // 清理失败（如文件仍被占用）不影响测试结论。
      }
    }
  }

  // 分批提交：每 _batchSize 条一个 batch，可选事务包裹。
  Future<void> _runChunkedCommit(Database db) async {
    if (_useTransaction) {
      await db.transaction((txn) async {
        for (var start = 0; start < _total; start += _batchSize) {
          final end = math.min(start + _batchSize, _total);
          final batch = txn.batch();
          for (var i = start; i < end; i++) {
            batch.rawInsert(
              'INSERT INTO Test (name, value) VALUES (?, ?)',
              ['item $i', i],
            );
          }
          await batch.commit(noResult: true);
          _log('chunk committed(txn) end=$end '
              'elapsedMs=${_sw?.elapsedMilliseconds ?? 0}');
          if (mounted) {
            setState(() => _inserted = end);
          }
        }
      });
    } else {
      for (var start = 0; start < _total; start += _batchSize) {
        final end = math.min(start + _batchSize, _total);
        final batch = db.batch();
        for (var i = start; i < end; i++) {
          batch.rawInsert(
            'INSERT INTO Test (name, value) VALUES (?, ?)',
            ['item $i', i],
          );
        }
        await batch.commit(noResult: true);
        _log('chunk committed end=$end '
            'elapsedMs=${_sw?.elapsedMilliseconds ?? 0}');
        if (mounted) {
          setState(() => _inserted = end);
        }
      }
    }
  }

  // 单次大 batch：所有行一次 commit，最容易触发 SharedBlock 满 / 内存堆积。
  Future<void> _runSingleCommit(Database db) async {
    Future<void> fillAndCommit(Batch batch, int start, int end) async {
      for (var i = start; i < end; i++) {
        batch.rawInsert(
          'INSERT INTO Test (name, value) VALUES (?, ?)',
          ['item $i', i],
        );
      }
      await batch.commit(noResult: true);
      _log('single-commit end=$end '
          'elapsedMs=${_sw?.elapsedMilliseconds ?? 0}');
      if (mounted) {
        setState(() => _inserted = math.max(_inserted, end));
      }
    }

    if (_useTransaction) {
      await db.transaction((txn) async {
        await fillAndCommit(txn.batch(), 0, _total);
      });
    } else {
      await fillAndCommit(db.batch(), 0, _total);
    }
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    final elapsedMs = _sw?.elapsedMilliseconds ?? 0;
    final throughput =
        elapsedMs > 0 ? (_inserted * 1000 / elapsedMs).toStringAsFixed(0) : '0';

    return Scaffold(
      appBar: AppBar(title: const Text('大数据插入压力测试 (#65)')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _configCard(),
          const SizedBox(height: 12),
          _metricCard(throughput, elapsedMs),
          const SizedBox(height: 12),
          _resultCard(throughput, elapsedMs),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _running ? null : _run,
                  child: Text(_running ? '插入中…' : '开始插入 ${_formatCount(_total)} 行'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _configCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('配置', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('总行数'),
            Wrap(
              spacing: 8,
              children: _totalPresets
                  .map(
                    (n) => ChoiceChip(
                      label: Text(_formatCount(n)),
                      selected: _total == n,
                      onSelected: _running
                          ? null
                          : (_) => setState(() {
                                _total = n;
                                _inserted = 0;
                              }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: [
                ChoiceChip(
                  label: const Text('分批提交(5000)'),
                  selected: _strategy == StressStrategy.chunked,
                  onSelected: _running
                      ? null
                      : (_) =>
                          setState(() => _strategy = StressStrategy.chunked),
                ),
                ChoiceChip(
                  label: const Text('单次大batch'),
                  selected: _strategy == StressStrategy.single,
                  onSelected: _running
                      ? null
                      : (_) =>
                          setState(() => _strategy = StressStrategy.single),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('包裹在单个事务'),
              value: _useTransaction,
              onChanged:
                  _running ? null : (v) => setState(() => _useTransaction = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(String throughput, int elapsedMs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(),
              },
              children: [
                _row('已插入', '${_formatCount(_inserted)} / ${_formatCount(_total)}'),
                _row('耗时', _formatDuration(elapsedMs)),
                _row('吞吐', '$throughput rows/s'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(String throughput, int elapsedMs) {
    if (_errorText != null) {
      return Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('出错 / 崩溃',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 4),
              SelectableText(_errorText!),
            ],
          ),
        ),
      );
    }
    if (_running) {
      return const SizedBox.shrink();
    }
    if (_inserted == 0) {
      return const SizedBox.shrink();
    }
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          '完成：${_formatCount(_inserted)} 行，耗时 ${_formatDuration(elapsedMs)}，'
          '吞吐 $throughput rows/s。',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  TableRow _row(String label, String value) {
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(label, style: const TextStyle(color: Colors.grey)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(value),
      ),
    ]);
  }

  String _formatCount(int n) {
    if (n >= 10000) {
      final w = n / 10000;
      return '${w.toStringAsFixed(w == w.roundToDouble() ? 0 : 1)}万';
    }
    return '$n';
  }

  String _formatDuration(int ms) {
    final s = ms / 1000.0;
    if (s < 60) return '${s.toStringAsFixed(1)} s';
    final m = (s / 60).floor();
    final rest = s - m * 60;
    return '$m:${rest.toStringAsFixed(1).padLeft(4, '0')}';
  }
}
