/*
 * Copyright (c) 2024 Hunan OpenValley Digital Industry Development Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// ignore_for_file: avoid_print

/// 读写分叉验证页(issue #89):按钮触发 + 屏幕日志流面板。
///
/// 将原断言式回归测试改为可交互 UI:点一个场景按钮,该场景的 insert 返回值、
/// query 行数、物理副本数、PRAGMA 挂载路径等关键证据**实时打印到屏幕日志区**,
/// 验证者一眼看到「能写也能读、落点没分叉」,无需在 IDE 控制台与 UI 间切换。
///
/// 复现目标(缺陷存在时):
/// - 写入后 query 读到 0 行(能写不能读);
/// - 同一 db 名出现 >1 个物理副本(读/写落点分叉);
/// - 关闭重开 / 先读后写 等时序下分叉暴露。
///
/// 修复(9797e03)后,所有场景日志应全绿。
class RwSplitTestPage extends StatefulWidget {
  /// 读写分叉验证页。
  const RwSplitTestPage({super.key});

  @override
  State<RwSplitTestPage> createState() => _RwSplitTestPageState();
}

class _RwSplitTestPageState extends State<RwSplitTestPage> {
  final List<_LogLine> _logs = [];
  bool _busy = false;
  final ScrollController _scrollController = ScrollController();

  // ────────────────────────────────────────────────────────────────────
  // 日志输出
  // ────────────────────────────────────────────────────────────────────

  /// 追加一条日志并刷新 UI、自动滚动到底部。
  void _log(String tag, String text, {bool? ok}) {
    final line = _LogLine(
      time: DateTime.now().toString().substring(11, 19),
      tag: tag,
      text: text,
      ok: ok,
    );
    // 必须在 mounted 后再 setState(场景可能在 dispose 后异步回调)
    if (!mounted) return;
    setState(() => _logs.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// 运行一个场景,自动管理 _busy、异常捕获与日志。
  Future<void> _runScenario(
    String tag,
    String title,
    Future<void> Function() fn,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    _log(tag, '──── ▶ $title ────');
    try {
      await fn();
      _log(tag, '场景完成 ✔', ok: true);
    } catch (e, st) {
      _log(tag, '场景异常: $e', ok: false);
      if (kDebugMode) print(st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // 共用工具(从断言版平移,落点探测逻辑不变)
  // ────────────────────────────────────────────────────────────────────

  /// 全盘递归扫描 base 及其父目录下所有 .db 文件,返回「文件名 -> 出现过的绝对路径集合」。
  Future<Map<String, Set<String>>> scanAllDbs() async {
    final base = await getDatabasesPath();
    _log('SYS', 'getDatabasesPath() = $base');
    final result = <String, Set<String>>{};
    final roots = <Directory>[Directory(base), Directory(base).parent];

    void scan(Directory dir, int depth) {
      if (depth > 6) return;
      try {
        for (final entity in dir.listSync()) {
          if (entity is File && entity.path.endsWith('.db')) {
            final name = basename(entity.path);
            result.putIfAbsent(name, () => <String>{}).add(entity.path);
          } else if (entity is Directory) {
            scan(entity, depth + 1);
          }
        }
      } catch (_) {
        // 无权限目录忽略
      }
    }

    for (final r in roots) {
      try {
        scan(r, 0);
      } catch (_) {}
    }
    return result;
  }

  /// 删除所有名字以 [prefix] 开头的 db 文件(连同可能被分叉出来的副本)。
  Future<void> purgeByNamePrefix(String prefix, {String tag = 'SYS'}) async {
    final all = await scanAllDbs();
    var deleted = 0;
    for (final entry in all.entries) {
      if (entry.key.startsWith(prefix)) {
        for (final p in entry.value) {
          try {
            await File(p).delete();
            deleted++;
          } catch (e) {
            _log(tag, 'purge skip $p ($e)');
          }
        }
      }
    }
    _log(tag, '已清空 $prefix* (删除 $deleted 个文件)', ok: true);
  }

  // ────────────────────────────────────────────────────────────────────
  // 场景 A/B/C:写入 + 查询 + 落点副本数
  // ────────────────────────────────────────────────────────────────────

  Future<void> _writeQueryCase({
    required String tag,
    required String title,
    required List<String> relPath,
  }) async {
    final base = await getDatabasesPath();
    final path = joinAll([base, ...relPath]);
    final fileName = relPath.last;
    _log(tag, 'openDatabase path = $path');
    await purgeByNamePrefix(fileName.split('.').first, tag: tag);

    final db = await openDatabase(path);
    try {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS Test (id INTEGER PRIMARY KEY, name TEXT)');
      final rowId = await db.rawInsert(
        'INSERT INTO Test (name) VALUES (?)',
        ['row_$tag'],
      );
      _log(tag, 'insert rowId = $rowId', ok: rowId > 0);

      final rows = await db.query('Test');
      final readOk = rows.isNotEmpty;
      _log(tag, 'db.query("Test") 行数 = ${rows.length}'
          '${readOk ? " ✔" : " ✘ 能写不能读"}',
          ok: readOk);

      final all = await scanAllDbs();
      final copies = all[fileName] ?? <String>{};
      _log(tag, '物理副本数 = ${copies.length}'
          '${copies.length == 1 ? " ✔" : " ✘ 落点分叉"}',
          ok: copies.length == 1);
      for (final c in copies) {
        _log(tag, '   - $c');
      }
    } finally {
      await db.close();
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // 场景 D:关闭旧连接后再读,逼读路径走 TaskPool 重建
  // ────────────────────────────────────────────────────────────────────

  Future<void> _readAfterReopenCase() async {
    const tag = 'D';
    final base = await getDatabasesPath();
    final path = join(base, 'flutter', 'repro_reopen.db');
    _log(tag, 'path = $path');
    await purgeByNamePrefix('repro_reopen', tag: tag);

    // 第一次:写入 N 行
    const n = 3;
    var db = await openDatabase(path);
    try {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS Test (id INTEGER PRIMARY KEY, name TEXT)');
      final batch = db.batch();
      for (var i = 0; i < n; i++) {
        batch.rawInsert('INSERT INTO Test (name) VALUES (?)', ['d_$i']);
      }
      await batch.commit(noResult: true);
      final justWritten = await db.query('Test');
      _log(tag, '写入后(同一连接) query 行数 = ${justWritten.length} ✔',
          ok: true);
    } finally {
      await db.close(); // 释放打开时的缓存 store
    }

    // 第二次:重新打开一个全新连接再读。
    // 若读路径 TaskPool 重建的 store 落点与写路径不同,这里会读到 0 行。
    db = await openDatabase(path);
    try {
      final rows = await db.query('Test');
      final ok = rows.length == n;
      _log(tag, '重开后(新连接) query 行数 = ${rows.length}'
          '${ok ? " ✔" : " ✘ 读路径落点与写路径不同(issue #89)"}',
          ok: ok);
    } finally {
      await db.close();
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // 场景 G:时序攻击 —— 先读后写,让读路径成为该名字的首次打开者
  // ────────────────────────────────────────────────────────────────────

  Future<void> _readBeforeWriteCase() async {
    const tag = 'G';
    final base = await getDatabasesPath();
    final path = join(base, 'flutter', 'repro_timing.db');
    _log(tag, 'path = $path');
    await purgeByNamePrefix('repro_timing', tag: tag);

    var db = await openDatabase(path);
    try {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS Test (id INTEGER PRIMARY KEY, name TEXT)');
      final before = await db.query('Test');
      _log(tag, '写入前 query 行数 = ${before.length} (预期 0,关键看落点)');

      await db.insert('Test', {'name': 'timing'});
      final after = await db.query('Test');
      _log(tag, '写入后 query 行数 = ${after.length}'
          '${after.length == 1 ? " ✔" : " ✘"}',
          ok: after.length == 1);
    } finally {
      await db.close();
    }

    // 写入后再扫一次:该名字是否出现了「带子目录」与「默认位置」两个副本。
    final all = await scanAllDbs();
    final copies = all['repro_timing.db'] ?? <String>{};
    _log(tag, '"repro_timing.db" 物理副本数 = ${copies.length}'
        '${copies.length == 1 ? " ✔" : " ✘ 落点分叉"}',
        ok: copies.length == 1);
    for (final c in copies) {
      _log(tag, '   - $c');
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // 场景 E:PRAGMA database_list 真实挂载路径
  // ────────────────────────────────────────────────────────────────────

  Future<void> _pragmaListCase() async {
    const tag = 'E';
    final base = await getDatabasesPath();
    final path = join(base, 'flutter', 'repro_pragma.db');
    _log(tag, '请求打开的路径: $path');
    await purgeByNamePrefix('repro_pragma', tag: tag);

    final db = await openDatabase(path);
    try {
      await db.execute(
          'CREATE TABLE IF NOT EXISTS Test (id INTEGER PRIMARY KEY, name TEXT)');
      await db.insert('Test', {'name': 'pragma'});

      List<Map<String, Object?>> listResult;
      try {
        listResult = await db.rawQuery('PRAGMA database_list');
      } catch (e) {
        _log(tag, 'PRAGMA database_list 不可用: $e (该探针部分平台不支持,跳过)',
            ok: null);
        return;
      }

      final fileCol = <String>{};
      for (final row in listResult) {
        for (final v in row.values) {
          if (v is String && v.endsWith('.db')) {
            fileCol.add(v);
          }
        }
      }
      _log(tag, '连接挂载的 db 文件: ${fileCol.toList()}');
      final expected = join('flutter', 'repro_pragma.db');
      final ok = fileCol.any((f) => f.contains(expected));
      _log(tag, '挂载路径指向 $expected ${ok ? "✔" : "✘ 落到默认位置(读路径分叉)"}',
          ok: fileCol.isEmpty ? null : ok);
    } finally {
      await db.close();
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // 场景 F:汇总诊断,全盘扫描所有 repro_*.db 的物理位置
  // ────────────────────────────────────────────────────────────────────

  Future<void> _summaryScanCase() async {
    const tag = 'F';
    final all = await scanAllDbs();
    final repro = Map.fromEntries(
        all.entries.where((e) => e.key.startsWith('repro_')));
    _log(tag, '全盘扫描到 repro_*.db 共 ${repro.length} 个名字:');
    var splitCount = 0;
    repro.forEach((name, copies) {
      final split = copies.length > 1;
      _log(tag, '   $name → ${copies.length} 份${split ? "  ⚠️ 分叉!" : ""}',
          ok: split ? false : true);
      for (final c in copies) {
        _log(tag, '      - $c');
      }
      if (split) splitCount++;
    });
    _log(tag, '检出落点分叉的库名数量 = $splitCount'
        '${splitCount == 0 ? " ✔" : " ✘"}',
        ok: splitCount == 0);
  }

  // ────────────────────────────────────────────────────────────────────
  // UI
  // ────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _btn(String label, Future<void> Function() onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: ElevatedButton(
        onPressed: _busy ? null : onTap,
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('读写分叉验证 (issue #89)'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: '清空日志',
            // 清空日志只是清屏幕显示,与场景执行无关,随时可用。
            onPressed: () => setState(_logs.clear),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 顶部按钮区:Wrap 自适应换行,避免小屏溢出
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Wrap(
              alignment: WrapAlignment.center,
              children: <Widget>[
                _btn('A 单层子目录', () => _runScenario('A', '单层子目录 写入+查询', () => _writeQueryCase(tag: 'A', title: '单层子目录', relPath: const ['flutter', 'repro_a.db']))),
                _btn('B 深层子目录', () => _runScenario('B', '深层子目录 写入+查询', () => _writeQueryCase(tag: 'B', title: '深层子目录', relPath: const ['deep', 'nest', 'repro_b.db']))),
                _btn('C 纯文件名', () => _runScenario('C', '纯文件名 写入+查询 (对照组)', () => _writeQueryCase(tag: 'C', title: '纯文件名', relPath: const ['repro_c.db']))),
                _btn('D 关闭重开再读', () => _runScenario('D', '关闭重开再读 (逼走 TaskPool 重建)', _readAfterReopenCase)),
                _btn('G 先读后写时序', () => _runScenario('G', '先读后写时序 (读路径首次打开)', _readBeforeWriteCase)),
                _btn('E PRAGMA落点', () => _runScenario('E', 'PRAGMA database_list 挂载路径', _pragmaListCase)),
                _btn('F 全盘扫描汇总', () => _runScenario('F', '全盘扫描 repro_*.db 分叉情况', _summaryScanCase)),
                _btn('清空全部数据', () async {
                  // 作为重置入口:先清空页面日志,再删数据文件,给一个干净的重新开始。
                  setState(_logs.clear);
                  await _runScenario('SYS', '清空全部 repro_* 数据',
                      () => purgeByNamePrefix('repro_', tag: 'SYS'));
                }),
              ],
            ),
          ),
          const Divider(height: 1),
          // 日志流面板
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text('点击上方按钮,日志将实时显示在此处',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    itemCount: _logs.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _LogLineView(_logs[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// 数据模型与日志行渲染
// ──────────────────────────────────────────────────────────────────────

class _LogLine {
  _LogLine({required this.time, required this.tag, required this.text, this.ok});
  final String time;
  final String tag;
  final String text;
  final bool? ok; // null=中性信息,true=绿,false=红
}

class _LogLineView extends StatelessWidget {
  const _LogLineView(this.line);
  final _LogLine line;

  @override
  Widget build(BuildContext context) {
    final color = line.ok == true
        ? Colors.green
        : line.ok == false
            ? Colors.red
            : (Theme.of(context).brightness == Brightness.dark
                ? Colors.white70
                : Colors.black87);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
              fontSize: 12,
              color: color,
              fontFamily: 'monospace',
              height: 1.3),
          children: <InlineSpan>[
            TextSpan(
                text: '${line.time} [${line.tag}] ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: line.text),
          ],
        ),
      ),
    );
  }
}
