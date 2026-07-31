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

// 大结果集查询验证 -- 复现 issue #75
//
// 背景：OHOS 上查询返回数据量特别大时，旧实现（TaskPool 路径，已在提交 6c42dd2 删除）
// 会因 taskPool 序列化限制（16MB）导致返回失败。提交 6c42dd2 把 query 搬到自管理
// worker 线程（ArrayBuffer transfer + postMessage），绕过序列化限制，本页验证大
// 结果集查询能否正常返回。
//
// 做法：
//  1) 灌入大量宽行（payload ≈ 1KB），默认 10 万行 ≈ 100MB，放大单次返回体积。
//  2) 对照两种查询：
//     * 普通一次性 rawQuery('SELECT * FROM Big') —— 把整个结果集一次性拉回。
//       修改前在此撞序列化限制报错；修改后应成功。
//     * rawQueryCursor('SELECT * FROM Big', bufferSize: B) —— 分页拉取。
//       每页体积小，修改前后都应能工作，作为”正确做法”的对照基线。
//
// 若设备上普通查询仍报序列化失败，即复现 issue #75，记录错误信息。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_example/database/database.dart';

/// Big query test route name.
const String testBigQueryRoute = '/test/bigquery';

/// 单次查询结果。
class _QueryResult {
  _QueryResult(this.label);

  final String label;
  bool running = false;
  bool? success; // null=未跑
  int? rows;
  int? elapsedMs;
  String? error;
}

/// Big query test page.
class BigQueryTestPage extends StatefulWidget {
  /// Big query test page.
  const BigQueryTestPage({Key? key}) : super(key: key);

  @override
  State<BigQueryTestPage> createState() => _BigQueryTestPageState();
}

class _BigQueryTestPageState extends State<BigQueryTestPage> {
  // ---- 可配置参数 ----
  int _total = 100000; // 总行数
  int _cursorBufferSize = 1000; // 游标分页大小
  static const int _bytesPerRow = 1024; // payload 字符串长度（单行约 1KB）

  // ---- 运行状态 ----
  bool _running = false;
  int _inserted = 0;
  String? _errorText;
  String? _phase; // 'seeding' / 'plainQuery' / 'cursorQuery'

  // 两种查询的结果
  final _QueryResult _plain = _QueryResult('普通一次性 rawQuery');
  final _QueryResult _cursor = _QueryResult('游标分页 rawQueryCursor');

  // 预设
  static const List<int> _totalPresets = [100000, 200000];
  static const List<int> _bufferPresets = [1000, 5000];

  static const _tag = '[SQFLITE-BIGQUERY]';

  void _log(String msg) {
    // ignore: avoid_print
    print('$_tag $msg');
  }

  // ---- 执行 ----
  Future<void> _run() async {
    setState(() {
      _running = true;
      _inserted = 0;
      _errorText = null;
      _phase = 'seeding';
      _plain
        ..running = false
        ..success = null
        ..rows = null
        ..elapsedMs = null
        ..error = null;
      _cursor
        ..running = false
        ..success = null
        ..rows = null
        ..elapsedMs = null
        ..error = null;
    });

    _log('START total=$_total cursorBufferSize=$_cursorBufferSize '
        'bytesPerRow=$_bytesPerRow (~${(_total * _bytesPerRow / 1024 / 1024).toStringAsFixed(1)}MB)');

    final payload = 'x' * _bytesPerRow;
    const batchSize = 5000;

    try {
      final path = await initDeleteDb('big_query_test.db');
      final db = await openDatabase(path);
      await db.execute(
        'CREATE TABLE Big (id INTEGER PRIMARY KEY, name TEXT, value INTEGER, payload TEXT)',
      );

      try {
        // 1) 灌入宽行
        final swSeed = Stopwatch()..start();
        await db.transaction((txn) async {
          for (var start = 0; start < _total; start += batchSize) {
            final end = math.min(start + batchSize, _total);
            final batch = txn.batch();
            for (var i = start; i < end; i++) {
              batch.rawInsert(
                'INSERT INTO Big (name, value, payload) VALUES (?, ?, ?)',
                ['item $i', i, payload],
              );
            }
            await batch.commit(noResult: true);
            if (mounted) {
              setState(() => _inserted = end);
            }
            _log('seeded end=$end elapsedMs=${swSeed.elapsedMilliseconds}');
          }
        });
        swSeed.stop();
        _log('seed DONE rows=$_inserted elapsedMs=${swSeed.elapsedMilliseconds}');

        // 2) 普通一次性查询
        setState(() {
          _phase = 'plainQuery';
          _plain.running = true;
        });
        _log('plain rawQuery start (全表 $_total 行一次性拉回)');
        final swPlain = Stopwatch()..start();
        try {
          final rows = await db.rawQuery('SELECT * FROM Big');
          swPlain.stop();
          _plain
            ..running = false
            ..success = true
            ..rows = rows.length
            ..elapsedMs = swPlain.elapsedMilliseconds;
          _log('plain rawQuery OK rows=${rows.length} '
              'elapsedMs=${swPlain.elapsedMilliseconds}');
        } catch (e, st) {
          swPlain.stop();
          _plain
            ..running = false
            ..success = false
            ..elapsedMs = swPlain.elapsedMilliseconds
            ..error = '$e\n$st';
          _log('plain rawQuery FAIL elapsedMs=${swPlain.elapsedMilliseconds}: $e');
        }

        // 3) 游标分页查询
        if (mounted) {
          setState(() {
            _phase = 'cursorQuery';
            _cursor.running = true;
          });
        }
        _log('cursor rawQueryCursor start (bufferSize=$_cursorBufferSize)');
        final swCursor = Stopwatch()..start();
        try {
          final cursor = await db.rawQueryCursor(
            'SELECT * FROM Big',
            <Object?>[],
            bufferSize: _cursorBufferSize,
          );
          var count = 0;
          // moveNext 到末尾返回 false 时 cursor 自动 close；
          // 中途异常走 catch 手动 close。
          try {
            while (await cursor.moveNext()) {
              count++;
            }
          } finally {
            await cursor.close();
          }
          swCursor.stop();
          _cursor
            ..running = false
            ..success = true
            ..rows = count
            ..elapsedMs = swCursor.elapsedMilliseconds;
          _log('cursor rawQueryCursor OK rows=$count '
              'elapsedMs=${swCursor.elapsedMilliseconds}');
        } catch (e, st) {
          swCursor.stop();
          _cursor
            ..running = false
            ..success = false
            ..elapsedMs = swCursor.elapsedMilliseconds
            ..error = '$e\n$st';
          _log('cursor rawQueryCursor FAIL '
              'elapsedMs=${swCursor.elapsedMilliseconds}: $e');
        }
      } finally {
        await db.close();
      }

      _log('DONE inserted=$_inserted '
          'plain=${_plain.success == true ? "OK(${_plain.rows})" : "FAIL"} '
          'cursor=${_cursor.success == true ? "OK(${_cursor.rows})" : "FAIL"}');
      if (mounted) {
        setState(() {
          _running = false;
          _phase = null;
        });
      }
    } catch (e, st) {
      _log('CRASH/ERROR phase=$_phase: $e');
      _errorText = '$e\n$st';
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('大结果集查询 (#75)')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _configCard(),
          const SizedBox(height: 12),
          _progressCard(),
          const SizedBox(height: 12),
          _resultCard(_plain),
          const SizedBox(height: 12),
          _resultCard(_cursor),
          const SizedBox(height: 12),
          _conclusionCard(),
          const SizedBox(height: 12),
          if (_errorText != null) _errorCard(),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _running ? null : _run,
                  child: Text(_running
                      ? '${_phase ?? '运行中'}…'
                      : '灌入 ${_formatCount(_total)} 行并查询'),
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
            Text('总行数（每行 payload ≈ ${_bytesPerRow}B，'
                '约 ${(_total * _bytesPerRow / 1024 / 1024).toStringAsFixed(1)}MB）'),
            Wrap(
              spacing: 8,
              children: _totalPresets
                  .map((n) => ChoiceChip(
                        label: Text(_formatCount(n)),
                        selected: _total == n,
                        onSelected: _running
                            ? null
                            : (_) => setState(() => _total = n),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            const Text('游标分页 bufferSize'),
            Wrap(
              spacing: 8,
              children: _bufferPresets
                  .map((n) => ChoiceChip(
                        label: Text('$n'),
                        selected: _cursorBufferSize == n,
                        onSelected: _running
                            ? null
                            : (_) => setState(() => _cursorBufferSize = n),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressCard() {
    if (!_running && _inserted == 0 && _plain.success == null && _cursor.success == null) {
      return const SizedBox.shrink();
    }
    final progress = _total > 0 ? _inserted / _total : 0.0;
    final phaseText = () {
      switch (_phase) {
        case 'seeding':
          return '灌入数据 ${_formatCount(_inserted)}/${_formatCount(_total)}';
        case 'plainQuery':
          return '普通一次性查询中…';
        case 'cursorQuery':
          return '游标分页查询中…';
        default:
          return '完成';
      }
    }();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(phaseText),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _phase == 'seeding' ? progress : null),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(_QueryResult r) {
    final started = r.running || r.success != null;
    if (!started) return const SizedBox.shrink();
    final color = r.running
        ? Colors.blue.shade50
        : (r.success == true ? Colors.green.shade50 : Colors.red.shade50);
    final titleColor = r.running
        ? Colors.blue
        : (r.success == true ? Colors.green : Colors.red);
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.label,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: titleColor)),
            const SizedBox(height: 4),
            if (r.running) const Text('进行中…'),
            if (!r.running && r.success == true)
              Text('成功：返回 ${_formatCount(r.rows ?? 0)} 行，'
                  '耗时 ${r.elapsedMs ?? 0} ms'),
            if (!r.running && r.success == false) ...[
              Text('失败：耗时 ${r.elapsedMs ?? 0} ms',
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 4),
              SelectableText(r.error ?? '',
                  style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _conclusionCard() {
    if (_plain.success == null && _cursor.success == null) {
      return const SizedBox.shrink();
    }
    final plainOk = _plain.success == true;
    final cursorOk = _cursor.success == true;
    String text;
    if (plainOk && cursorOk) {
      text = '两者均成功：大结果集查询在本版本可正常返回（普通一次性 + 游标分页都 OK）。';
    } else if (!plainOk && cursorOk) {
      text = '普通查询失败、游标分页成功：即 issue #75 现象--一次性拉大结果集受传输限制'
          '失败，改用 rawQueryCursor 分页可绕过。';
    } else if (plainOk && !cursorOk) {
      text = '普通查询成功、游标分页失败：游标路径异常，需排查 queryCursorNext。';
    } else {
      text = '两者均失败：查询路径整体异常。';
    }
    return Card(
      color: Theme.of(context).dividerColor.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('结论', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(text),
            const SizedBox(height: 4),
            const Text(
              '# 提示：在 6c42dd2 之前的版本（TaskPool 路径）上跑普通查询应失败；'
              '在 6c42dd2 及之后（worker 线程路径）上应成功。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() {
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

  String _formatCount(int n) {
    if (n >= 10000) {
      final w = n / 10000;
      return '${w.toStringAsFixed(w == w.roundToDouble() ? 0 : 1)}万';
    }
    return '$n';
  }
}
