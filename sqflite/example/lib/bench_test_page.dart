// 单次操作耗时测试 —— 验证提交 6c42dd2(worker 线程改造)前后的单次 db 操作耗时。
//
// 点「开始测试」,自动依次执行 建表 / 插入 / 修改 / 查询,
// 每个操作重复 N 次取平均耗时(ms),结果一行一个,一目了然。
// 在 6c42dd2^(改造前) 和 6c42dd2(改造后) 各运行一次对比即可。

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_example/database/database.dart';

/// Bench test route name.
const String testBenchRoute = '/test/bench';

/// 单个操作的平均耗时。
class _Result {
  _Result(this.name, this.avgMs);

  final String name;
  final double avgMs;
}

/// Bench test page.
class BenchTestPage extends StatefulWidget {
  /// Bench test page.
  const BenchTestPage({Key? key}) : super(key: key);

  @override
  State<BenchTestPage> createState() => _BenchTestPageState();
}

class _BenchTestPageState extends State<BenchTestPage> {
  // 每个操作重复次数(取平均,降低单次抖动)。
  static const _loops = 20;

  bool _running = false;
  String? _current; // 当前正在测的操作名
  final List<_Result> _results = [];

  Future<void> _run() async {
    setState(() {
      _running = true;
      _current = null;
      _results.clear();
    });

    final path = await initDeleteDb('bench_test.db');
    final db = await openDatabase(path);

    const createSql =
        'CREATE TABLE T (id INTEGER PRIMARY KEY, name TEXT, value INTEGER)';
    const dropSql = 'DROP TABLE IF EXISTS T';
    final sw = Stopwatch();

    try {
      // 1) 建表:每轮先 DROP(不计入),再计 CREATE
      setState(() => _current = '建表');
      for (var i = 0; i < _loops; i++) {
        await db.execute(dropSql);
        sw.start();
        await db.execute(createSql);
        sw.stop();
      }
      _add('建表 (CREATE TABLE)', sw);
      sw.reset();

      // 2) 插入(单条):顺带产生数据供后面修改/查询用
      setState(() => _current = '插入');
      for (var i = 0; i < _loops; i++) {
        sw.start();
        await db.rawInsert(
          'INSERT INTO T (name, value) VALUES (?, ?)',
          ['item $i', i],
        );
        sw.stop();
      }
      _add('插入 (单条)', sw);
      sw.reset();

      // 3) 修改(单条)
      setState(() => _current = '修改');
      for (var i = 0; i < _loops; i++) {
        final id = (i % _loops) + 1;
        sw.start();
        await db.rawUpdate('UPDATE T SET value = ? WHERE id = ?', [i * 2, id]);
        sw.stop();
      }
      _add('修改 (单条)', sw);
      sw.reset();

      // 4) 查询(命中 1 条)
      setState(() => _current = '查询');
      for (var i = 0; i < _loops; i++) {
        final id = (i % _loops) + 1;
        sw.start();
        await db.rawQuery('SELECT * FROM T WHERE id = ?', [id]);
        sw.stop();
      }
      _add('查询 (1 条)', sw);
      sw.reset();

      // 5) 查询(列表 LIMIT 100)
      setState(() => _current = '查询列表');
      for (var i = 0; i < _loops; i++) {
        sw.start();
        await db.rawQuery('SELECT * FROM T LIMIT 100');
        sw.stop();
      }
      _add('查询 (列表 LIMIT 100)', sw);
    } finally {
      await db.close();
      if (mounted) {
        setState(() {
          _running = false;
          _current = null;
        });
      }
    }
  }

  void _add(String name, Stopwatch sw) {
    final avgMs = sw.elapsedMicroseconds / _loops / 1000.0;
    setState(() => _results.add(_Result(name, avgMs)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('单次操作耗时')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ..._results.map((r) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(r.name)),
                    Text(
                      '${r.avgMs.toStringAsFixed(3)} ms',
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )),
          if (_running)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('正在测试:$_current …'),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _running ? null : _run,
              child: Text(_running ? '测试中…' : '开始测试'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '每个操作重复 20 次取平均。\n'
              '在 6c42dd2^(改造前) 和 6c42dd2(改造后) 各运行一次,对比各项耗时。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
