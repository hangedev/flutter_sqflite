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

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'test_page.dart';

/// New features test page.
class NewFeaturesTestPage extends TestPage {
  /// New features test page.
  NewFeaturesTestPage({Key? key}) : super('New features tests', key: key) {
    test('Attach', () async {
      await initDeleteDb('main.db');
      await initDeleteDb('secondary.db');

      // 初始化两个数据库
      final db = await initDatabase('main.db');
      final secondaryDb = await initDatabase('secondary.db');

      // 插入示例数据
      await db.insert('users', {'name': 'Alice'});
      await secondaryDb.insert('orders', {'product': 'Laptop', 'user_id': 1});

      // 附加第二个数据库
      await attachDatabase(db, secondaryDb, 'secondary');

      // 执行跨数据库查询
      final results = await db.rawQuery('''
    SELECT users.name, orders.product 
    FROM users
    INNER JOIN secondary.orders ON users.id = orders.user_id
  ''');

      // 分离数据库
      await db.execute('DETACH DATABASE secondary');

      // 关闭数据库
      await db.close();
      await secondaryDb.close();
      expect(results[0]['product'], 'Laptop');
    });

    test('Tokenizer', () async {
      const dbName = 'tokenizer';
      const sqlCreateTable = 'CREATE VIRTUAL TABLE example USING fts4(name, content, tokenize=icu zh_CN)';
      await initDeleteDb(dbName);

      final databasePath = await getDatabasesPath();
      final path = join(databasePath, dbName);
      final database = await openDatabase(
        path,
        version: 1,
        onCreate: (Database db, int version) async {
          // 创建FTS虚拟表
          await db.execute(sqlCreateTable);
        },
      );

      // 插入数据
      await database.insert('example', {'name': 'jack', 'content': 'This is a sample text for full-text search in Flutter 中国'});

      // 搜索
      final results = await database.query('example', where: 'content MATCH ?', whereArgs: ['sample text']);
      expect(results[0]['name'], 'jack');
    });

    test('Bigint sort', () async {
      final path = await initDeleteDb('bigint.db');
      final db = await openDatabase(path);
      final String _tableName = "users";
      db.execute("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT, age INTEGER, create_t UNLIMITED INT)");
      List<Map<String, dynamic>> users = [];
      for (int i = 0; i < 5; i++) {
        users.add(getUser());
      }
      await db.transaction((txn) async {
        Batch batch = txn.batch();
        for (var user in users) {
          batch.insert('users', user);
        }
        await batch.commit();
      });

      final maps = await db.query(_tableName, orderBy: 'create_t ASC');
      List<int> createTimes = maps.map((user) => user['create_t'] as int).toList();
      expect(isASC(createTimes), true);
    });
  }

  Map<String, dynamic> getUser() {
    int now = 9223372036854775807;
    return {
      'name': 'Jack',
      'age': Random().nextInt(30000),
      'create_t': now - Random().nextInt(30000),
    };
  }

  bool isASC(List<int> users) {
    for (int i = 0; i < users.length - 1; i++) {
      if (users[i] > users[i + 1]) {
        return false;
      }
    }
    return true;
  }

  // 初始化数据库并创建表
  Future<Database> initDatabase(String name) async {
    final path = join(await getDatabasesPath(), name);
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        if (name == 'main.db') {
          await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            name TEXT
          )
        ''');
        } else {
          await db.execute('''
          CREATE TABLE orders (
            id INTEGER PRIMARY KEY,
            product TEXT,
            user_id INTEGER
          )
        ''');
        }
      },
    );
  }

  // 附加数据库的核心方法
  Future<void> attachDatabase(Database mainDb, Database secondaryDb, String alias) async {
    // 关闭目标数据库以释放文件锁
    await secondaryDb.close();
    // 获取附加数据库的绝对路径
    final path = join(await getDatabasesPath(), 'secondary.db');

    try {
      // 执行 ATTACH 命令
      await mainDb.execute('ATTACH DATABASE ? AS $alias', [path]);
      print("attach success}");
    } catch (error) {
      print("attach failed, ${error.toString()}");
    }
  }
}
