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

/// Sql command type.
enum SqliteSqlCommandType {
  /// such CREATE TABLE, DROP_INDEX, pragma
  execute,

  /// Insert statement,
  insert,

  /// Update statement.
  update,

  /// Delete statement.
  delete,

  /// Query statement (SELECTà
  query,
}

/// Sql command. internal only.
class SqfliteSqlCommand {
  /// The command type.
  final SqliteSqlCommandType type;

  /// The sql statement.
  final String sql;

  /// The sql arguments.
  final List<Object?>? arguments;

  /// Sql command.
  SqfliteSqlCommand(this.type, this.sql, this.arguments);
}
