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
import 'package:sqflite_common/src/database.dart';
import 'package:sqflite_common/src/mixin/factory.dart';

/// Internal database factory interface.
abstract class SqfliteDatabaseFactory
    implements DatabaseFactory, SqfliteInvokeHandler {
  /// Wrap any exception to a [DatabaseException].
  Future<T> wrapDatabaseException<T>(Future<T> Function() action);

  // To override
  // This also should wrap exception
  //Future<T> safeInvokeMethod<T>(String method, [Object? arguments]);

  /// Create a new database object.
  SqfliteDatabase newDatabase(
      SqfliteDatabaseOpenHelper openHelper, String path);

  /// Remove our internal open helper.
  void removeDatabaseOpenHelper(String path);

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options});

  /// Close the database.
  ///
  /// db.close() calls this right await.
  Future<void> closeDatabase(SqfliteDatabase database);

  @override
  Future<void> deleteDatabase(String path);

  @override
  Future<bool> databaseExists(String path);
}
