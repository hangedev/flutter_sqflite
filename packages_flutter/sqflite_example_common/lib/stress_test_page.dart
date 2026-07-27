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

// 大数据插入压力测试 —— 复现 issue #45 / #65 / DTS2026070854160
//
// 目标：把 sqflite OHOS 在“插入大量数据”时的当前表现可视化出来：
//  - 插入进度、累计耗时、吞吐（rows/s）
//  - 掉帧监控（单帧最长耗时 + 累计丢帧估算）：用 SchedulerBinding 的 timings 回调
//  - 一个常驻旋转指示器，肉眼可见卡顿
//  - 两种提交策略对照：
//      * chunked 分批提交（issue 中 5000 条/组的做法）
//      * single 单次大 batch（最易触发 SharedBlock 满 / 内存堆积 / 崩溃）
//
// 说明：本页所有插入在 Dart 主 isolate 执行（与 issue 复现场景一致）。
// 真正的修复方向是把 native 平台线程上的 db 操作搬到 TaskPool worker，
// 修复后此处“单帧最长耗时 / 是否崩溃”应明显改善，可用于前后对比。
//
// 注意：当前分支 br_v2.4.2_ohos_dev 的 OHOS native channel 仍在主线程处理
// （SqflitePlugin.onMethodCall -> async handleXxxCall -> await Database.execute），
// 未移植 dev 的 SqfliteWorker.ets worker 线程修复。因此本页在 OHOS 上预期会
// 复现掉帧/卡顿/THREAD_BLOCK_6S appfreeze；在 Android/desktop 上表现正常，
// 可作为跨平台对照基线。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sqflite_common/sqflite.dart';

import 'test_page.dart';

/// Stress test route name.
const String testStressRoute = '/test/stress';

/// Insert strategy.
enum StressStrategy {
  /// 分批提交：按 batchSize 切片，每片一个 batch.commit。
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

class _StressTestPageState extends State<StressTestPage>
    with SingleTickerProviderStateMixin {
  // ---- 可配置参数 ----
  int _total = 100000; // 总行数（默认 10 万，可上调到 50 万+ 复现崩溃）
  int _batchSize = 5000; // 单批大小（issue 中 5000/组）
  bool _useTransaction = true; // 是否包裹在单个事务里
  StressStrategy _strategy = StressStrategy.chunked;

  // ---- 运行状态 ----
  bool _running = false;
  int _inserted = 0;
  Stopwatch? _sw;
  String? _errorText;

  // ---- 掉帧监控 ----
  double _worstFrameMs = 0;
  int _droppedFrames = 0;
  late final Ticker _ticker;
  bool _tickerStarted = false;
  Duration _lastFrameTime = Duration.zero;

  // 用于“肉眼可见卡顿”的旋转动画
  late final AnimationController _spin;

  // 预设行数快捷按钮
  static const List<int> _totalPresets = [10000, 100000, 500000, 1000000];
  static const List<int> _batchPresets = [1000, 5000, 10000];

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _ticker = Ticker(_onTick);
  }

  @override
  void dispose() {
    _stopFrameMonitor();
    _spin.dispose();
    _ticker.dispose();
    super.dispose();
  }

  // Ticker：每帧记录帧间隔（>16.6ms 视为掉帧），同时驱动肉眼可见的计数刷新。
  void _onTick(Duration elapsed) {
    final now = elapsed;
    if (_lastFrameTime != Duration.zero) {
      final deltaMs = (now - _lastFrameTime).inMicroseconds / 1000.0;
      if (_running && deltaMs > 16.6) {
        if (deltaMs > _worstFrameMs) {
          _worstFrameMs = deltaMs;
        }
        _droppedFrames += ((deltaMs - 16.6) / 16.6).round();
      }
    }
    _lastFrameTime = now;
    if (_running && mounted) {
      setState(() {});
    }
  }

  void _startFrameMonitor() {
    _worstFrameMs = 0;
    _droppedFrames = 0;
    _lastFrameTime = Duration.zero;
    if (!_tickerStarted) {
      _ticker.start();
      _tickerStarted = true;
    }
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _stopFrameMonitor() {
    if (_tickerStarted) {
      _ticker.stop();
      _tickerStarted = false;
    }
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  // 系统级帧计时（build+raster），用于补强 Ticker 的估算。
  void _onTimings(List<FrameTiming> timings) {
    if (!_running) return;
    for (final t in timings) {
      final ms = t.totalSpan.inMicroseconds / 1000.0;
      if (ms > _worstFrameMs) {
        _worstFrameMs = ms;
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  // 统一的日志前缀，方便在 hdc hilog 里 grep。
  static const _tag = '[SQFLITE-STRESS]';

  void _log(String msg) {
    // ignore: avoid_print
    print('$_tag $msg');
  }

  // ---- 执行插入 ----
  Future<void> _run() async {
    setState(() {
      _running = true;
      _inserted = 0;
      _errorText = null;
    });
    _startFrameMonitor();
    _sw = Stopwatch()..start();

    _log('START total=$_total batchSize=$_batchSize '
        'strategy=${_strategy.name} txn=$_useTransaction');

    try {
      final path = await initDeleteDb('stress_test.db');
      final db = await openDatabase(path);
      await db.execute(
        'CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT, value INTEGER)',
      );

      try {
        if (_strategy == StressStrategy.single) {
          await _runSingleCommit(db);
        } else {
          await _runChunkedCommit(db);
        }
      } finally {
        await db.close();
      }

      _sw!.stop();
      _log('DONE inserted=$_inserted elapsedMs=${_sw!.elapsedMilliseconds} '
          'throughput=${_sw!.elapsedMilliseconds > 0 ? (_inserted * 1000 / _sw!.elapsedMilliseconds).toStringAsFixed(0) : 0}rows/s '
          'worstFrameMs=${_worstFrameMs.toStringAsFixed(1)} droppedFrames=$_droppedFrames');
      if (mounted) {
        setState(() => _running = false);
      }
    } catch (e, st) {
      _sw?.stop();
      _log('CRASH/ERROR inserted=$_inserted elapsedMs=${_sw?.elapsedMilliseconds} : $e');
      _errorText = '$e\n$st';
      if (mounted) {
        setState(() => _running = false);
      }
    } finally {
      _stopFrameMonitor();
    }
  }

  // 分批提交：把 _total 按 _batchSize 切片，每片一个 batch，可选事务包裹。
  Future<void> _runChunkedCommit(Database db) async {
    Future<void> insertChunk(int start, int end) async {
      final batch = db.batch();
      for (var i = start; i < end; i++) {
        batch.rawInsert(
          'INSERT INTO Test (name, value) VALUES (?, ?)',
          ['item $i', i],
        );
      }
      await batch.commit(noResult: true);
      _log('chunk committed end=$end '
          'elapsedMs=${_sw?.elapsedMilliseconds ?? 0} '
          'worstFrameMs=${_worstFrameMs.toStringAsFixed(1)} droppedFrames=$_droppedFrames');
      if (mounted) {
        setState(() => _inserted = end);
      }
    }

    if (_useTransaction) {
      await db.transaction((txn) async {
        for (var start = 0; start < _total; start += _batchSize) {
          final end = math.min(start + _batchSize, _total);
          // 事务内不能用 db.batch()，需要用 txn.batch()
          final batch = txn.batch();
          for (var i = start; i < end; i++) {
            batch.rawInsert(
              'INSERT INTO Test (name, value) VALUES (?, ?)',
              ['item $i', i],
            );
          }
          await batch.commit(noResult: true);
          _log('chunk committed(txn) end=$end '
              'elapsedMs=${_sw?.elapsedMilliseconds ?? 0} '
              'worstFrameMs=${_worstFrameMs.toStringAsFixed(1)} droppedFrames=$_droppedFrames');
          if (mounted) {
            setState(() => _inserted = end);
          }
        }
      });
    } else {
      for (var start = 0; start < _total; start += _batchSize) {
        final end = math.min(start + _batchSize, _total);
        await insertChunk(start, end);
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
          'elapsedMs=${_sw?.elapsedMilliseconds ?? 0} '
          'worstFrameMs=${_worstFrameMs.toStringAsFixed(1)} droppedFrames=$_droppedFrames');
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
    final progress = _total > 0 ? _inserted / _total : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('大数据插入压力测试 (#45/#65)')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _configCard(),
          const SizedBox(height: 12),
          _metricCard(progress, throughput, elapsedMs),
          const SizedBox(height: 12),
          _resultCard(throughput, elapsedMs),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _running ? null : _run,
                  child: Text(_running ? '插入中…' : '开始插入 $_total 行'),
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
                          : (_) => setState(() => _total = n),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            const Text('单批大小'),
            Wrap(
              spacing: 8,
              children: _batchPresets
                  .map(
                    (n) => ChoiceChip(
                      label: Text(_formatCount(n)),
                      selected: _batchSize == n,
                      onSelected: _running
                          ? null
                          : (_) => setState(() => _batchSize = n),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: [
                ChoiceChip(
                  label: const Text('分批提交'),
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

  Widget _metricCard(double progress, String throughput, int elapsedMs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 肉眼可见卡顿：旋转指示器
                RotationTransition(
                  turns: _spin,
                  child: const Icon(Icons.refresh, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(value: progress),
                ),
                const SizedBox(width: 12),
                Text('${(progress * 100).toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(),
              },
              children: [
                _row('已插入', '${_formatCount(_inserted)} / ${_formatCount(_total)}'),
                _row('耗时', _formatDuration(elapsedMs)),
                _row('吞吐', '$throughput rows/s'),
                _row(
                  '单帧最长',
                  '${_worstFrameMs.toStringAsFixed(1)} ms'
                  ' ${_worstFrameMs > 100 ? "⚠️严重卡顿" : (_worstFrameMs > 33 ? "⚠卡顿" : "")}',
                ),
                _row(
                  '累计丢帧(估)',
                  '$_droppedFrames'
                  ' ${_droppedFrames > 30 ? "⚠️" : ""}',
                ),
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
          '吞吐 $throughput rows/s，单帧最长 ${_worstFrameMs.toStringAsFixed(1)} ms，'
          '累计丢帧 $_droppedFrames。',
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
