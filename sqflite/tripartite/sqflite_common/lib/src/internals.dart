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

import 'package:meta/meta.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/src/database_mixin.dart';
import 'package:sqflite_common/src/factory.dart';

/// Internal access to invoke method
extension DatabaseFactoryInternalsExt on DatabaseFactory {
  /// Call invoke method manually.
  @visibleForTesting
  Future<T> internalsInvokeMethod<T>(String method, Object? arguments) async {
    return (this as SqfliteDatabaseFactory).invokeMethod<T>(method, arguments);
  }
}

/// Internal access to database configuration
extension DatabaseInternalsExt on Database {
  /// Do not use synchronized to allow concurrent access
  @visibleForTesting
  set internalsDoNotUseSynchronized(bool doNotUseSynchronized) =>
      (this as SqfliteDatabaseMixin).doNotUseSynchronized =
          doNotUseSynchronized;

  /// Internal database id.
  @visibleForTesting
  int? get databaseId => (this as SqfliteDatabaseMixin).id;
}
