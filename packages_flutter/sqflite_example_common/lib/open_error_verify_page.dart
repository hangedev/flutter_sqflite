import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_example_common/database/database.dart';

class OhosOpenErrorVerifyPage extends StatefulWidget {
  const OhosOpenErrorVerifyPage({super.key});

  @override
  State<OhosOpenErrorVerifyPage> createState() =>
      _OhosOpenErrorVerifyPageState();
}

enum _VerifyState {
  idle,
  running,
  passed,
  failed,
}

class _VerifyItem {
  _VerifyItem({
    required this.title,
    required this.expected,
  });

  final String title;
  final String expected;
  _VerifyState state = _VerifyState.idle;
  String details = '尚未执行';
}

class _OhosOpenErrorVerifyPageState extends State<OhosOpenErrorVerifyPage> {
  final _badPathItem = _VerifyItem(
    title: '只读打开不存在数据库校验',
    expected: '只读打开一个不存在的数据库文件时，应抛出 DatabaseException(open_failed)。',
  );

  final _nonSqliteItem = _VerifyItem(
    title: '非 sqlite 文件校验',
    expected: '普通 dummy 文件不应被静默当成可正常使用的只读数据库。',
  );

  bool _runningAll = false;

  Future<void> _runAll() async {
    if (_runningAll) {
      return;
    }
    setState(() {
      _runningAll = true;
    });
    try {
      await _runBadPathCheck();
      await _runNonSqliteCheck();
    } finally {
      if (mounted) {
        setState(() {
          _runningAll = false;
        });
      }
    }
  }

  Future<void> _runBadPathCheck() async {
    _setStatus(
      _badPathItem,
      _VerifyState.running,
      '正在准备不存在的数据库路径...',
    );

    final factory = databaseFactory;
    final dbPath = p.join(
      await factory.getDatabasesPath(),
      'ohos_missing_${DateTime.now().millisecondsSinceEpoch}.db',
    );

    try {
      await factory.deleteDatabase(dbPath);
      final db = await factory
          .openDatabase(
            dbPath,
            options: OpenDatabaseOptions(readOnly: true),
          )
          .timeout(const Duration(seconds: 5));
      await db.close();
      _setStatus(
        _badPathItem,
        _VerifyState.failed,
        '异常：只读打开不存在数据库竟然成功了。\n'
            '数据库路径：$dbPath',
      );
    } on TimeoutException {
      _setStatus(
        _badPathItem,
        _VerifyState.failed,
        '异常：openDatabase 调用超时，未正常返回结果。\n'
            '数据库路径：$dbPath\n'
            '该场景本应快速失败，这通常说明 OHOS 原生侧发生了挂起。',
      );
    } on DatabaseException catch (e) {
      final passed = e.isOpenFailedError();
      _setStatus(
        _badPathItem,
        passed ? _VerifyState.passed : _VerifyState.failed,
        '数据库路径：$dbPath\n'
            '异常信息：$e',
      );
    } catch (e) {
      _setStatus(
        _badPathItem,
        _VerifyState.failed,
        '异常：出现了非预期类型的错误。\n'
            '数据库路径：$dbPath\n'
            '错误信息：$e',
      );
    }
  }

  Future<void> _runNonSqliteCheck() async {
    _setStatus(
      _nonSqliteItem,
      _VerifyState.running,
      '正在准备 dummy 文件...',
    );

    final factory = databaseFactory;
    final path = p.join(
      await factory.getDatabasesPath(),
      'ohos_non_sqlite_${DateTime.now().millisecondsSinceEpoch}.db',
    );

    final buffer = <String>[];
    var blockedAsExpected = false;
    Database? db;

    try {
      await writeFileAsString(path, 'dummy', flush: true);
      buffer.add('已创建 dummy 文件：$path');

      try {
        db = await factory.openDatabase(
          path,
          options: OpenDatabaseOptions(readOnly: true),
        );
        buffer.add('只读 openDatabase：成功');
      } on DatabaseException catch (e) {
        blockedAsExpected = true;
        buffer.add('只读 openDatabase：$e');
      }

      // 验证损坏数据库的延迟失败机制：
      // openDatabase 虽然返回成功，但后续操作 getVersion 应该抛出异常
      // 这是OHOS对损坏文件的延迟失败处理（与Android/iOS行为一致）
      if (db != null) {
        try {
          final version = await db.getVersion();
          // 如果getVersion成功，说明数据库实际上能正常打开，测试失败
          buffer.add('getVersion：成功（$version）');
        } on DatabaseException catch (e) {
          // 如果getVersion抛出异常，说明延迟失败机制正常工作，测试通过
          blockedAsExpected = true;
          buffer.add('getVersion：$e');
        } finally {
          // 无论成功或失败，都要关闭数据库，清理资源
          await db.close();
        }
      }

      final content = await readFileAsString(path);
      buffer.add('校验后的文件内容：$content');

      final passed = blockedAsExpected && content == 'dummy';
      _setStatus(
        _nonSqliteItem,
        passed ? _VerifyState.passed : _VerifyState.failed,
        buffer.join('\n'),
      );
    } catch (e) {
      _setStatus(
        _nonSqliteItem,
        _VerifyState.failed,
        '${buffer.join('\n')}\n'
            '非预期错误：$e',
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
    return Scaffold(
      appBar: AppBar(title: const Text('OHOS openDatabase 验证页')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '这是仅用于 OHOS 的本地验证页面，不会修改上游共享示例测试。',
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _runningAll ? null : _runAll,
              child: const Text('执行全部校验'),
            ),
            const SizedBox(height: 12),
            _buildItemCard(
              item: _badPathItem,
              onPressed: _runningAll ? null : _runBadPathCheck,
            ),
            const SizedBox(height: 12),
            _buildItemCard(
              item: _nonSqliteItem,
              onPressed: _runningAll ? null : _runNonSqliteCheck,
            ),
          ],
        ),
      ),
    );
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