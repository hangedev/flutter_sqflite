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

import common from '@ohos.app.ability.common';
import relationalStore from '@ohos.data.relationalStore';
import { Operation } from './operation/Operation';
import { SqlCommand } from './SqlCommand';
import { ValueType } from '@ohos.data.ValuesBucket';
import { Constant } from './OhosConstant';
import { BusinessError } from '@ohos.base';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { SqlErrorInfo } from './operation/SqlErrorInfo';
import { MethodCallOperation } from './operation/MethodCallOperation';
import { BatchOperation } from './operation/BatchOperation';
import { Any, Log } from '@ohos/flutter_ohos';
import {
  AttachHandler,
  BeginExclusiveHandler,
  BeginImmediateHandler,
  CommitHandler,
  DetachHandler,
  ISqlHandler,
  RollbackHandler
} from './SqlHandler';
import { deviceInfo } from '@kit.BasicServicesKit';


type HandleCallback = (x: Object) => void;

// 分页游标：绑定 ResultSet 与首次查询的 pageSize（对齐 Android SqfliteCursor）
interface SqfliteCursor {
  cursorId: number;
  // 游标归属的数据库 id：关库时按此关闭该库名下的全部分页游标（对齐 Android 关库即关游标）
  dbId: number | undefined;
  pageSize: number | undefined;
  resultSet: relationalStore.ResultSet;
}

export class Database {
  public context: common.Context;
  public path: string;
  public id: number;
  public singleInstance: boolean;
  public logLevel: number;
  private static lastTransactionId: number = 0;
  private static currentTransactionId: number | null;
  private static transactionDepth: number = 0;
  // 当前事务所属的数据库 id：事务状态是跨库共享的全局量，关库清零前必须比对持有者，
  // 否则关闭无关库会把别的库正在进行的事务 depth 清掉（事务内写被自动提交、COMMIT 后 depth 变 -1）
  private static currentTransactionDbId: number | null = null;
  // 跟踪当前事务内创建的表
  private static transactionCreatedTables: Set<string> = new Set();
  // 游标管理用于分页查询（对齐 Android SqfliteCursor：保存 pageSize 供续页复用）
  private static cursorMap: Map<number, SqfliteCursor> = new Map();
  private static lastCursorId: number = 0;
  // 缓存游标数量上限：Dart 侧异常放弃分页（不 cancel 也不读完）且库未关闭时，
  // 防止 entry 永久累积；超限按 cursorId（单调递增，最小即最旧）淘汰
  private static readonly MAX_CACHED_CURSORS: number = 32;

  constructor(context: common.Context, path: string, id: number, singleInstance: boolean, logLevel: number) {
    this.context = context;
    this.path = path;
    this.id = id;
    this.singleInstance = singleInstance;
    this.logLevel = logLevel;
  }

  private static handlers: ISqlHandler[] = [
    new BeginImmediateHandler(),
    new CommitHandler(),
    new RollbackHandler(),
    new BeginExclusiveHandler(),
    new AttachHandler(),
    new DetachHandler()
  ];

  private static enterOrLeaveInTransaction(value: boolean | null, dbId: number | undefined): void {
    if (value == true) {
      if (Database.transactionDepth === 0) {
        // 顶层 BEGIN：记录事务持有库，供关库时判断能否清零全局事务状态
        Database.currentTransactionDbId = dbId === undefined ? null : dbId;
      }
      Database.transactionDepth++;
    } else if (value == false) {
      // 防负值钳制：depth 为 0 时不再递减（裸 ROLLBACK 失败后的清理分支、
      // 或任何非配对调用都不把 depth 打到 -1，-1 会让后续 BEGIN 的顶层判定失真）
      if (Database.transactionDepth > 0) {
        Database.transactionDepth--;
      }
      if (Database.transactionDepth <= 0) {
        Database.currentTransactionDbId = null;
      }
    }
  }

  // 重置事务状态 (关闭数据库时调用)：深度、当前事务 id 与事务内建表记录一并清理，
  // 避免跨数据库残留（currentTransactionId 过期、新库同名表被误判为事务内已创建）。
  // 仅当被关的库恰是当前事务持有者时才清零：关闭无关库不得破坏其他库正在进行的事务
  public static resetTransactionState(dbId: number): void {
    if (Database.currentTransactionDbId != null && Database.currentTransactionDbId !== dbId) {
      return;
    }
    Database.transactionDepth = 0;
    Database.currentTransactionId = null;
    Database.currentTransactionDbId = null;
    Database.clearTransactionCreatedTables();
  }

  // 是否正处于事务中（openDatabase 恢复单实例时上报 recoveredInTransaction 用）
  public static isInTransaction(): boolean {
    return Database.transactionDepth > 0;
  }
  
  // 清空事务内创建的表记录 (提交或回滚时调用)
  public static clearTransactionCreatedTables(): void {
    Database.transactionCreatedTables.clear();
  }

  private static async handleException(operation: Operation, err: BusinessError<void>, db?: relationalStore.RdbStore): Promise<void> {
    let code = err.code;
    let message = err.message;
    // 14800000 是 RDB 通用错误，绝大多数是真实失败，一律转 success(null) 会把失败
    // 静默吞成“假成功”（Dart 侧拿到 null 误以为写入成功）。仅 noResult 批量写入场景
    // （Dart 不消费结果）按历史行为容错为成功，其余按失败上报。
    if (code == Constant.RDB_ERROR_CODE_14800000 && operation.getNoResult()) {
      Log.w(Constant.TAG, `[handleException] code=14800000 with noResult, treated as success. message: ${message}`);
      operation.success(null);
      return;
    } else if (code == Constant.RDB_ERROR_CODE_14800021) {
      Database.handleTableOrSyntaxError(operation, message);
    } else if (code == Constant.RDB_ERROR_CODE_14800032) {
      await Database.handleConstraintViolation(operation, db);
    } else if (code == Constant.RDB_ERROR_CODE_801) {
      operation.error(Constant.SQLITE_ERROR, 'error code:' + code + '。' + " Database is readonly", SqlErrorInfo.getMap(operation));
    } else {
      operation.error(Constant.SQLITE_ERROR, 'error code:' + code + '。' + message, SqlErrorInfo.getMap(operation));
    }
  }

    /**
   * 处理表不存在或语法错误（错误码 14800021）
   */
  private static handleTableOrSyntaxError(operation: Operation, message: string): void {
    let normalizedMessage = message;
    const sql = operation.getSqlCommand()?.getSql() || '';
    // CREATE TABLE 命中 14800021 时只可能是“表已存在”或保留字语法错误，不可能是 no such table，
    // 用于在 message 不含 “already exists” 字样时兜底。
    const createTableMatch = sql.match(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)/i);

    // 表已存在（如 CREATE TABLE 重复建表）：OHOS 的通用文案
    // “Generic error...the updated data does not exist...table X already exists”
    // 同样包含 “does not exist” 字样，必须先于“表不存在”分支判定，避免误报。
    if (message.toLowerCase().includes('already exists')) {
      normalizedMessage = createTableMatch != null
        ? `table ${createTableMatch[1]} already exists`
        : `table already exists`;
    } else if (createTableMatch != null &&
      (message.includes('does not exist') || message.includes('Generic error'))) {
      // 部分设备实测 OHOS 抛出的 BusinessError.message 只含通用文案
      // “SQLite: Generic error...updated data does not exist.”，不含 “already exists” 字样，
      // 因此按 CREATE TABLE 语句类型兜底；保留字表名仍判为语法错误。
      const tableName = createTableMatch[1];
      const isReserved =
        Constant.SQL_RESERVED_WORDS.some(kw => tableName.toLowerCase() === kw.toLowerCase());
      normalizedMessage = isReserved ? `syntax error` : `table ${tableName} already exists`;
    } else if (message.includes('Insert failed') || message.includes('updated data does not') ||
      message.includes('does not exist')) {
      // 判断表不存在：Insert failed | updated data does not exist | does not exist
      normalizedMessage = Database.normalizeTableNotFoundError(operation, message);
    } else if (message.includes('not supported') ||
      (message.includes('Generic error') && !message.includes('Insert failed'))) {
      // 判断语法错误：not supported 或 纯粹的 Generic error（不包含 Insert failed）
      normalizedMessage = `syntax error`;
    }

    operation.error(Constant.SQLITE_ERROR, normalizedMessage, SqlErrorInfo.getMap(operation));
  }

  /**
   * 规范化表不存在错误消息
   */
  private static normalizeTableNotFoundError(operation: Operation, message: string): string {
    // 获取 SQL 语句用于错误类型推断
    const sql = operation.getSqlCommand()?.getSql() || '';
    // 从 SQL 中提取表名
    const tableMatch = sql.match(/(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|FROM|CREATE\s+TABLE)\s+(\w+)/i);
    
    if (tableMatch) {
      const tableName = tableMatch[1];
      // 检查表名是否为SQLite保留字(完整列表)
      const reservedWords = Constant.SQL_RESERVED_WORDS;
      if (reservedWords.some(kw => tableName.toLowerCase() === kw.toLowerCase())) {
        return `syntax error`;
      } else {
        return `no such table: ${tableName}`;
      }
    } else {
      // 无法提取表名时，也返回语法错误
      return `syntax error`;
    }
  }

  /**
   * 处理唯一约束或主键冲突（错误码 14800032）
   */
  private static async handleConstraintViolation(operation: Operation, db?: relationalStore.RdbStore): Promise<void> {
    const sql = operation.getSqlCommand()?.getSql() || '';
    let resultCode = Constant.SQLITE_CONSTRAINT_UNIQUE;
    let errorMessage = 'UNIQUE constraint failed';
    
    const insertMatch = sql.match(/INSERT\s+INTO\s+(\w+)\s*\((\w+)\)/i);
    
    if (insertMatch && db) {
      const tableName = insertMatch[1];
      const columnName = insertMatch[2];
      
      // 检查列是否为主键
      const isPrimaryKey = await Database.checkIfPrimaryKey(db, tableName, columnName);
      if (isPrimaryKey) {
        resultCode = Constant.SQLITE_CONSTRAINT_PRIMARYKEY; // 1555
      }
      
      errorMessage = `UNIQUE constraint failed: ${tableName}.${columnName}`;
    }
    
    const finalMessage = `${errorMessage} (code ${resultCode})`;
    operation.error(Constant.SQLITE_ERROR, finalMessage, SqlErrorInfo.getMap(operation));
  }

  /**
   * 检查列是否为主键
   */
  private static async checkIfPrimaryKey(db: relationalStore.RdbStore, tableName: string, columnName: string): Promise<boolean> {
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await db.querySql(`PRAGMA table_info(${tableName})`);
      while (resultSet.goToNextRow()) {
        const row = resultSet.getRow();
        if (row['name'] === columnName && row['pk'] === 1) {
          return true;
        }
      }
    } catch (e) {
      Log.e(Constant.TAG, `Failed to query table_info: ${e}`);
    } finally {
      // finally 统一关闭：goToNextRow/getRow 中途抛错时 catch 分支原先漏 close，泄漏 native 游标句柄
      if (resultSet != null) {
        try {
          resultSet.close();
        } catch (closeErr) {
          Log.e(Constant.TAG, `Failed to close table_info resultSet: ${closeErr}`);
        }
      }
    }
    return false;
  }

  /**
   * 判断 SQL 是否为 DDL 语句 (需要使用 executeSql 而不是 execute)
   * @param sql SQL 语句
   * @returns true 如果是 DDL 语句
   */
  private static isDDL(sql: string): boolean {
    const upperSql = sql.trim().toUpperCase();
    return upperSql.startsWith('CREATE ') ||
           upperSql.startsWith('DROP ') ||
           upperSql.startsWith('ALTER ') ||
           upperSql.startsWith('TRUNCATE ');
  }

  private static async executeOrError(operation: Operation, db: relationalStore.RdbStore,
    callback?: HandleCallback): Promise<boolean> {
    let command: SqlCommand = operation.getSqlCommand();
    let sqlArguments: ValueType[] | undefined = operation.getArgument(Constant.PARAM_SQL_ARGUMENTS);
    let sql: string = command.getSql();
    let promise: ValueType | undefined;
    try {
      // 防御：并发下解码偶发损坏导致 sql 字段缺失时，返回明确错误，避免 isDDL 里
      // undefined.trim() 抛 TypeError 误导（曾误报为 “Cannot read property trim of undefined”）。
      if (!sql) {
        Log.e(Constant.TAG, '[executeOrError] FAILED: sql is undefined (message decode corrupted)');
        operation.error(Constant.SQLITE_ERROR, 'invalid sql argument: missing sql field',
          SqlErrorInfo.getMap(operation));
        return false;
      }
      // DDL 语句(CREATE/DROP/ALTER)需要使用 executeSql
      const isDDL = Database.isDDL(sql);
      
      if (isDDL) {
        // executeSql 不支持参数，DDL 语句通常也不需要参数
        await db.executeSql(sql);
        // 如果在事务内且是CREATE TABLE,记录表名以处理ohos事务隔离问题
        const transactionId = operation.getTransactionId();
        if (Database.transactionDepth > 0) {
          const createMatch = sql.match(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)/i);
          if (createMatch) {
            const tableName = createMatch[1];
            Database.transactionCreatedTables.add(tableName.toLowerCase());
          }
        }
        promise = undefined; // DDL 语句没有返回值
      } else {
        if (sqlArguments == undefined || sqlArguments.length < 1) {
          promise = await db.execute(sql) as ValueType;
        } else {
          promise = await db.execute(sql, sqlArguments) as ValueType;
        }
      }
      if (callback != undefined && promise !== undefined) {
        callback(promise);
      }
      return true;
    } catch (err) {
      const businessErr = err as BusinessError<void>;
      // RDB 的 execute() 即使走无参重载，对“SQL 含占位符但未绑定参数”也严格校验并
      // 报 14800000；而 SQLite/Android 对未绑定占位符按 NULL 处理（未绑定 -> NULL，
      // WHERE 比较恒假 -> 影响 0 行）。该场景降级用 querySql() 重试（其无参重载
      // 不做占位符校验），对齐 Android 的容忍语义（rawDelete('... name = ?', []) 不报错）
      if (businessErr.code == Constant.RDB_ERROR_CODE_14800000 &&
        !Database.isDDL(sql) && (sqlArguments == undefined || sqlArguments.length < 1)) {
        let rs: relationalStore.ResultSet | null = null;
        try {
          rs = await db.querySql(sql);
          // 未绑定占位符 = NULL 语义：WHERE 比较恒假，影响行数为 0
          promise = 0;
        } catch (retryErr) {
          const retryBusinessErr = retryErr as BusinessError<void>;
          Log.e(Constant.TAG, `[executeOrError] querySql retry FAILED sql="${sql}", ` +
            `code=${retryBusinessErr.code}, message=${retryBusinessErr.message}`);
          await Database.handleException(operation, retryErr, db);
          return false;
        } finally {
          // 对齐 checkIfPrimaryKey/doQuery 的 finally 防护：close 异常不再泄漏句柄，
          // 也不再覆盖已定型的回执结果
          if (rs != null) {
            try {
              rs.close();
            } catch (closeErr) {
              Log.e(Constant.TAG, `[executeOrError] querySql retry rs.close failed: ${closeErr}`);
            }
          }
        }
        if (callback != undefined) {
          callback(promise);
        }
        return true;
      }
      // 诊断：打印失败 SQL 与参数，便于定位 401（Parameter error）/ 14800021 等错误的具体操作。
      // 并发压力下若 sqlArguments 出现 undefined 元素，RDB 会报 "The X must be ValueObject"。
      Log.e(Constant.TAG, `[executeOrError] FAILED sql="${sql}", code=${businessErr.code}, ` +
        `message=${businessErr.message}, argsLen=${sqlArguments?.length}, args0=${sqlArguments?.[0]}`);
      await Database.handleException(operation, err, db);
      return false;
    }
  }

  /// execute
  public static async execute(operation: Operation, db: relationalStore.RdbStore): Promise<void> {
    const sql = operation.getSqlCommand().getSql();
    // 防御：sql 缺失时先回执明确错误（与 executeOrError 同款），否则 handlers 的
    // match() 里 undefined.toUpperCase() 会抛 TypeError、错误码退化为通用 'error'
    if (!sql) {
      operation.error(Constant.SQLITE_ERROR, 'invalid sql argument: missing sql field',
        SqlErrorInfo.getMap(operation));
      return;
    }
    const inTransactionChangeValue: object = operation.getArgument<object>(Constant.PARAM_IN_TRANSACTION_CHANGE);
    const inTransactionChange: boolean | null = (typeof inTransactionChangeValue === 'boolean') ? inTransactionChangeValue as boolean : null;
    const enteringTransaction: boolean = (inTransactionChange === true) && operation.hasNullTransactionId();

    // 仅对事务控制命令输出诊断日志（inTransactionChange 非空表示是 BEGIN/COMMIT/ROLLBACK 类），
    // 避免对高频的普通 INSERT/SELECT/UPDATE 每次都打日志，也避免 Release 下泄露业务 SQL。
    if (inTransactionChange !== null) {
      Log.i(Constant.TAG, `[execute] sql="${sql}", inTransactionChange=${inTransactionChange}, enteringTransaction=${enteringTransaction}`);
    }

    if (enteringTransaction) {
      Database.currentTransactionId = ++(Database.lastTransactionId);
    }

    const handler = Database.handlers.find((h) => h.match(sql));
    let success: boolean;
    if (handler) {
      const result = handler.execute(sql, operation, db);
      success = result instanceof Promise ? await result : result;
    } else {
      success = await Database.executeOrError(operation, db);
    }
    
    if (handler?.needsPostProcess ?? true) {
      if (success && inTransactionChange !== null) {
        Database.enterOrLeaveInTransaction(inTransactionChange, operation.getArgument<number>(Constant.PARAM_ID));
        // 如果是离开事务(COMMIT或ROLLBACK)，清空该事务创建表的记录
        if (inTransactionChange === false) {
          Database.clearTransactionCreatedTables();
        }
      } else if (!success && inTransactionChange === false && handler instanceof RollbackHandler) {
        // ROLLBACK 失败也结束本地事务记账：ROLLBACK 的语义就是结束事务（最常见失败原因
        // "无活动事务"即 RDB 内部事务已不在）。若保留 depth 与事务内建表记录，
        // isInTransaction 与空结果集判定（handleEmptyResultSet 视"事务内建的表"为存在，
        // 返回空数据而非 no such table）将长期失真，仅关库可清理；
        // 与 COMMIT 失败不同——COMMIT 失败时事务可能仍处于打开状态，保留 depth 由
        // 后续 ROLLBACK 或关库时的 resetTransactionState 收尾（对齐 Android）
        Database.enterOrLeaveInTransaction(false, operation.getArgument<number>(Constant.PARAM_ID));
        Database.clearTransactionCreatedTables();
      }
      Database.handleExecute(success, enteringTransaction, operation, inTransactionChange);
    }
  }

  private static handleExecute(executeSuccess: boolean, enteringTransaction: boolean, operation: Operation,
    inTransactionChange: boolean | null) {
    if (!executeSuccess) {
      // Revert if needed
      if (enteringTransaction) {
        Database.currentTransactionId = null;
      }
    } else if (enteringTransaction) {
      /// Return the transaction id;
      if (Database.currentTransactionId != null) {
        let res: Map<String, Object> = new Map();
        res.set(Constant.PARAM_TRANSACTION_ID, Database.currentTransactionId);
        operation.success(res);
      } else {
        operation.success(null);
      }
    } else {
      if (inTransactionChange == false) {
        Database.currentTransactionId = null;
      }
      operation.success(null);
    }
  }

  public static async doExecute(operation: Operation, db: relationalStore.RdbStore, dbId?: number): Promise<boolean> {
    // 对齐 Android batch 内 executeOrError：跟踪事务深度与事务内建表记录，
    // 避免 batch 内 BEGIN/COMMIT 后静态 transactionDepth 失真
    // （dbId 由外层 batch 消息传入：单条 BatchOperation 的 map 不携带 id）
    const inTransactionChangeValue: object = operation.getArgument<object>(Constant.PARAM_IN_TRANSACTION_CHANGE);
    const inTransactionChange: boolean | null =
      (typeof inTransactionChangeValue === 'boolean') ? inTransactionChangeValue as boolean : null;
    let executeSuccess: boolean = await Database.executeOrError(operation, db);
    if (!executeSuccess) {
      return false;
    }
    if (inTransactionChange !== null) {
      Database.enterOrLeaveInTransaction(inTransactionChange, dbId);
      // 离开事务(COMMIT或ROLLBACK)时清空该事务创建表的记录
      if (inTransactionChange === false) {
        Database.clearTransactionCreatedTables();
      }
    }
    operation.success(null);
    return true;
  }

  /// insert
  public static async insert(operation: Operation, db: relationalStore.RdbStore): Promise<void> {
    await Database.doInsert(operation, db);
  }

  private static async doInsert(operation: Operation, db: relationalStore.RdbStore): Promise<boolean> {
    let rowIdResult: number = 0; 
    // 使用 callback 捕获 executeOrError 返回的 rowId
    let executeSuccess: boolean = await Database.executeOrError(operation, db, (rowId) => {
      rowIdResult = rowId as number;
    });
    if (!executeSuccess) {
      return false;
    }

    // 如果不需要返回结果，直接返回 null
    if (operation.getNoResult()) {
      operation.success(null);
      return true;
    }
    
    // 如果 rowId <= 0 (比如 ON CONFLICT IGNORE),返回 null（对齐 Android changes()==0 的语义）
    if (rowIdResult <= 0) {
      operation.success(null);
      return true;
    }
    
    // 正常情况,返回 executeOrError 已经设置的 rowId
    operation.success(rowIdResult);
    return true;
  }

  /// update
  public static async update(operation: Operation, db: relationalStore.RdbStore): Promise<void> {
    await Database.doUpdate(operation, db);
  }

  private static async doUpdate(operation: Operation, db: relationalStore.RdbStore): Promise<boolean> {
    let executeSuccess: boolean = await Database.executeOrError(operation, db, (rows) => {
      operation.success(rows);
    });
    if (!executeSuccess) {
      return false;
    }

    // don't get last id if not expected
    if (operation.getNoResult()) {
      operation.success(null);
      return true;
    }
    return true;
  }

  /// query
  public static async query(operation: Operation, db: relationalStore.RdbStore): Promise<void> {
    await Database.doQuery(operation, db);
  }

  /// queryCursorNext - 获取游标的下一页数据
  // 改为 async：worker 串行队列依赖 queryCursorNext 完成后 captured 才写入，
  // catch 里的 handleException 是异步的（14800032 分支 await handleConstraintViolation），
  // 不 await 会在 captured=null 时提前回 null reply -> MissingPluginException。
  public static async queryCursorNext(operation: Operation): Promise<void> {
    const cursorId: number = operation.getArgument(Constant.PARAM_CURSOR_ID);
    const cancel: boolean = operation.getArgument(Constant.PARAM_CANCEL) ?? false;
    
    // 如果是取消操作，关闭并删除游标
    if (cancel) {
      Database.closeCursor(cursorId);
      operation.success(null);
      return;
    }
    
    // 获取保存的分页游标（Dart 侧续页调用不携带 pageSize，须复用首次查询保存的页长）
    const sqfliteCursor = Database.cursorMap.get(cursorId);
    if (!sqfliteCursor) {
      operation.error(Constant.SQLITE_ERROR, `Cursor not found: ${cursorId}`, SqlErrorInfo.getMap(operation));
      return;
    }
    const resultSet = sqfliteCursor.resultSet;

    let cursorHasMoreData = false;

    try {
      // 继续读取下一页数据
      let results = Database.handleQuerySqlResult(resultSet, sqfliteCursor.pageSize);

      // 判断是否还有更多数据
      cursorHasMoreData = Database.cursorHasMoreData(resultSet);

      if (cursorHasMoreData) {
        // 继续保存 cursorId
        results.set(Constant.PARAM_CURSOR_ID, cursorId as Object);
      }

      operation.success(results);
    } catch (err) {
      await Database.handleException(operation, err as BusinessError<void>);
      cursorHasMoreData = false;
    } finally {
      // 没有更多数据时关闭游标
      if (!cursorHasMoreData) {
        Database.closeCursor(cursorId);
      }
    }
  }
  
  /// closeCursor - 关闭并删除游标
  private static closeCursor(cursorId: number): void {
    const sqfliteCursor = Database.cursorMap.get(cursorId);
    if (sqfliteCursor) {
      try {
        sqfliteCursor.resultSet.close();
      } catch (err) {
        Log.e('Database', `Error closing cursor ${cursorId}: ${err}`);
      } finally {
        // 无论 close 是否抛异常都删除条目（对齐 closeAllCursors/closeCursorsOfDatabase）：
        // 条目残留时 evictCursorsOverLimit 的 while 会反复选中同一关不掉的最旧游标，
        // 无限循环挂死 worker 串行队列（全部 sqflite 操作永久阻塞）
        Database.cursorMap.delete(cursorId);
      }
    }
  }

  /// closeAllCursors - 关闭并清空全部缓存游标（全局清理入口，worker 异常恢复等场景调用）
  public static closeAllCursors(): void {
    Database.cursorMap.forEach((sqfliteCursor: SqfliteCursor, cursorId: number) => {
      try {
        sqfliteCursor.resultSet.close();
      } catch (err) {
        Log.e('Database', `Error closing cursor ${cursorId}: ${err}`);
      }
    });
    Database.cursorMap.clear();
  }

  /// 缓存游标数超上限时按最旧（cursorId 最小）淘汰，close+delete 成对释放
  private static evictCursorsOverLimit(): void {
    while (Database.cursorMap.size > Database.MAX_CACHED_CURSORS) {
      let oldestCursorId: number = -1;
      Database.cursorMap.forEach((_sqfliteCursor: SqfliteCursor, cursorId: number) => {
        if (oldestCursorId === -1 || cursorId < oldestCursorId) {
          oldestCursorId = cursorId;
        }
      });
      if (oldestCursorId === -1) {
        break;
      }
      Database.closeCursor(oldestCursorId);
    }
  }

  /// closeCursorsOfDatabase - 关闭并删除指定数据库名下的全部分页游标
  // 对齐 Android “关库即关游标” 语义：closeDatabase 时调用，
  // 避免 Dart 侧未消费完/未 cancel 的 ResultSet 永久滞留 cursorMap 造成句柄泄漏
  public static closeCursorsOfDatabase(dbId: number): void {
    Database.cursorMap.forEach((sqfliteCursor: SqfliteCursor, cursorId: number) => {
      if (sqfliteCursor.dbId === dbId) {
        try {
          sqfliteCursor.resultSet.close();
        } catch (err) {
          Log.e('Database', `Error closing cursor ${cursorId} of database ${dbId}: ${err}`);
        }
        Database.cursorMap.delete(cursorId);
      }
    });
  }

  /// 是否还有未读取的分页数据
  // 等价 Android 的 !(cursor.isLast() || cursor.isAfterLast())：
  // isAtLastRow 未覆盖“已越过最后一行/空结果集”状态（rowCount=0 时 isAtLastRow
  // 恒为 false，会误判还有数据，导致 Dart 侧多一次空页往返甚至死循环），
  // 须补 isEnded 与空集判定。
  private static cursorHasMoreData(resultSet: relationalStore.ResultSet): boolean {
    return resultSet.rowCount > 0 && !resultSet.isAtLastRow && !resultSet.isEnded;
  }

  /**
   * 处理用户版本查询
   * 改为 async：catch 里的 handleException 是异步的（14800032 分支内部有 await），
   * 不 await 会在 error 信封写入 captured 前就返回，worker 以 null 回执，Dart 收到 null 而非错误
   */
  private static async handleUserVersionQuery(operation: Operation, db: relationalStore.RdbStore): Promise<boolean> {
    try {
      let versionMap: Map<String, object> = new Map<String, object>();
      versionMap.set(Constant.PARAM_COLUMNS, ['user_version']);
      versionMap.set(Constant.PARAM_ROWS, [[db.version]]);
      operation.success(versionMap);
      return true;
    } catch (err) {
      await Database.handleException(operation, err as BusinessError<void>);
      Log.e('Database', `doQuery err ${err}`);
      return false;
    }
  }

  /**
   * 执行 SQL 查询并返回 ResultSet
   */
  private static async executeQuery(sql: string, sqlArguments: ValueType[] | undefined, db: relationalStore.RdbStore): Promise<relationalStore.ResultSet> {
    // 空参数组（含空数组）走无参重载：RDB 会对占位符数与绑定参数数做严格校验，
    // 而 SQLite 对未绑定占位符按 NULL 处理（Android 行为），与 executeOrError 路径一致
    if (sqlArguments != undefined && sqlArguments.length > 0) {
      return await db.querySql(sql, sqlArguments);
    } else {
      return await db.querySql(sql);
    }
  }

  /**
   * 验证查询结果，检查表是否存在
   */
  private static async validateQueryResult(operation: Operation, resultSet: relationalStore.ResultSet,
    sql: string): Promise<boolean> {
    // querySql 在表不存在或SQL语法错误时不会抛出异常，而是返回 columnCount=0 的空结果，需要检测这种情况并主动抛出异常
    if (resultSet.columnCount === 0) {
      return await Database.handleEmptyResultSet(operation, sql);
    }
    return true;
  }

  /**
   * 处理空结果集（表不存在或语法错误）
   */
  private static async handleEmptyResultSet(operation: Operation, sql: string): Promise<boolean> {
    const tableMatch = sql.match(/FROM\s+(\w+)/i);

    if (tableMatch) {
      const tableName = tableMatch[1];
      const tableNameLower = tableName.toLowerCase();

      // 检查表是否在当前事务内创建
      if (Database.transactionDepth <= 0 || !Database.transactionCreatedTables.has(tableNameLower)) {
        const reservedTableNames = ['table', 'index', 'group', 'order', 'select', 'where'];
        const isReservedTableName = reservedTableNames.includes(tableNameLower);

        const errorMessage = isReservedTableName ? 'Generic error' : `Table does not exist: ${tableName}`;
        await Database.handleException(operation, {
          code: Constant.RDB_ERROR_CODE_14800021,
          message: errorMessage
        } as BusinessError<void>);
        return false;
      }
    } else {
      // 无法提取表名，说明SQL语法错误
      await Database.handleException(operation, {
        code: Constant.RDB_ERROR_CODE_14800021,
        message: `syntax error`
      } as BusinessError<void>);
      return false;
    }

    return true;
  }

  /**
   * 处理游标分页（保存 ResultSet 与 pageSize 以便后续分页）
   */
  private static handleCursorPagination(resultSet: relationalStore.ResultSet, cursorPageSize: number | undefined,
    results: Map<String, object>, dbId: number | undefined): number | null {
    // 判断是否需要保存分页游标
    let hasMoreData = false;
    if (cursorPageSize != null && cursorPageSize > 0) {
      hasMoreData = Database.cursorHasMoreData(resultSet);
    }

    if (hasMoreData) {
      // 保存游标（含归属 dbId 与 pageSize，续页复用）
      Database.lastCursorId++;
      const savedCursorId = Database.lastCursorId;
      const sqfliteCursor: SqfliteCursor = {
        cursorId: savedCursorId,
        dbId: dbId,
        pageSize: cursorPageSize,
        resultSet: resultSet
      };
      Database.cursorMap.set(savedCursorId, sqfliteCursor);
      results.set(Constant.PARAM_CURSOR_ID, savedCursorId as Object);
      // 超过缓存上限时淘汰最旧游标，防止 Dart 侧弃用分页导致的慢性累积
      Database.evictCursorsOverLimit();
      return savedCursorId;
    }

    return null;
  }

  private static async doQuery(operation: Operation, db: relationalStore.RdbStore): Promise<boolean> {
    let command: SqlCommand = operation.getSqlCommand();
    let sql: string = command.getSql();

    // 特殊处理：用户版本查询
    if (sql == Constant.SQL_PRAGMA_USER_VERSION) {
      return await Database.handleUserVersionQuery(operation, db);
    }

    let cursorPageSize: number | undefined = operation.getArgument(Constant.PARAM_CURSOR_PAGE_SIZE);
    let sqlArguments: ValueType[] | undefined = operation.getArgument(Constant.PARAM_SQL_ARGUMENTS);
    // 游标归属的数据库 id：关库时按此关闭该库名下的全部分页游标
    let dbId: number | undefined = operation.getArgument<number>(Constant.PARAM_ID);
    let resultSet: relationalStore.ResultSet | null = null;
    let savedCursorId: number | null = null;

    try {
      // 执行查询
      resultSet = await Database.executeQuery(sql, sqlArguments, db);

      // 验证查询结果
      if (!await Database.validateQueryResult(operation, resultSet, sql)) {
        return false;
      }

      // 读取数据
      let results = Database.handleQuerySqlResult(resultSet, cursorPageSize);

      // 处理游标分页
      savedCursorId = Database.handleCursorPagination(resultSet, cursorPageSize, results, dbId);

      operation.success(results);
      return true;

    } catch (err) {
      Log.e('Database', `doQuery caught exception: code=${(err as BusinessError<void>).code}, message=${(err as BusinessError<void>).message}`);
      // handleException 是 async（14800032 分支内部还要查 PRAGMA table_info），必须 await：
      // 否则 error 信封尚未写入 captured 就返回，worker 会以 null 回执，
      // Dart 侧收到 null 而非 error 信封（与 queryCursorNext 已修复的同一问题）
      await Database.handleException(operation, err as BusinessError<void>, db);
      // 异常时清理已保存的游标（closeCursor 同时关闭 ResultSet 并移除映射，避免句柄泄漏）
      if (savedCursorId !== null) {
        Database.closeCursor(savedCursorId);
      }
      return false;
    } finally {
      // 如果没有保存，就关闭 ResultSet；close 自身也可能抛异常（句柄已失效等），
      // 防护后仅记日志，避免掩盖 try 块已写入的正常/错误回执
      if (savedCursorId == null && resultSet != null) {
        try {
          resultSet.close();
        } catch (closeErr) {
          Log.e('Database', `Failed to close resultSet in doQuery finally: ${closeErr}`);
        }
      }
    }
  }

  private static handleQuerySqlResult(resultSet: relationalStore.ResultSet,
    cursorPageSize: number | undefined): Map<String, object> {
    let results: Map<String, object> = new Map<String, Object>();
    let rows: Array<Array<Object>> = new Array<Array<Object>>();
    let columns: Array<string> | null = null;
    let valuesType: Array<string> | null = null;
    let columnCount: number = 0;

    // resultSet是一个数据集合得游标，默认值想第-1个记录，有效的数据从0开始
    while (resultSet.goToNextRow()) {
      if (columns == null) {
        columnCount = resultSet.columnCount;
        columns = new Array<string>();
        valuesType = new Array<string>();
        let row: Record<string, ValueType> = resultSet.getRow() as Record<string, ValueType>;
        for (let i = 0; i < columnCount; i++) {
          let columnName = resultSet.getColumnName(i);
          columns.push(columnName);
          let valueType: string = typeof row[columnName];
          valuesType.push(valueType);
        }
        results.set(Constant.PARAM_COLUMNS, columns);
        results.set(Constant.PARAM_ROWS, rows);
      }

      let row = Database.cursorRowToList(resultSet, columnCount, valuesType);
      rows.push(row);

      // 分页支持：读够指定数量后停止
      if (cursorPageSize != null && cursorPageSize > 0) {
        if (rows.length >= cursorPageSize) {
          break;
        }
      }
    }

    return results;
  }

  static cursorRowToList(cursor: relationalStore.ResultSet, length: number,
    valuesType: Array<string> | null): Array<Object> {
    let list = new Array<Object>();

    for (let i = 0; i < length; i++) {
      let value: Object = Database.cursorValue(cursor, i, valuesType![i]);
      list.push(value);
    }
    return list;
  }

  static cursorValue(cursor: relationalStore.ResultSet, index: number, valueType: Any | null): Any {
    if ('number' === valueType) {
      let value = cursor.getString(index);
      if(value) {
        let isIntegerString = /^-?\d+$/.test(value);
        if (isIntegerString) {
          let valueBig = BigInt(value);
          if (valueBig > Number.MAX_SAFE_INTEGER || valueBig < Number.MIN_SAFE_INTEGER) {
            return valueBig;
          } else {
            return cursor.getValue(index);
          }
        }
      }
    }
    return cursor.getValue(index);
  }

  /// batch
  public static async batch(call: MethodCall, result: MethodResult, db: relationalStore.RdbStore): Promise<void> {

    let mainOperation: MethodCallOperation = new MethodCallOperation(call, result);
    let noResult: boolean = mainOperation.getNoResult();
    let continueOnError: boolean = mainOperation.getContinueOnError();

    let operations: Array<Map<string, Object>> =
      mainOperation.getArgument(Constant.PARAM_OPERATIONS) as Array<Map<string, Object>>;
    // 防御畸形消息：operations 缺失/非数组时直接回 bad_param，
    // 避免下方 operations.length 抛 TypeError（错误语义退化为通用 'error' 码）
    if (!Array.isArray(operations)) {
      result.error(Constant.ERROR_BAD_PARAM, 'Batch argument operations is null or not an array', null);
      return;
    }
    let results: Array<Map<string, Object>> = new Array();

    for (let index = 0; index < operations.length; index++) {

      const map: Map<string, Object> = operations[index];
      let operation: BatchOperation = new BatchOperation(map, noResult);
      const method: string = operation.getMethod();

      let executeSuc: boolean;
      switch (method) {
        case Constant.METHOD_EXECUTE:
          executeSuc = await Database.doExecute(operation, db, mainOperation.getArgument<number>(Constant.PARAM_ID));
          if (executeSuc) {
            operation.handleSuccess(results);
          } else if (continueOnError) {
            operation.handleErrorContinue(results);
          } else {
            operation.handleError(result);
            return;
          }
          break;
        case Constant.METHOD_INSERT:
          executeSuc = await Database.doInsert(operation, db);
          if (executeSuc) {
            operation.handleSuccess(results);
          } else if (continueOnError) {
            operation.handleErrorContinue(results);
          } else {
            operation.handleError(result);
            return;
          }
          break;
        case Constant.METHOD_QUERY:
          executeSuc = await Database.doQuery(operation, db);
          if (executeSuc) {
            operation.handleSuccess(results);
          } else if (continueOnError) {
            operation.handleErrorContinue(results);
          } else {
            operation.handleError(result);
            return;
          }
          break;
        case Constant.METHOD_UPDATE:
          executeSuc = await Database.doUpdate(operation, db);
          if (executeSuc) {
            operation.handleSuccess(results);
          } else if (continueOnError) {
            operation.handleErrorContinue(results);
          } else {
            operation.handleError(result);
            return;
          }
          break;
        default:
          result.error(Constant.ERROR_BAD_PARAM, "Batch method " + method + " not supported", null);
          return;
      }
    }
    if (noResult) {
      result.success(null);
    } else {
      result.success(results);
    }
  }
}