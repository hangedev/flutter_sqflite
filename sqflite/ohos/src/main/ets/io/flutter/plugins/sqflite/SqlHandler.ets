/*
* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
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

import { Operation } from './operation/Operation';
import { relationalStore } from '@kit.ArkData';
import { Tools } from './Tools';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constant } from './OhosConstant';
import { Log } from '@ohos/flutter_ohos';

/// 每个 Handler 都要实现 match + execute
export interface ISqlHandler {
  // 如果能处理此 SQL，就返回 true
  match(sql: string): boolean;
  // 执行逻辑，返回是否执行成功
  execute( sql: string, operation: Operation, db: relationalStore.RdbStore): Promise<boolean> | boolean;
  // 默认 false，表示不走后处理；某些 Handler 可以覆盖为 true
  get needsPostProcess(): boolean;
}

/// 抽象 Handler，提供默认 no-op 实现
abstract class BaseSqlHandler implements ISqlHandler {
  match(sql: string): boolean {
    return false;
  }

  execute(sql: string, operation: Operation, db: relationalStore.RdbStore): Promise<boolean> | boolean {
    return false;
  }

  get needsPostProcess(): boolean {
    return false;
  }
}

/// 事务开始
export class BeginImmediateHandler extends BaseSqlHandler {
  match(sql: string) {
    const upperSql = sql.toUpperCase();
    return upperSql === Constant.SQL_BEGIN_IMMEDIATE ||
           upperSql === Constant.SQL_BEGIN_IMMEDIATE + ' TRANSACTION' ||
           // BEGIN TRANSACTION 在标准 SQLite 中等同 BEGIN DEFERRED TRANSACTION，
           // 但 OHOS relationalStore 的 beginTransaction() 只有一种事务类型（不区分
           // DEFERRED/IMMEDIATE/EXCLUSIVE 的锁语义），此处统一走 beginTransaction()，
           // 对 drift ORM 等下发该命令的场景功能上等价，不影响事务正常开始/提交/回滚。
           upperSql === 'BEGIN TRANSACTION';
  }

  execute(_sql: string, operation: Operation, db: relationalStore.RdbStore): boolean {
    try {
      db.beginTransaction();
      return true;
    } catch (err) {
      // 局部捕获：失败时转 sqlite_error 信封（返回 false 后 execute 主流程不再回 success），
      // 避免异常上抛到 handleOne 兜底导致错误码退化为通用 'error'
      const error = err as BusinessError;
      operation.error(Constant.SQLITE_ERROR,
        `begin transaction failed, error code: ${error.code}. message is ${error.message}`, '');
      return false;
    }
  }

  get needsPostProcess(): boolean {
    return true;
  }
}

/// 提交事务
export class CommitHandler extends BaseSqlHandler {
  match(sql: string) {
    const upperSql = sql.toUpperCase();
    return upperSql === Constant.SQL_COMMIT ||
           upperSql === Constant.SQL_COMMIT + ' TRANSACTION';
  }

  execute(sql: string, operation: Operation, db: relationalStore.RdbStore) {
    try {
      db.commit();
      return true;
    } catch (err) {
      // COMMIT 失败（无活动事务/连接异常）时事务深度不回滚（事务可能仍处于打开状态，
      // 由后续 ROLLBACK 或关库时的 resetTransactionState 收尾），转为 sqlite_error 信封
      const error = err as BusinessError;
      operation.error(Constant.SQLITE_ERROR,
        `commit failed, error code: ${error.code}. message is ${error.message}`, '');
      return false;
    }
  }

  get needsPostProcess(): boolean {
    return true;
  }
}

// 回滚事务
export class RollbackHandler extends BaseSqlHandler {
  match(sql: string) {
    const upperSql = sql.toUpperCase();
    return upperSql === Constant.SQL_ROLLBACK ||
           upperSql === Constant.SQL_ROLLBACK + ' TRANSACTION';
  }

  execute(sql: string, operation: Operation, db: relationalStore.RdbStore) {
    try {
      db.rollBack();
      return true;
    } catch (err) {
      // 回滚失败（如无活动事务）：对齐 Android execSQL("ROLLBACK") 失败传播
      // sqlite_error 的语义（与 CommitHandler 同款），并记日志便于排查
      const error = err as BusinessError;
      Log.e(Constant.TAG, `rollBack failed, error code: ${error.code}. message is ${error.message}`);
      operation.error(Constant.SQLITE_ERROR,
        `rollback failed, error code: ${error.code}. message is ${error.message}`, '');
      return false;
    }
  }

  get needsPostProcess(): boolean {
    return true;
  }
}

/// BEGIN EXCLUSIVE (HarmonyOS SDK暂未支持此事务)
export class BeginExclusiveHandler extends BaseSqlHandler {
  match(sql: string) {
    const upperSql = sql.toUpperCase();
    return upperSql === Constant.SQL_BEGIN_EXCLUSIVE ||
           upperSql === Constant.SQL_BEGIN_EXCLUSIVE + ' TRANSACTION';
  }
  execute(_sql: string, operation: Operation, _db: relationalStore.RdbStore) {
    return true;
  }
  get needsPostProcess(): boolean {
    return true;
  }
}

/// ATTACH
export class AttachHandler extends BaseSqlHandler {
  match(sql: string) {
    return Tools.startsWithIgnoreCase(sql, Constant.SQL_ATTACH);
  }
  execute(sql: string, operation: Operation, db: relationalStore.RdbStore) {
    return this.handleAttach(db, sql, operation);
  }

  private async handleAttach(db: relationalStore.RdbStore, sql: string, operation: Operation): Promise<boolean> {
    const sqlArguments: string[] | undefined = operation.getArgument(Constant.PARAM_SQL_ARGUMENTS);

    const exprPattern = /attach\s+(?:database\s+)?([^\s;]+?)(?:\s+as\s+)/i;
    const exprMatch = sql.match(exprPattern);
    let fullPath: string = '';
    if (exprMatch) {
      const pathToken: string = exprMatch[1].trim();
      if (pathToken === '?') {
        // 防御：? 占位符与参数个数不匹配时不能空引用，回 bad_param 而非抛 TypeError
        if (sqlArguments === undefined || sqlArguments.length < 1) {
          operation.error(Constant.ERROR_BAD_PARAM, 'attach failed: missing path argument for placeholder', '');
          return false;
        }
        fullPath = sqlArguments[0];
      } else {
        fullPath = pathToken;
      }
      // 移除路径两边的引号 (单引号或双引号)
      fullPath = fullPath.replace(/^['"]|['"]$/g, '');
    }

    const schemaPattern = /\s+as\s+([^\s;]+)/i;
    const schemaMatch = sql.match(schemaPattern);
    let attachName: string = '';
    if (schemaMatch) {
      const schemaToken: string = schemaMatch[1].trim();
      if (schemaToken === '?') {
        if (sqlArguments === undefined || sqlArguments.length < 1) {
          operation.error(Constant.ERROR_BAD_PARAM, 'attach failed: missing schema argument for placeholder', '');
          return false;
        }
        attachName = sqlArguments[sqlArguments.length - 1];
      } else {
        attachName = schemaToken;
      }
      // 移除 schema 名称两边的引号
      attachName = attachName.replace(/^['"]|['"]$/g, '');
    }

    try {
      await db.attach(fullPath, attachName);
      operation.success(null);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      operation.error(Constant.SQLITE_ERROR, `attach failed, error code: ${error.code}. message is ${error.message}`, '');
      return false;
    }
  }
}

/// DETACH
export class DetachHandler extends BaseSqlHandler {
  match(sql: string) {
    return Tools.startsWithIgnoreCase(sql, Constant.SQL_DETACH);
  }
  execute(sql: string, operation: Operation, db: relationalStore.RdbStore) {
    return this.handleDetach(db, sql, operation);
  }

  private async handleDetach(db: relationalStore.RdbStore, sql: string, operation: Operation): Promise<boolean> {
    const sqlArguments: string[] | undefined = operation.getArgument(Constant.PARAM_SQL_ARGUMENTS);

    const schemaPattern = /detach\s+(?:database\s+)?([^\s;]+)/i;
    const schemaMatch = sql.match(schemaPattern);
    let attachName: string = '';
    if (schemaMatch) {
      const schemaToken: string = schemaMatch[1].trim();
      if (schemaToken === '?') {
        // 防御：? 占位符与参数个数不匹配时不能空引用，回 bad_param 而非抛 TypeError
        if (sqlArguments === undefined || sqlArguments.length < 1) {
          operation.error(Constant.ERROR_BAD_PARAM, 'detach failed: missing schema argument for placeholder', '');
          return false;
        }
        attachName = sqlArguments[0];
      } else {
        attachName = schemaToken;
      }
    }

    try {
      await db.detach(attachName);
      operation.success(null);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      operation.error(Constant.SQLITE_ERROR, `detach failed, error code: ${error.code}. message is ${error.message}`, '');
      return false;
    }
  }
}