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

import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { Tools } from './Tools';
import { BusinessError } from '@ohos.base';
import { Log } from '@ohos/flutter_ohos';
import { Constant } from './OhosConstant';
import deviceInfo from '@ohos.deviceInfo';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import fs from '@ohos.file.fs';
import { HashMap } from '@kit.ArkTS';

export class DatabaseHelper {
  // 已加载的数据库, 存储数据库名称与数据库实例
  public static dbMap: Map<string, relationalStore.RdbStore> = new Map<string, relationalStore.RdbStore>();
  // 加载的数据库, 存储数据库id与数据库名称
  public static dbIdMap: HashMap<number, string> = new HashMap<number, string>();
  // 当前数据库的id
  private static currentDbId: number = 0;
  // 内存数据库映射表: 存储内存数据库ID到临时文件名的映射
  private static memoryDbMap: Map<number, string> = new Map<number, string>();
  // 应用上下文: 用于数据库操作
  private static appContext: common.Context | null = null;
  // 跟踪各数据库当前事务深度, 用于恢复 openDatabase 返回标志
  private static transactionDepthByDbName: Map<string, number> = new Map<string, number>();
  // 按dbName隔离的事务内创建的表记录
  private static transactionCreatedTablesByDbName: Map<string, Set<string>> = new Map<string, Set<string>>();
  // 占位数据库的错误映射: 记录因损坏而延迟失败的 dbId → 错误消息
  // 用途: 对"已存在的损坏数据库"在 openDatabase 阶段先返回成功，后续操作再返回 sqlite_error
  public static invalidOpenDbErrors: HashMap<number, string> = new HashMap<number, string>();

  // 打开一个数据库
  public static async openDatabase(context: common.Context, call: MethodCall, result: MethodResult): Promise<void> {
    if (DatabaseHelper.appContext === null) {
      DatabaseHelper.appContext = context;
    }
    
    let id: number = -1;
    let dbPath: string = call.argument(Constant.PARAM_PATH);
    let isMemoryDb: boolean = false;
    // 内存数据库转换为临时数据库 RdbStore 不支持SQLite :memory:语法
    if (dbPath === Constant.MEMORY_DATABASE_PATH) {
      isMemoryDb = true;
      // 使用时间戳确保每次都是唯一的数据库名称
      const timestamp = Date.now();
      dbPath = `temp_memory_${timestamp}.db`;
    }
    
    let dbPathDirList: string[] = dbPath.split('/');
    let dbName: string = DatabaseHelper.getDatabaseNameByDbPathDirList(dbPathDirList);

    const isExisted: boolean = await DatabaseHelper.checkDatabaseExisted(dbPath);
    let local: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseFromMemory(dbName);
    let recovered: boolean = false;
    let recoveredInTransaction: boolean = false;
    if (isExisted && local != null) {
      // 从通过数据库名称从内存中获取数据库ID
      id = DatabaseHelper.getMemoryDatabaseIdByDatabaseName(dbName);
      recovered = true;
      recoveredInTransaction = DatabaseHelper.isDatabaseInTransaction(dbName);
    } else {
      let readOnly: boolean =
        call.argument(Constant.PARAM_READ_ONLY) == undefined ? false : call.argument(Constant.PARAM_READ_ONLY);
      let config: relationalStore.StoreConfig = DatabaseHelper.createDatabaseConfig(dbPathDirList, dbName, readOnly);

      try {
        let rdbStore = await relationalStore.getRdbStore(context, config);
        DatabaseHelper.dbMap.set(dbName, rdbStore);
        DatabaseHelper.currentDbId = DatabaseHelper.currentDbId + 1;
        id = DatabaseHelper.currentDbId;
        DatabaseHelper.dbIdMap.set(id, dbName);
        // 记录内存数据库的映射关系，用于关闭时清理
        if (isMemoryDb) {
          DatabaseHelper.memoryDbMap.set(id, dbName);
        }
      } catch (err) {
        const error = err as BusinessError;
        const message = error.message ?? JSON.stringify(err);
        Log.e('DatabaseHelper', `open database failed: ${message}`);
        // 对"已存在的损坏数据库文件"做延迟失败处理：openDatabase 先返回成功，
        // 让后续 query/getVersion 返回 sqlite_error 而非 open_failed，
        // 与 Android/iOS 在坏 sqlite 文件上的外部行为保持一致。
        if (isExisted && Number(error.code) === Constant.RDB_ERROR_CODE_14800011) {
          DatabaseHelper.currentDbId = DatabaseHelper.currentDbId + 1;
          id = DatabaseHelper.currentDbId;
          DatabaseHelper.dbIdMap.set(id, dbName);
          DatabaseHelper.invalidOpenDbErrors.set(id, 'file is not a database');

          Log.i('DatabaseHelper', `Deferred corrupt open: id=${id}, name=${dbName}`);
        } else {
          result.error(Constant.SQLITE_ERROR, `${Constant.ERROR_OPEN_FAILED} ${message}`, null);
          return;
        }
      }
    }
    let map: Record<string, Object> = {
      'id': id,
    }
    if (recovered) {
      map['recovered'] = true;
    }
    if (recoveredInTransaction) {
      map['recoveredInTransaction'] = true;
    }
    result.success(map);
  }

  // 检查数据库是否存在
  public static async checkDatabaseExisted(dbPath: string): Promise<boolean> {
    let isExists: boolean = await fs.access(dbPath);
    return isExists;
  }

  // 从已加载的列表里获取一个数据库
  private static getDatabaseFromMemory(dbName: string): relationalStore.RdbStore | null {
    if (DatabaseHelper.dbMap.has(dbName)) {
      return DatabaseHelper.dbMap.get(dbName) as relationalStore.RdbStore | null;
    }
    return null;
  }

  // 从已加载的列表里获取一个数据库
  public static getDatabaseOrError(call: MethodCall, result: MethodResult): relationalStore.RdbStore | null {
    let dbId: number = call.argument(Constant.PARAM_ID);
    let dbName: string | undefined = DatabaseHelper.dbIdMap.get(dbId);
    if (dbName == undefined) {
      result.error('sqlite_error', "database_closed" + dbId, null);
      return null;
    }
    // 占位数据库: 对损坏文件的延迟失败处理
    // openDatabase 阶段先返回成功，后续操作返回 sqlite_error + file is not a database
    // closeDatabase 仍允许正常关闭，返回哑元对象以通过 SqflitePlugin 的前置非空校验
    const invalidOpenError = DatabaseHelper.invalidOpenDbErrors.get(dbId);
    if (invalidOpenError != undefined) {

      if (call.method === Constant.METHOD_CLOSE_DATABASE) {
        return {} as relationalStore.RdbStore;
      }
      result.error(Constant.SQLITE_ERROR, invalidOpenError, null);
      return null;
    }
    let rdbStore = DatabaseHelper.getDatabaseFromMemory(dbName);
    if (rdbStore != null) {
      return rdbStore;
    } else {
      result.error('sqlite_error', "database_closed" + dbId, null);
      return null;
    }
  }
  // 根据数据库 id 维护事务深度。
  // 当 execute 成功进入事务时深度 +1，提交或回滚成功时深度 -1。
  // 这里按 dbName 记录而不是用全局状态，避免多个数据库之间互相污染。
  public static noteTransactionChangeByDbId(dbId: number, inTransactionChange: boolean): void {
    const dbName: string | undefined = DatabaseHelper.dbIdMap.get(dbId);
    if (dbName === undefined) {
      return;
    }
    const currentDepth: number = DatabaseHelper.transactionDepthByDbName.get(dbName) ?? 0;
    const nextDepth = inTransactionChange
      ? currentDepth + 1
      : Math.max(0, currentDepth - 1);
    if (nextDepth > 0) {
      DatabaseHelper.transactionDepthByDbName.set(dbName, nextDepth);
    } else {
      DatabaseHelper.transactionDepthByDbName.delete(dbName);
    }
  }

  // 获取指定数据库的事务深度
  public static getTransactionDepthByDbId(dbId: number): number {
    const dbName: string | undefined = DatabaseHelper.dbIdMap.get(dbId);
    if (dbName === undefined) {
      return -1;
    }
    return DatabaseHelper.transactionDepthByDbName.get(dbName) ?? 0;
  }

  /**
   * 添加事务内创建的表（按dbName隔离）
   * 用于解决多数据库场景下的事务状态隔离问题
   * @param dbName 数据库名称
   * @param tableName 表名（会自动转为小写）
   */
  public static addTransactionCreatedTable(dbName: string, tableName: string): void {
    if (!DatabaseHelper.transactionCreatedTablesByDbName.has(dbName)) {
      DatabaseHelper.transactionCreatedTablesByDbName.set(dbName, new Set<string>());
    }
    DatabaseHelper.transactionCreatedTablesByDbName.get(dbName)!.add(tableName.toLowerCase());
  }

  /**
   * 检查表是否在当前事务内创建（按dbName隔离）
   * 用于处理OHOS RDB的事务隔离问题：在事务内创建表后立即查询该表
   * @param dbName 数据库名称
   * @param tableName 表名（会自动转为小写）
   * @returns true-表在当前事务内创建，false-表不是在当前事务内创建
   */
  public static hasTransactionCreatedTable(dbName: string, tableName: string): boolean {
    const tables = DatabaseHelper.transactionCreatedTablesByDbName.get(dbName);
    return tables ? tables.has(tableName.toLowerCase()) : false;
  }

  /**
   * 清理指定数据库的事务创建表记录（按dbName隔离）
   * 在事务提交或回滚时调用，以及关闭数据库时调用
   * @param dbName 数据库名称
   */
  public static clearTransactionCreatedTablesByDbName(dbName: string): void {
    DatabaseHelper.transactionCreatedTablesByDbName.delete(dbName);
  }

  /**
   * 清理指定数据库的所有事务状态（按dbName隔离）
   * 统一清理事务深度和事务创建表记录，避免残留
   * @param dbName 数据库名称
   */
  public static clearAllTransactionStateByDbName(dbName: string): void {
    if (dbName !== undefined) {
      DatabaseHelper.transactionDepthByDbName.delete(dbName);
      DatabaseHelper.transactionCreatedTablesByDbName.delete(dbName);
    }
  }

  // 判断指定数据库当前是否仍处于事务中。
  // openDatabase 恢复已有单实例数据库时，会据此返回 recoveredInTransaction。
  public static isDatabaseInTransaction(dbName: string): boolean {
    return (DatabaseHelper.transactionDepthByDbName.get(dbName) ?? 0) > 0;
  }

  /**
   * 清理指定数据库缓存的所有事务状态（按dbId查找dbName后清理）
   * 统一清理事务深度和事务创建表记录，避免残留
   * 预留给 close/delete 等场景使用，避免已关闭数据库残留事务信息
   * @param dbId 数据库ID
   */
  public static clearTransactionStateByDbId(dbId: number): void {
    const dbName: string | undefined = DatabaseHelper.dbIdMap.get(dbId);
    if (dbName !== undefined) {
      DatabaseHelper.clearAllTransactionStateByDbName(dbName);
    }
  }

  // 关闭一个数据库
  public static async closeDatabase(call: MethodCall, result: MethodResult): Promise<void> {
    let dbId: number = call.argument(Constant.PARAM_ID);
    let dbName: string | undefined = DatabaseHelper.dbIdMap.get(dbId);
    if (dbName == undefined) {
      result.success(null);
      return;
    }
    // 占位数据库: 清理占位条目并返回成功
    if (DatabaseHelper.invalidOpenDbErrors.hasKey(dbId)) {
      DatabaseHelper.invalidOpenDbErrors.remove(dbId);
      DatabaseHelper.dbIdMap.remove(dbId);
      result.success(null);
      return;
    }
    let local: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseFromMemory(dbName);
    if (local != null) {
      try {
        // 对于损坏的数据库,先从内存移除,避免 close() 挂起
        DatabaseHelper.removeDatabaseFromMemoryByDatabaseName(dbName);
        await DatabaseHelper.closeRdbStoreWithTimeout(local, 'on closeDatabase');

        // 如果是内存数据库，关闭后删除临时文件
        if (DatabaseHelper.memoryDbMap.has(dbId)) {
          const tempDbName = DatabaseHelper.memoryDbMap.get(dbId)!;
          DatabaseHelper.memoryDbMap.delete(dbId);

          // 删除临时数据库文件
          try {
            if (DatabaseHelper.appContext) {
              const config: relationalStore.StoreConfig = {
                name: tempDbName,
                securityLevel: relationalStore.SecurityLevel.S1
              };
              await relationalStore.deleteRdbStore(DatabaseHelper.appContext, config);
            }
          } catch (deleteErr) {
            Log.e('DatabaseHelper', `Failed to delete temp db file: ${JSON.stringify(deleteErr)}`);
          }
        }

        result.success(null);
        return;
      } catch (err) {
        let code = (err as BusinessError).code;
        let message = (err as BusinessError).message;
        result.error('sqlite_error', "close database failed. " + 'error code:' + code + '.  message:' + message, null);
        return;
      }
    } else {
      // 数据库实例已不在内存中时，顺手清理可能残留的事务状态与映射关系
      DatabaseHelper.clearTransactionStateByDbId(dbId);
      // 清理ID
      DatabaseHelper.dbIdMap.remove(dbId);
      result.success(null);
      return;
    }
  }

  // 删除一个数据库
  public static async deleteDatabase(context: common.Context, dbPath: string): Promise<boolean> {
    let result: boolean = false;
    let dbPathDirList: string[] = dbPath.split('/');
    let dbName: string = DatabaseHelper.getDatabaseNameByDbPathDirList(dbPathDirList);

    try {
      // 与 Android 一致：先关闭已打开的数据库，再删除文件
      let local: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseFromMemory(dbName);
      if (local != null) {
        const dbId: number = DatabaseHelper.getMemoryDatabaseIdByDatabaseName(dbName);
        DatabaseHelper.removeDatabaseFromMemoryByDatabaseName(dbName);
        await DatabaseHelper.closeRdbStoreWithTimeout(local, 'before delete');
        if (dbId >= 0 && DatabaseHelper.memoryDbMap.has(dbId)) {
          DatabaseHelper.memoryDbMap.delete(dbId);
        }
      } else {
        // 清理占位数据库的残留条目（仅在 dbIdMap 中有记录的情况）
        // 查找 dbName 对应的所有 dbId
        const dbIdsToRemove: number[] = [];
        DatabaseHelper.dbIdMap.forEach((name: string, id: number) => {
          if (name === dbName) {
            dbIdsToRemove.push(id);
          }
        });
        // 清理 dbIdMap 和 invalidOpenDbErrors
        dbIdsToRemove.forEach((id: number) => {
          DatabaseHelper.dbIdMap.remove(id);
          DatabaseHelper.invalidOpenDbErrors.remove(id);
        });
        // 统一清理所有事务状态
        DatabaseHelper.clearAllTransactionStateByDbName(dbName);
      }

      let config: relationalStore.StoreConfig = DatabaseHelper.createDatabaseConfig(dbPathDirList, dbName);
      await relationalStore.deleteRdbStore(context, config);
      result = true;
      return result;
    } catch (e) {
      Log.e('DatabaseHelper', `deleteRdbStore failed: ${JSON.stringify(e)}`);
      return result;
    }
  }

  // 获取设备版本信息
  public static async getPlatformVersion(call: MethodCall, result: MethodResult): Promise<void> {
    result.success('ohos' + deviceInfo.osFullName);
  }

  // Options操作，设置LogLevel，仅限开发，已被废弃
  public static async options(call: MethodCall, result: MethodResult): Promise<void> {
    let logLevel: number | undefined = call.argument(Constant.PARAM_LOG_LEVEL);
    result.success(null);
  }

  // 设置debug模式，查看SQL查询，已弃用
  public static async debugMode(call: MethodCall, result: MethodResult): Promise<void> {
    let on: boolean = call.args;
    result.success(null);
  }

  // Debug操作,获取数据库信息
  public static async onDebug(call: MethodCall, result: MethodResult): Promise<void> {
    let cmd: string = call.argument(Constant.PARAM_CMD);
    let map: Record<string, Object> = {};

    // Get database info
    if (Constant.CMD_GET === cmd) {
      // 返回数据库列表信息
      if (DatabaseHelper.dbIdMap.length > 0) {
        let databasesInfo: Record<string, Object> = {};
        DatabaseHelper.dbIdMap.forEach((dbName: string, dbId: number) => {
          let info: Record<string, Object> = {};
          // 从 dbMap 中获取数据库路径信息
          // 由于ohos端架构限制,暂时只能提供数据库名称
          info[Constant.PARAM_PATH] = dbName;
          info[Constant.PARAM_SINGLE_INSTANCE] = true; // 默认值
          // 添加事务深度信息
          info['transactionDepth'] = DatabaseHelper.getTransactionDepthByDbId(dbId);
          databasesInfo[dbId.toString()] = info;
        });
        map["databases"] = databasesInfo;
      }
    }
    result.success(map);
  }

  private static createDatabaseConfig(dbNameList: string[], dbName: string,
    isReadOnly?: boolean): relationalStore.StoreConfig {
    //自定义数据库路径
    let customDir: string = '';
    for (let index = Constant.DB_PATH_PARSING_BEGIN_INDEX; index < dbNameList.length - 1; index++) {
      if (customDir.length > 0) {
        customDir = customDir + '/' + dbNameList[index];
      } else {
        customDir = dbNameList[index];
      }
    }

    let customDirPath = customDir.length > 0 ? customDir : undefined;
    let sdkApiVersion = deviceInfo.sdkApiVersion;
    let config: relationalStore.StoreConfig | undefined = undefined;
    if (sdkApiVersion >= Constant.API_17) {
      config = {
        name: dbName, // 数据库文件名
        securityLevel: relationalStore.SecurityLevel.S1, // 数据库安全级别
        customDir: customDirPath,
        tokenizer: relationalStore.Tokenizer.ICU_TOKENIZER,
        isReadOnly: isReadOnly
      }
    } else {
      config = {
        name: dbName, // 数据库文件名
        securityLevel: relationalStore.SecurityLevel.S1, // 数据库安全级别
        customDir: customDirPath,
        isReadOnly: isReadOnly
      }
    }
    return config!;
  }

  private static getDatabaseNameByDbPathDirList(dbPathDirList: string[]): string {
    let dbName: string = dbPathDirList[dbPathDirList.length - 1];
    let endWithDb: boolean = Tools.stringEndWith(dbName, '.db');
    if (!endWithDb) {
      dbName = dbName + '.db';
    }
    return dbName;
  }

  private static getMemoryDatabaseIdByDatabaseName(dbName: string): number {
    let id = -1;
    DatabaseHelper.dbIdMap.forEach((value, key) => {
      if (dbName == value) {
        id = key ?? -1;
      }
    })
    return id;
  }

  private static async closeRdbStoreWithTimeout(local: relationalStore.RdbStore,
    logContext: string): Promise<void> {
    let timerId: number = -1;
    try {
      const closePromise = local.close();
      const timeoutPromise = new Promise<void>((_, reject) => {
        timerId = setTimeout(() => reject(new Error('Close timeout')), 5000);
      });
      try {
        await Promise.race([closePromise, timeoutPromise]);
      } catch (closeErr) {
        Log.e('DatabaseHelper', `rdbStore.close() failed or timeout ${logContext}: ${JSON.stringify(closeErr)}`);
      } finally {
        if (timerId >= 0) {
          clearTimeout(timerId);
        }
      }
    } catch (err) {
      Log.e('DatabaseHelper', `Error closing database ${logContext}: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 从内存中移除数据库实例及相关状态（统一清理入口）
   * 清理 dbMap、事务状态、dbIdMap、invalidOpenDbErrors 的所有相关条目
   * @param dbName 数据库名称
   */
  private static removeDatabaseFromMemoryByDatabaseName(dbName: string) {
    DatabaseHelper.dbMap.delete(dbName);
    DatabaseHelper.clearAllTransactionStateByDbName(dbName);

    // 遍历清理所有匹配 dbName 的 dbId 和 invalidOpenDbErrors
    const dbIdsToRemove: number[] = [];
    DatabaseHelper.dbIdMap.forEach((name: string, id: number) => {
      if (name === dbName) {
        dbIdsToRemove.push(id);
      }
    });
    dbIdsToRemove.forEach((id: number) => {
      DatabaseHelper.dbIdMap.remove(id);
      DatabaseHelper.invalidOpenDbErrors.remove(id);
    });
  }
}