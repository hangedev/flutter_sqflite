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
import 'package:sqflite_common/src/batch.dart';
import 'package:sqflite_common/src/constant.dart';
import 'package:sqflite_common/src/database.dart';
import 'package:sqflite_common/src/database_mixin.dart';

/// Transaction param, new in transaction v2
class SqfliteTransactionParam {
  /// null for no transaction
  ///
  final int? transactionId;

  /// Transaction param, new in transaction v2.
  SqfliteTransactionParam(this.transactionId);
}

/// Transaction mixin.
mixin SqfliteTransactionMixin implements Transaction {
  /// Optional transaction id, depending on the implementation
  int? transactionId;
}

/// Transaction implementation
class SqfliteTransaction
    with SqfliteDatabaseExecutorMixin, SqfliteTransactionMixin
    implements Transaction {
  /// Create a transaction on a given [database]
  SqfliteTransaction(this.database);

  /// The transaction database
  @override
  final SqfliteDatabaseMixin database;

  @override
  SqfliteDatabase get db => database;

  /// True if a transaction is successfull
  bool? successful;

  @override
  SqfliteTransaction get txn => this;

  @override
  Batch batch() => SqfliteTransactionBatch(this);
}

/// Special transaction that is run even if a pending transaction is in progress.
SqfliteTransaction getForcedSqfliteTransaction(SqfliteDatabaseMixin database) =>
    SqfliteTransaction(database)..transactionId = paramTransactionIdValueForce;
