/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
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
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'test_page.dart';

// ignore_for_file: avoid_print

/// 原生 sqflite MethodChannel 名（直接复用数据库实例 id 构造畸形消息）。
const String _platformChannelName = 'com.tekartik.sqflite';

/// 页面级防连点：同一时刻只允许一个用例在执行。
/// TestPage 基类的单条点击之间没有互斥（仅等待整组结束），而本页用例操作
/// 全局资源（游标 LRU 上限、temp_memory_*.db 计数），并发重跑会互相干扰
/// （对方新开的游标会把我方"最新游标"挤出 LRU、对方在开的临时文件会被
/// 计入我方计数），快速反复点击必然误报失败。
bool _caseRunning = false;

Future<void> _guarded(Future<void> Function() fn) async {
  if (_caseRunning) {
    print('[忽略] 上一个用例仍在运行，本次触发被防连点挡下');
    return;
  }
  _caseRunning = true;
  try {
    await fn();
  } finally {
    _caseRunning = false;
  }
}

/// 稳定性与资源管理回归测试页（结构同 Raw tests 页：进入自动逐条运行，
/// 点击单条可重跑，右上角刷新整组重跑，print 日志输出到终端）。
///
/// 逐项验证原生层（ArkTS）修复的资源管理与错误处理行为：
/// 游标生命周期（关库清理/LRU 上限）、事务中断后的状态一致性、
/// 失败信封规范化（open_failed/sqlite_error/bad_param）、
/// 畸形消息防御、内存库临时文件清理。
/// 每个用例自包含并在 finally 中收尾自身资源（对后续用例无污染）。
class ResourceTestPage extends TestPage {
  /// 回归测试页。
  ResourceTestPage({Key? key}) : super('稳定性与资源管理回归', key: key) {
    test('用例 1：游标未释放即关库', () => _guarded(() async {
      // 用文件库：内存库每次打开都是新临时文件（temp_memory_<ts>.db），
      // 验证不了"关库后重开同一库"
      final path = join(await getDatabasesPath(), 'resource_case1.db');
      await databaseFactory.deleteDatabase(path);
      var db = await openDatabase(path, version: 1, onCreate: (db, version) async {
        await db.execute('CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT)');
      });
      try {
        await db.execute(
            "INSERT INTO Test (name) VALUES ('a'),('b'),('c'),('d'),('e')");
        print('用例 1 | 步骤1: rawQueryCursor(bufferSize: 2) 取得游标，不读完也不 close');
        // 故意持有不释放：原生侧该库游标随 close 统一回收
        await db.rawQueryCursor('SELECT * FROM Test', null, bufferSize: 2);
        print('用例 1 | 步骤2: 直接 close 数据库（游标仍打开）');
        await db.close();
        print('用例 1 | 步骤3: 重新打开同一文件，验证读写正常');
        final db2 = await openDatabase(path, version: 1);
        try {
          final count = await _count(db2);
          await db2.execute("INSERT INTO Test (name) VALUES ('after-reopen')");
          final count2 = await _count(db2);
          print('用例 1 | 重开后 $count 行，写入后 $count2 行');
          verify(count == 5 && count2 == 6,
              '期望 close 不抛异常（原生随关库回收该库名下 ResultSet）、重开后 5 行可读可写（→6 行）；实际 $count 行 → $count2 行');
        } finally {
          await db2.close();
        }
      } finally {
        // db 已在用例内 close；重开失败时兜底
        if (db.isOpen) {
          await db.close();
        }
      }
    }));

    test('用例 2：游标缓存 LRU 上限（32）', () => _guarded(() async {
      final db = await _openMemoryDb();
      final cursors = <QueryCursor>[];
      try {
        final batch = db.batch();
        for (var i = 0; i < 100; i++) {
          batch.insert('Test', {'name': 'row$i'});
        }
        await batch.commit();
        print('用例 2 | 步骤1: 打开 40 个分页游标（bufferSize: 5），全部不释放');
        for (var i = 0; i < 40; i++) {
          cursors.add(await db.rawQueryCursor('SELECT * FROM Test', null,
              bufferSize: 5));
        }
        print('用例 2 | 步骤2: 最旧游标（第 1 个）消费完本地缓冲后续页，应已被 LRU 淘汰');
        var oldestEvicted = false;
        try {
          await _moveToNextPage(cursors[0], 5);
          print('用例 2 | 最旧游标续页成功（未淘汰？）');
        } catch (e) {
          oldestEvicted = true;
          print('用例 2 | 最旧游标续页抛异常（预期）: ${_brief(e)}');
        }
        print('用例 2 | 步骤3: 最新游标（第 40 个）消费完本地缓冲后续页，应正常返回数据');
        final latestOk = await _moveToNextPage(cursors[39], 5);
        print('用例 2 | 最旧=${oldestEvicted ? '已淘汰' : '未淘汰'}，'
            '最新=${latestOk ? '正常' : '失败'}');
        verify(oldestEvicted && latestOk,
            '期望最旧游标续页报 Cursor not found（句柄成对释放）、最新游标续页正常；'
            '实际最旧 ${oldestEvicted ? '已淘汰' : '未淘汰'}、最新 ${latestOk ? '正常' : '失败'}');
      } finally {
        for (final cursor in cursors) {
          // 原生侧游标可能已被 LRU 淘汰/关库清理，close 会抛 Cursor not found，吞掉即可。
          unawaited(cursor.close().catchError((Object e) {}));
        }
        await db.close();
      }
    }));

    test('用例 3：裸 SQL 事务未提交即关库', () => _guarded(() async {
      final db = await _openMemoryDb();
      try {
        print('用例 3 | 步骤1: 裸 BEGIN IMMEDIATE + INSERT 1 行（不 COMMIT）');
        await db.execute('BEGIN IMMEDIATE');
        await db.execute("INSERT INTO Test (name) VALUES ('uncommitted')");
        print('用例 3 | 步骤2: 不提交直接 close（原生关库前重置全局事务状态）');
        await db.close();
      } finally {
        if (db.isOpen) {
          await db.close();
        }
      }
      final db2 = await _openMemoryDb();
      try {
        final count = await _count(db2);
        await db2.execute("INSERT INTO Test (name) VALUES ('next-db-ok')");
        final count2 = await _count(db2);
        print('用例 3 | 重开后 $count 行（未提交已回滚），新库正常插入后 $count2 行');
        verify(count == 0 && count2 == 1,
            '期望 close 不抛异常、未提交 INSERT 被回滚（重开库 0 行）、之后在新库上无事务包裹正常 INSERT 成功（→1 行）；'
            '实际重开后 $count 行、新库插入后 $count2 行');
      } finally {
        await db2.close();
      }
    }));

    test('用例 4：重复 BEGIN 失败信封', () => _guarded(() async {
      final db = await _openMemoryDb();
      try {
        print('用例 4 | 步骤1: 第一次 BEGIN IMMEDIATE（应成功）');
        await db.execute('BEGIN IMMEDIATE');
        print('用例 4 | 步骤2: 第二次 BEGIN IMMEDIATE（观察失败信封或嵌套语义）');
        var code = '<no-exception>';
        try {
          await db.execute('BEGIN IMMEDIATE');
        } on Exception catch (e) {
          // 判据：异常文本含 sqlite_error（原生信封 code 为 sqlite_error 时携带）
          code = _brief(e).contains('sqlite_error') ? 'sqlite_error' : _brief(e);
        }
        await db.execute('ROLLBACK');
        // 无论 OHOS 采用 beginTransaction 嵌套计数（不抛）还是 sqlite_error 信封，
        // 事务命令后库与通道必须仍可用（不崩 worker、不挂起）
        final count = await _count(db);
        print('用例 4 | 第二次 BEGIN='
            '${code == '<no-exception>' ? '嵌套计数' : code}，ROLLBACK 后 COUNT = $count');
        verify((code == 'sqlite_error' || code == '<no-exception>') && count == 0,
            '期望要么明确报 sqlite_error（带错误码）、要么按 OHOS beginTransaction 嵌套计数语义静默接受，'
            '两种情况下 ROLLBACK 后库均可正常查询；'
            '实际第二次 BEGIN ${code == '<no-exception>' ? '未抛异常（嵌套计数语义）' : '结果 = $code'}、'
            'ROLLBACK 后 COUNT = $count');
      } finally {
        await db.close();
      }
    }));

    test('用例 5：openDatabase 失败传播', () => _guarded(() async {
      print('用例 5 | 步骤1: readOnly 打开不存在的文件，应抛异常且含 open_failed');
      // 注：OHOS 文件名允许 * ? 等字符（"bad*name?.db" 能成功创建），
      // 确定失败路径用 readOnly + 不存在文件（只读不允许创建）
      final path = join(await getDatabasesPath(), 'no_such_file_readonly.db');
      await databaseFactory.deleteDatabase(path);
      var code = '<no-exception>';
      var opened = false;
      try {
        final db = await openDatabase(path, readOnly: true);
        opened = true;
        await db.close();
      } on Exception catch (e) {
        code = e.toString();
      }
      // 报错信息全文输出，不做省略截断
      print('用例 5 | ${opened ? 'open 成功' : '异常 = $code'}');
      verify(!opened && code.contains('open_failed'),
          '期望 openDatabase 抛 PlatformException/DatabaseException 且 message 含 open_failed 与底层错误码；'
          '实际 ${opened ? '竟然 open 成功（未复现失败路径）' : '异常 = $code'}');
    }));

    test('用例 6：ATTACH 占位符缺参', () => _guarded(() async {
      final db = await _openMemoryDb();
      try {
        print('用例 6 | 步骤1: execute("ATTACH DATABASE ? AS ?") 不传参数');
        var code = '<no-exception>';
        try {
          await db.execute('ATTACH DATABASE ? AS ?');
        } on Exception catch (e) {
          // 原生部分校验错误（如 bad_param）未经 Dart 侧 wrapDatabaseException
          // 转换时会以 PlatformException 冒出，一并接住
          code = e.toString();
        }
        print('用例 6 | ${code == '<no-exception>' ? '未抛异常' : '异常 = ${_brief(code)}'}');
        verify(code.contains('bad_param') || code.contains('attach'),
            '期望抛 DatabaseException 明确指向 attach 缺参（bad_param），而非静默成功或 native 崩溃；'
            '实际 ${code == '<no-exception>' ? '未抛异常' : '异常 = ${_brief(code)}'}');
      } finally {
        await db.close();
      }
    }));

    test('用例 7：batch 畸形消息防御', () => _guarded(() async {
      final db = await _openMemoryDb();
      try {
        // db.id 不在公开 Database 接口上（是 sqflite_common 内部字段），经 dynamic 取运行时值
        final dbId = (db as dynamic).id as int?;
        print('用例 7 | 步骤1: 原始 channel 发 batch 消息，operations 传 null');
        var code = '<no-exception>';
        try {
          await const MethodChannel(_platformChannelName)
              .invokeMethod<void>('batch', {'id': dbId, 'operations': null});
        } on PlatformException catch (e) {
          code = e.code;
        }
        // 库仍应可用（畸形消息不应打断通道）
        final count = await _count(db);
        print('用例 7 | PlatformException.code = $code，后续 COUNT = $count');
        verify(code == 'bad_param' && count == 0,
            '期望 PlatformException(code: bad_param) 且之后该库仍可正常查询；'
            '实际 code = $code、后续 COUNT = $count');
      } finally {
        await db.close();
      }
    }));

    test('用例 8：内存库临时文件清理', () => _guarded(() async {
      // 前序用例均在 finally 中收尾自身库/游标，这里统计到的 temp_memory_*.db
      // 只可能是真正泄漏的文件
      final before = await _countTempMemoryFiles();
      print('用例 8 | 步骤1: 运行前 temp_memory_*.db = $before 个');
      print('用例 8 | 步骤2: 连续开关 5 个 :memory: 库（各插 1 行）');
      for (var i = 0; i < 5; i++) {
        final db = await _openMemoryDb();
        await db.execute("INSERT INTO Test (name) VALUES ('m$i')");
        await db.close();
      }
      final after = await _countTempMemoryFiles();
      print('用例 8 | 运行前 $before 个 → 运行后 $after 个');
      verify(before == 0 && after == 0,
          '期望运行前无残留（前序用例已收尾）且连续开关 5 个 :memory: 库后仍无残留'
          '（正常 close 删除 + worker 启动兜底清理）；实际运行前 $before 个 → 运行后 $after 个');
      print('用例 8 | 步骤3: 打开用户命名的常规库 temp_memory_custom.db'
          '（前缀与内存库临时文件相同，验证正常可用、不计入孤儿数）');
      final customPath = join(await getDatabasesPath(), 'temp_memory_custom.db');
      await databaseFactory.deleteDatabase(customPath);
      final customDb = await openDatabase(customPath, version: 1,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT)');
          });
      await customDb.execute("INSERT INTO Test (name) VALUES ('user-data-1')");
      await customDb.execute("INSERT INTO Test (name) VALUES ('user-data-2')");
      await customDb.close();
      final reopened = await openDatabase(customPath, version: 1);
      final customCount = await _count(reopened);
      await reopened.close();
      print('用例 8 | temp_memory_custom.db 重开 COUNT = $customCount（用户数据完整 = 2）');
      final finalCount = await _countTempMemoryFiles();
      await databaseFactory.deleteDatabase(customPath);
      verify(customCount == 2 && finalCount == 0,
          '期望用户以 temp_memory_ 开头命名的常规库正常可用（重开数据完整 COUNT=2）'
          '且不计入孤儿临时文件统计（收窄为纯数字时间戳格式后 COUNT=0；'
          '真机热重启后文件不被 worker 兜底清理误删见文档步骤）；'
          '实际 COUNT = $customCount、孤儿统计 = $finalCount');
    }));

    test('用例 9：事务中关闭无关库不影响本库事务', () => _guarded(() async {
      final basePath = await getDatabasesPath();
      final pathA = join(basePath, 'resource_case9_a.db');
      final pathB = join(basePath, 'resource_case9_b.db');
      await databaseFactory.deleteDatabase(pathA);
      await databaseFactory.deleteDatabase(pathB);
      final dbA = await openDatabase(pathA, version: 1,
          onCreate: (db, version) async {
        await db.execute('CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT)');
      });
      final dbB = await openDatabase(pathB, version: 1,
          onCreate: (db, version) async {
        await db.execute('CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT)');
      });
      try {
        print('用例 9 | 步骤1: dbA 事务内插入 1 行');
        await dbA.transaction((txn) async {
          await txn.insert('Test', {'name': 'before'});
          print('用例 9 | 步骤2: 事务进行中 close 无关库 dbB'
              '（修复前：全局事务状态被误清，事务内写被自动提交、COMMIT 后 depth 失真）');
          await dbB.close();
          print('用例 9 | 步骤3: 继续在事务内插入 1 行并提交');
          await txn.insert('Test', {'name': 'after'});
        });
        final count = await _count(dbA);
        print('用例 9 | 提交后 dbA COUNT = $count（事务原子性完整 = 2）');
        verify(count == 2,
            '期望事务中关闭无关库不影响本库事务（两条插入原子提交，COUNT = 2）；'
            '实际 COUNT = $count');
      } finally {
        if (dbB.isOpen) {
          await dbB.close();
        }
        await dbA.close();
      }
    }));

    test('用例 10：损坏库重复打开复用占位实例', () => _guarded(() async {
      final path = join(await getDatabasesPath(), 'resource_case10_corrupt.db');
      await databaseFactory.deleteDatabase(path);
      // 先建合法库再写坏：保证文件存在且非 SQLite 格式（14800011 占位路径）
      final db = await openDatabase(path, version: 1,
          onCreate: (d, v) async {
        await d.execute('CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT)');
      });
      await db.close();
      await File(path).writeAsString('this is not a sqlite database file');
      // 直接走原始 channel：Dart 侧 openDatabase 同路径会命中 factory 缓存
      // （不再向原生发 openDatabase 消息），验证不了原生占位复用分支
      const channel = MethodChannel(_platformChannelName);
      print('用例 10 | 步骤1: 文件已写坏，原始 channel 第一次 openDatabase（占位成功）');
      final r1 = await channel.invokeMethod<Map<dynamic, dynamic>>(
          'openDatabase', {'path': path});
      final id1 = r1?['id'];
      print('用例 10 | 第一次: id=$id1, recovered=${r1?['recovered']}');
      print('用例 10 | 步骤2: 第二次 openDatabase 同路径（应复用占位条目，不再新建）');
      final r2 = await channel.invokeMethod<Map<dynamic, dynamic>>(
          'openDatabase', {'path': path});
      final id2 = r2?['id'];
      final recovered2 = r2?['recovered'] == true;
      print('用例 10 | 第二次: id=$id2, recovered=$recovered2');
      verify(id1 != null && id2 != null && id1 == id2 && recovered2,
          '期望第二次 open 复用占位条目（id 相同且 recovered=true，无孤儿条目累积，'
          'hilog Deferred corrupt open 仅出现一次）；'
          '实际第一次 id=$id1、第二次 id=$id2 recovered=$recovered2');
      print('用例 10 | 步骤3: closeDatabase 关闭占位条目（应清理四张登记表，不报错）');
      await channel.invokeMethod<Object>('closeDatabase', {'id': id2});
      print('用例 10 | 步骤4: 关闭后第三次 openDatabase（条目已清理，应分配新 id）');
      final r3 = await channel.invokeMethod<Map<dynamic, dynamic>>(
          'openDatabase', {'path': path});
      final id3 = r3?['id'];
      print('用例 10 | 第三次: id=$id3, recovered=${r3?['recovered']}');
      verify(id3 != null && id3 != id2,
          '期望 close 占位条目后重新 open 分配新 id（条目与单实例登记均被清理，'
          '不残留"关不掉的占位条目"）；实际关闭前 id=$id2、关闭后 id=$id3');
    }));
  }
}

/// 打开一个干净的内存库（每次打开均为新的临时文件库）。
/// singleInstance: false —— 每次 open 都创建独立实例（Dart 侧不复用缓存、
/// 原生侧按 id 记账），与多实例修复（CHANGELOG #2）的语义一致。
Future<Database> _openMemoryDb() async {
  return openDatabase(inMemoryDatabasePath, version: 1,
      singleInstance: false, onCreate: (db, version) async {
    await db.execute('CREATE TABLE Test (id INTEGER PRIMARY KEY, name TEXT)');
  });
}

Future<int> _count(Database db) async =>
    Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM Test')) ?? 0;

/// 先消费完本地缓冲的一页（bufferSize 行），再 moveNext 一次触发原生续页。
/// moveNext 在本地缓冲未耗尽时只前进索引、不发原生请求，
/// 直接调一次验证不了原生侧游标是否已被 LRU 淘汰。
Future<bool> _moveToNextPage(QueryCursor cursor, int bufferedRows) async {
  for (var i = 0; i < bufferedRows; i++) {
    await cursor.moveNext();
  }
  return cursor.moveNext();
}

/// 统计 databaseDir 与其上级目录（rdb 结果目录）下 temp_memory_*.db 的数量。
/// 内存库临时文件名固定为 temp_memory_<纯数字时间戳>.db（原生侧 Date.now() 生成），
/// 统计口径与原生孤儿清理的严格匹配保持一致，避免把用户以 temp_memory_ 开头
/// 命名的常规数据库（如 temp_memory_custom.db）计入孤儿数。
final RegExp _memoryTempFilePattern = RegExp(r'^temp_memory_[0-9]+\.db$');

Future<int> _countTempMemoryFiles() async {
  var total = 0;
  final rdbDir = await getDatabasesPath();
  final dirs = <String>[rdbDir, rdbDir.substring(0, rdbDir.lastIndexOf('/'))];
  for (final dir in dirs) {
    final directory = Directory(dir);
    if (!directory.existsSync()) continue;
    await for (final entity in directory.list()) {
      final base = entity.path.substring(entity.path.lastIndexOf('/') + 1);
      if (_memoryTempFilePattern.hasMatch(base)) {
        total++;
      }
    }
  }
  return total;
}

/// 异常信息压缩为单行短描述。
String _brief(Object e) {
  final text = e.toString();
  const max = 140;
  final oneLine = text.replaceAll('\n', ' ');
  return oneLine.length <= max ? oneLine : '${oneLine.substring(0, max)}…';
}
