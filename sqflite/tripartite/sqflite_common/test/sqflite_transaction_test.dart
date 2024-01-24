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
import 'package:sqflite_common/src/exception.dart';
import 'package:test/test.dart';

import 'test_scenario.dart';

void main() {
  group('transaction', () {
    final transactionBeginStep = [
      'execute',
      {
        'sql': 'BEGIN IMMEDIATE',
        'id': 1,
        'inTransaction': true,
        'transactionId': null
      },
      null,
    ];
    final transactionBeginFailureStep = [
      'execute',
      {
        'sql': 'BEGIN IMMEDIATE',
        'id': 1,
        'inTransaction': true,
        'transactionId': null
      },
      SqfliteDatabaseException('failure', null),
    ];
    final transactionEndStep = [
      'execute',
      {'sql': 'COMMIT', 'id': 1, 'inTransaction': false},
      1
    ];
    test('basic', () async {
      final scenario = startScenario([
        protocolOpenStep,
        transactionBeginStep,
        transactionEndStep,
        transactionBeginStep,
        transactionEndStep,
        protocolCloseStep,
      ]);
      final factory = scenario.factory;
      final db = await factory.openDatabase(inMemoryDatabasePath);

      await db.transaction((txn) async {});
      await db.transaction((txn) async {});
      await db.close();
      scenario.end();
    });
    test('error in begin after open', () async {
      final scenario = startScenario([
        protocolOpenStep,
        transactionBeginFailureStep,
        transactionBeginStep,
        transactionEndStep,
        protocolCloseStep,
      ]);
      final factory = scenario.factory;
      final db = await factory.openDatabase(inMemoryDatabasePath);

      try {
        await db.transaction((txn) async {});
        fail('should fail');
      } on DatabaseException catch (_) {}
      await db.transaction((txn) async {});
      await db.close();
      scenario.end();
    });
    test('error in begin during open', () async {
      final scenario = startScenario([
        protocolOpenStep,
        [
          'query',
          {'sql': 'PRAGMA user_version', 'id': 1},
          // ignore: inference_failure_on_collection_literal
          {},
        ],
        [
          'execute',
          {
            'sql': 'BEGIN EXCLUSIVE',
            'id': 1,
            'inTransaction': true,
            'transactionId': null
          },
          SqfliteDatabaseException('failure', null),
        ],
        [
          'execute',
          {
            'sql': 'ROLLBACK',
            'id': 1,
            'transactionId': -1,
            'inTransaction': false
          },
          null,
        ],
        protocolCloseStep,
      ]);
      final factory = scenario.factory;
      try {
        await factory.openDatabase(inMemoryDatabasePath,
            options:
                OpenDatabaseOptions(version: 1, onCreate: (db, version) {}));
      } on DatabaseException catch (_) {}
      scenario.end();
    });
  });
}
