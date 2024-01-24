/*
 * Copyright (c) 2021-2022 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License")
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

import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/src/constant.dart';
import 'package:sqflite_common/src/method_call.dart';
import 'package:sqflite_common/src/mixin/factory.dart';
import 'package:test/test.dart';

var logs = <SqfliteMethodCall>[];
var databaseFactoryMock = buildDatabaseFactory(
    tag: 'mock',
    invokeMethod: (method, [arguments]) async {
      logs.add(SqfliteMethodCall(method, arguments));
      if (method == methodGetDatabasesPath) {
        return 'mock_path';
      }
    });

void main() {
  test('simple sqflite example', () async {
    logs.clear();
    // ignore: deprecated_member_use_from_same_package
    await databaseFactoryMock.debugSetLogLevel(sqfliteLogLevelVerbose);
    expect(logs.map((log) => log.toMap()), [
      {
        'method': 'options',
        'arguments': {'logLevel': 2}
      }
    ]);
  });
  test('databasesPath', () async {
    final oldDatabasePath = await databaseFactoryMock.getDatabasesPath();
    try {
      await databaseFactoryMock.setDatabasesPath('.');
      final path = await databaseFactoryMock.getDatabasesPath();
      expect(path, '.');
    } finally {
      await databaseFactoryMock.setDatabasesPath(oldDatabasePath);
    }
  });
}
