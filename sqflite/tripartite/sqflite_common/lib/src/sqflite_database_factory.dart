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
import 'package:sqflite_common/src/factory.dart';

SqfliteDatabaseFactory? _databaseFactory;

/// Default database factory.
@visibleForTesting
DatabaseFactory? get databaseFactoryOrNull => _databaseFactory;

/// Change the default factory.
set databaseFactoryOrNull(DatabaseFactory? databaseFactory) {
  if (databaseFactory != null) {
    if (databaseFactory is! SqfliteDatabaseFactory) {
      throw ArgumentError.value(
          databaseFactory, 'databaseFactory', 'Unsupported sqflite factory');
    }
    _databaseFactory = databaseFactory;
  } else {
    /// Unset
    _databaseFactory = null;
  }
}

/// sqflite Default factory.
DatabaseFactory get databaseFactory =>
    _databaseFactory ??
    () {
      throw StateError('''databaseFactory not initialized
databaseFactory is only initialized when using sqflite. When using `sqflite_common_ffi`
You must call `databaseFactory = databaseFactoryFfi;` before using global openDatabase API
''');
    }();

/// Change the default factory.
///
/// Be aware of the potential side effect. Any library using sqflite
/// will have this factory as the default for all operations.
///
/// This setter must be call only once, before any other calls to sqflite.
set databaseFactory(DatabaseFactory? databaseFactory) {
  // Warn when changing. might throw in the future
  if (databaseFactory != null) {
    if (_databaseFactory != null) {
      print('''
*** sqflite warning ***

You are changing sqflite default factory.
Be aware of the potential side effects. Any library using sqflite
will have this factory as the default for all operations.

*** sqflite warning ***
''');
    }
  }
  databaseFactoryOrNull = databaseFactory;
}
