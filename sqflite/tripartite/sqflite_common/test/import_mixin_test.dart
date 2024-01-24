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

import 'package:sqflite_common/src/mixin/dev_utils.dart';
import 'package:sqflite_common/src/mixin/import_mixin.dart';
import 'package:test/test.dart';

void main() {
  group('handler_mixin', () {
    // Check that public api are exported
    test('exported', () {
      for (var value in <dynamic>[
        // ignore: deprecated_member_use_from_same_package
        SqfliteOptions,
        methodOpenDatabase,
        methodOpenDatabase,
        methodCloseDatabase,
        methodOptions,
        sqliteErrorCode,
        methodInsert,
        methodQuery,
        methodUpdate,
        methodExecute,
        methodBatch,
        // Factory
        buildDatabaseFactory, SqfliteInvokeHandler, SqfliteDatabaseFactoryBase,
        SqfliteDatabaseFactoryMixin, SqfliteDatabaseFactory,
        // Database
        SqfliteDatabaseOpenHelper, SqfliteDatabase, SqfliteDatabaseMixin,
        SqfliteDatabaseBase,
        // Exception
        SqfliteDatabaseException,
        // ignore: deprecated_member_use_from_same_package
        devPrint, devWarning,
      ]) {
        expect(value, isNotNull);
      }
    });
  });
}
