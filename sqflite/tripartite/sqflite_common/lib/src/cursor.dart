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
import 'package:sqflite_common/src/transaction.dart';

/// Sqflite query cursor wrapper.
class SqfliteQueryCursor implements QueryCursor {
  final SqfliteDatabase _database;

  /// Current transaction if any
  final SqfliteTransaction? txn; // transaction if any

  /// True when closed. moveNext should fail but current row remains ok
  var closed = false;

  /// The native cursor id, null if not supported or if closed
  int? cursorId;

  /// The current result list
  List<Map<String, Object?>> resultList;

  /// The current index
  int currentIndex = -1;

  /// Sqflite query cursor wrapper.
  SqfliteQueryCursor(this._database, this.txn, this.cursorId, this.resultList);

  @override
  Map<String, Object?> get current =>
      _database.txnQueryCursorGetCurrent(txn, this);

  @override
  Future<bool> moveNext() => _database.txnQueryCursorMoveNext(txn, this);

  @override
  Future<void> close() => _database.txnQueryCursorClose(txn, this);
}
