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
import 'package:test/test.dart';

import 'test_scenario.dart';

void main() {
  group('sqflite', () {
    var startCommands = [protocolOpenStep];
    var endCommands = [protocolCloseStep];
    test('batch commit', () async {
      final scenario = startScenario([
        ...startCommands,
        [
          'execute',
          {
            'sql': 'BEGIN IMMEDIATE',
            'id': 1,
            'inTransaction': true,
            'transactionId': null
          },
          null
        ],
        [
          'batch',
          {
            'operations': [
              {'method': 'execute', 'sql': 'PRAGMA dummy'}
            ],
            'id': 1
          },
          null
        ],
        [
          'execute',
          {'sql': 'COMMIT', 'id': 1, 'inTransaction': false},
          null
        ],
        ...endCommands,
      ]);
      final factory = scenario.factory;
      final db = await factory.openDatabase(inMemoryDatabasePath);
      var batch = db.batch();
      expect(batch.length, 0);
      batch.execute('PRAGMA dummy');
      expect(batch.length, 1);
      expect(await batch.commit(), isEmpty); // Mock return values
      await db.close();
      scenario.end();
    });
    test('batch apply', () async {
      final scenario = startScenario([
        ...startCommands,
        [
          'batch',
          {
            'operations': [
              {'method': 'execute', 'sql': 'PRAGMA dummy'}
            ],
            'id': 1
          },
          null
        ],
        ...endCommands,
      ]);
      final factory = scenario.factory;
      final db = await factory.openDatabase(inMemoryDatabasePath);
      var batch = db.batch();
      batch.execute('PRAGMA dummy');
      await batch.apply();
      await db.close();
      scenario.end();
    });
  });
}
