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
import { Any, Log } from '@ohos/flutter_ohos';
import { Constant } from './OhosConstant';
import deviceInfo from '@ohos.deviceInfo';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import fs from '@ohos.file.fs';
import { HashMap } from '@kit.ArkTS';
import { Database } from './Database';

export class DatabaseHelper {
  // 已加载的数据库, 存储数据库id与数据库实例
  // （以 id 而非路径为键：同一路径以 singleInstance=false 多次打开时是多个独立实例，
  // 按路径为键会互相覆盖——旧实例句柄泄漏且 closeDatabase 会误关新实例）
  public static dbMap: Map<number, relationalStore.RdbStore> = new Map<number, relationalStore.RdbStore>();
  // 加载的数据库, 存储数据库id与数据库完整路径
  public static dbIdMap: HashMap<number, string> = new HashMap<number, string>();
  /// 加载的数据库, 存储数据库id与是否只读
  public static dbIdOnlyMap: HashMap<number, boolean> = new HashMap<number, boolean>();
  // 打开失败的占位数据库: id -> 懒失败错误信息（文件存在但损坏时对齐上游懒失败语义，
  // 后续操作回 sqlite_error / file is not a database，见 getDatabaseOrError）
  public static invalidOpenDbErrors: HashMap<number, string> = new HashMap<number, string>();
  // 单实例表: 存储以单实例打开的数据库完整路径与数据库id
  // （对齐 Android _singleInstancesByPath）
  private static singleInstanceByPath: Map<string, number> = new Map<string, number>();
  // 当前数据库的id
  private static currentDbId: number = 0;
  // 内存数据库映射表: 存储内存数据库ID到临时文件名的映射
  private static memoryDbMap: Map<number, string> = new Map<number, string>();
  // 应用上下文: 用于数据库操作
  private static appContext: common.Context | null = null;
  // 插件日志级别（0 none / 1 sql / 2 verbose），options/debugMode 可修改
  private static currentLogLevel: number = Constant.LOG_LEVEL_NONE;

  public static getLogLevel(): number {
    return DatabaseHelper.currentLogLevel;
  }

  // 打开一个数据库
  public static async openDatabase(context: common.Context, call: MethodCall, result: MethodResult): Promise<void> {
    if (DatabaseHelper.appContext === null) {
      DatabaseHelper.appContext = context;
    }

    let dbPath: string = call.argument(Constant.PARAM_PATH);
    // 参数校验：path 缺失/类型错误时回 bad_param，避免后续 split/建库抛出误导性错误
    if (typeof dbPath !== 'string' || dbPath.length === 0) {
      result.error(Constant.ERROR_BAD_PARAM, 'Invalid null or empty path argument for openDatabase', null);
      return;
    }
    let isMemoryDb: boolean = false;
    // 内存数据库转换为临时数据库 RdbStore 不支持SQLite :memory:语法
    if (dbPath === Constant.MEMORY_DATABASE_PATH) {
      isMemoryDb = true;
      // 使用时间戳确保每次都是唯一的数据库名称
      const timestamp = Date.now();
      dbPath = Constant.MEMORY_DB_TEMP_PREFIX + timestamp + '.db';
    }

    // singleInstance 缺省为 true；内存数据库强制为 false（每次打开独立实例），
    // 语义对齐 Android SqflitePlugin.onOpenDatabaseCall
    const singleInstanceArg: Any = call.argument(Constant.PARAM_SINGLE_INSTANCE);
    const singleInstance: boolean = singleInstanceArg !== false && !isMemoryDb;

    // 单实例复用：同一路径已打开时直接返回已有实例（recovered=true），
    // 避免对同一文件重复 getRdbStore 产生两个实例导致写入互相覆盖
    if (singleInstance) {
      const existingId: number | undefined = DatabaseHelper.singleInstanceByPath.get(dbPath);
      // 命中正常实例或懒失败占位条目（损坏库）均按单实例复用返回，
      // 避免重复 open 同一损坏库时每次新建占位条目、旧条目成为孤儿
      if (existingId != undefined &&
        (DatabaseHelper.dbMap.has(existingId) || DatabaseHelper.invalidOpenDbErrors.hasKey(existingId))) {
        const recoveredMap: Record<string, Object> = {
          'id': existingId,
          'recovered': true,
          'recoveredInTransaction': Database.isInTransaction(),
        };
        result.success(recoveredMap);
        return;
      }
    }

    let dbPathDirList: string[] = dbPath.split('/');
    let dbName: string = DatabaseHelper.getDatabaseNameByDbPathDirList(dbPathDirList);
    let readOnly: boolean =
      call.argument(Constant.PARAM_READ_ONLY) == undefined ? false : call.argument(Constant.PARAM_READ_ONLY);
    let id: number = -1;

    try {
      let config: relationalStore.StoreConfig = DatabaseHelper.createDatabaseConfig(dbPathDirList, dbName, readOnly);
      let rdbStore = await relationalStore.getRdbStore(context, config);
      DatabaseHelper.currentDbId = DatabaseHelper.currentDbId + 1;
      id = DatabaseHelper.currentDbId;
      DatabaseHelper.dbMap.set(id, rdbStore);
      DatabaseHelper.dbIdMap.set(id, dbPath);
      DatabaseHelper.dbIdOnlyMap.set(id, readOnly);
      if (singleInstance) {
        DatabaseHelper.singleInstanceByPath.set(dbPath, id);
      }
      // 记录内存数据库的映射关系，用于关闭时清理
      if (isMemoryDb) {
        DatabaseHelper.memoryDbMap.set(id, dbPath);
      }
    } catch (err) {
      const e = err as BusinessError;
      // 文件存在且 getRdbStore 报"数据库文件异常/损坏"（14800011，典型：非 SQLite 格式）：
      // 对齐上游懒失败语义——iOS/Android 的 open 不在打开阶段抛 "not a database"，
      // 而是返回成功、推迟到首次操作报错；上游用例 "Open non sqlite file" 依赖该行为
      // （其 db.close() 不在 try-catch 内，open 阶段抛异常会让用例直接失败）。
      // 占位条目后续操作回 sqlite_error / file is not a database（getDatabaseOrError 查
      // invalidOpenDbErrors），而非误导性的 database_closed。
      let fileExists: boolean = false;
      try {
        fileExists = await DatabaseHelper.checkDatabaseExists(dbPath);
      } catch (accessErr) {
        fileExists = false;
      }
      if (fileExists && Number(e.code) === Constant.RDB_ERROR_CODE_14800011) {
        // 创建占位条目并登记懒失败错误：本次 open 返回成功，后续操作报 file is not a database
        DatabaseHelper.currentDbId = DatabaseHelper.currentDbId + 1;
        id = DatabaseHelper.currentDbId;
        DatabaseHelper.dbIdMap.set(id, dbPath);
        DatabaseHelper.dbIdOnlyMap.set(id, readOnly);
        DatabaseHelper.invalidOpenDbErrors.set(id, 'file is not a database');
        // 与正常打开一致登记单实例表，使同路径重复 open 命中上面的占位复用分支
        if (singleInstance) {
          DatabaseHelper.singleInstanceByPath.set(dbPath, id);
        }
        Log.i('DatabaseHelper', `Deferred corrupt open: id=${id}, path=${dbPath}, code=${e.code}`);
      } else {
        // 其余真失败（路径非法/目录不存在/权限/文件不存在）：立即向 Dart 报错
        // （open_failed + path），Dart 侧 isOpenFailedError 依赖该前缀（对齐 Android）
        result.error(Constant.SQLITE_ERROR,
          Constant.ERROR_OPEN_FAILED + ' ' + dbPath + '. error code:' + e.code + '. message:' + e.message, null);
        return;
      }
    }
    let map: Record<string, Object> = {
      'id': id,
      'recovered': false,
      'recoveredInTransaction': false,
    }
    result.success(map);
  }

  // 检查数据库是否存在
  public static async checkDatabaseExists(dbPath: string): Promise<boolean> {
    let isExists: boolean = await fs.access(dbPath);
    return isExists;
  }

  // 从已加载的列表里获取一个数据库（按 id 索引，多实例同路径互不干扰）
  private static getDatabaseFromMemory(dbId: number): relationalStore.RdbStore | null {
    if (DatabaseHelper.dbMap.has(dbId)) {
      return DatabaseHelper.dbMap.get(dbId) as relationalStore.RdbStore | null;
    }
    return null;
  }

  // 从已加载的列表里获取一个数据库
  public static getDatabaseOrError(call: MethodCall, result: MethodResult): relationalStore.RdbStore | null {
    let dbId: number = call.argument(Constant.PARAM_ID);
    // 参数校验：id 缺失/类型错误时回 bad_param
    if (typeof dbId !== 'number') {
      result.error(Constant.ERROR_BAD_PARAM, 'Invalid null id argument', null);
      return null;
    }
    let dbPath: string | undefined = DatabaseHelper.dbIdMap.get(dbId);
    if (dbPath == undefined) {
      result.error(Constant.SQLITE_ERROR, Constant.ERROR_DATABASE_CLOSED + ' ' + dbId, null);
      return null;
    }
    // 占位数据库（损坏文件的懒失败）：除 close 外的任何操作回 file is not a database
    // （对齐 Android/iOS 首次查询坏文件的报错文本；closeDatabase 不经此入口，可直接关闭占位条目）
    const invalidOpenError: string | undefined = DatabaseHelper.invalidOpenDbErrors.get(dbId);
    if (invalidOpenError != undefined) {
      result.error(Constant.SQLITE_ERROR, invalidOpenError, null);
      return null;
    }
    let rdbStore = DatabaseHelper.getDatabaseFromMemory(dbId);
    if (rdbStore != null) {
      return rdbStore;
    } else {
      result.error(Constant.SQLITE_ERROR, Constant.ERROR_DATABASE_CLOSED + ' ' + dbId, null);
      return null;
    }
  }

  // 关闭一个数据库
  public static async closeDatabase(call: MethodCall, result: MethodResult): Promise<void> {
    let dbId: number = call.argument(Constant.PARAM_ID);
    // 参数校验：id 缺失/类型错误时回 bad_param
    if (typeof dbId !== 'number') {
      result.error(Constant.ERROR_BAD_PARAM, 'Invalid null id argument for closeDatabase', null);
      return;
    }
    let dbPath: string | undefined = DatabaseHelper.dbIdMap.get(dbId);
    if (dbPath === undefined) {
      // 该 id 不在已打开列表（前置 getDatabaseOrError 已拦截此场景）：仍必须回执，避免 Dart 侧挂起
      result.error(Constant.SQLITE_ERROR, Constant.ERROR_DATABASE_CLOSED + ' ' + dbId, null);
      return;
    }
    let local: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseFromMemory(dbId);
    if (local != null) {
      try {
        // 对于损坏的数据库,先从内存移除,避免 close() 挂起
        DatabaseHelper.removeDatabaseFromMemory(dbId);
        // 对齐 Android “关库即关游标”：关闭并清理该库名下的全部分页游标，避免 ResultSet 滞留 cursorMap
        Database.closeCursorsOfDatabase(dbId);
        // 使用 Promise.race 添加超时保护
        const closePromise = local.close();
        let closeTimerId: number = -1;
        const timeoutPromise = new Promise<void>((_, reject) => {
          closeTimerId = setTimeout(() => reject(new Error('Close timeout')), 5000); // 5秒超时
        });

        try {
          await Promise.race([closePromise, timeoutPromise]);
        } catch (closeErr) {
          Log.e('DatabaseHelper', `rdbStore.close() failed or timeout: ${JSON.stringify(closeErr)}`);
        } finally {
          // 竞速结束后取消定时器，避免 5 秒僵尸定时器随每次关库累积
          clearTimeout(closeTimerId);
        }
        
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
      // 清理ID（含占位数据库的懒失败标记与单实例登记）
      DatabaseHelper.removeDatabaseFromMemory(dbId);
      result.success(null);
      return;
    }
  }

  // 删除一个数据库
  // 对齐 Android onDeleteDatabaseCall：先关闭并移除该路径已打开的实例再删除文件；
  // 删除失败不向 Dart 报错（吞掉异常记录日志），恒定 success 由调用方返回。
  public static async deleteDatabase(context: common.Context, dbPath: string): Promise<void> {
    let dbPathDirList: string[] = dbPath.split('/');
    let dbName: string = DatabaseHelper.getDatabaseNameByDbPathDirList(dbPathDirList);

    await DatabaseHelper.closeDatabaseByPath(dbPath);

    try {
      let config: relationalStore.StoreConfig = DatabaseHelper.createDatabaseConfig(dbPathDirList, dbName);
      await relationalStore.deleteRdbStore(context, config);
    } catch (e) {
      Log.e('DatabaseHelper', `delete database ${dbPath} failed: ${JSON.stringify(e)}`);
    }
  }

  // 关闭并移除指定路径的全部数据库实例（不通知 Dart，供 deleteDatabase 内部使用）
  // 多实例打开同一路径时（singleInstance=false）逐个关闭，避免只关一个、其余句柄泄漏
  private static async closeDatabaseByPath(dbPath: string): Promise<void> {
    const dbIds: number[] = [];
    DatabaseHelper.dbIdMap.forEach((path: string, dbId: number) => {
      if (dbPath === path) {
        dbIds.push(dbId);
      }
    });
    if (dbIds.length === 0) {
      return;
    }
    for (const dbId of dbIds) {
      const local: relationalStore.RdbStore | undefined = DatabaseHelper.dbMap.get(dbId);
      // 对齐 Android “关库即关游标”：删除前关闭该实例名下的全部分页游标
      Database.closeCursorsOfDatabase(dbId);
      DatabaseHelper.removeDatabaseFromMemory(dbId);
      // 对齐 closeDatabase：同步移除内存库 id→临时文件名登记，避免 deleteDatabase
      // 后 memoryDbMap 条目残留（物理文件由外层 deleteDatabase 的 deleteRdbStore 删除）
      DatabaseHelper.memoryDbMap.delete(dbId);
      // 仅当该实例恰是当前事务持有者时才清零全局事务状态：删除无关库
      // 不得清掉其他库正在进行的事务（否则事务内写被自动提交、COMMIT 后 depth 失真）
      Database.resetTransactionState(dbId);
      if (local === undefined) {
        continue;
      }
      // 与 closeDatabase 相同的超时保护，避免 close() 挂起阻塞 worker 串行队列
      const closePromise = local.close();
      let closeTimerId: number = -1;
      const timeoutPromise = new Promise<void>((_, reject) => {
        closeTimerId = setTimeout(() => reject(new Error('Close timeout')), 5000); // 5秒超时
      });
      try {
        await Promise.race([closePromise, timeoutPromise]);
      } catch (err) {
        Log.e('DatabaseHelper', `close before delete failed: ${JSON.stringify(err)}`);
      } finally {
        // 竞速结束后取消定时器，避免僵尸定时器累积
        clearTimeout(closeTimerId);
      }
    }
  }

  // 获取设备版本信息
  public static async getPlatformVersion(call: MethodCall, result: MethodResult): Promise<void> {
    result.success('ohos' + deviceInfo.osFullName);
  }

  // Options操作，设置LogLevel
  // androidThreadPriority/androidThreadCount 仅作用于 Android 线程池实现，
  // OHOS 为固定单 worker 串行队列（等价 THREAD_COUNT=1），无对应参数可调。
  public static async options(call: MethodCall, result: MethodResult): Promise<void> {
    const logLevelArg: Any = call.argument(Constant.PARAM_LOG_LEVEL);
    if (typeof logLevelArg === 'number') {
      DatabaseHelper.currentLogLevel = logLevelArg;
    }
    result.success(null);
  }

  // 设置debug模式，查看SQL查询，已弃用（对齐 Android onDebugModeCall 的日志级别切换语义）
  public static async debugMode(call: MethodCall, result: MethodResult): Promise<void> {
    let on: boolean = call.args === true;
    // on -> verbose 级别（对齐 Android debug 构建的 EXTRA_LOGV 分级），off -> 关闭。
    // OHOS 无 BuildConfig.DEBUG 等价物（无构建类型感知），开启即 verbose，
    // 与 Android release 下降级为 sql 级存在差异（API 已 deprecated，影响面小）
    DatabaseHelper.currentLogLevel = on ? Constant.LOG_LEVEL_VERBOSE : Constant.LOG_LEVEL_NONE;
    result.success(null);
  }

  // Debug操作,获取数据库信息
  public static async onDebug(call: MethodCall, result: MethodResult): Promise<void> {
    let cmd: string = call.argument(Constant.PARAM_CMD);
    let map: Record<string, Object> = {};

    // Get database info
    if (Constant.CMD_GET === cmd) {
      const logLevel: number = DatabaseHelper.getLogLevel();
      if (logLevel > Constant.LOG_LEVEL_NONE) {
        map[Constant.PARAM_LOG_LEVEL] = logLevel;
      }
      // 返回数据库列表信息
      if (DatabaseHelper.dbIdMap.length > 0) {
        let databasesInfo: Record<string, Object> = {};
        DatabaseHelper.dbIdMap.forEach((dbPath: string, dbId: number) => {
          let info: Record<string, Object> = {};
          // dbIdMap 的值即打开时的完整路径
          info[Constant.PARAM_PATH] = dbPath;
          // 打开时记录的实际单实例标记
          info[Constant.PARAM_SINGLE_INSTANCE] = DatabaseHelper.singleInstanceByPath.has(dbPath);
          if (logLevel > Constant.LOG_LEVEL_NONE) {
            info[Constant.PARAM_LOG_LEVEL] = logLevel;
          }
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

  public static getDatabasePathByDatabaseId(dbid: number): string {
    return DatabaseHelper.dbIdMap.get(dbid);
  }

  // 按 id 从内存移除一个数据库登记（dbMap/dbIdMap/dbIdOnlyMap/懒失败标记/单实例表）
  private static removeDatabaseFromMemory(dbId: number) {
    const dbPath: string | undefined = DatabaseHelper.dbIdMap.get(dbId);
    DatabaseHelper.dbMap.delete(dbId);
    DatabaseHelper.dbIdMap.remove(dbId);
    DatabaseHelper.dbIdOnlyMap.remove(dbId);
    DatabaseHelper.invalidOpenDbErrors.remove(dbId);
    // 仅当该路径登记的单实例 id 就是本实例时才清除，
    // 避免多实例场景下误删后来者对同路径的登记
    if (dbPath != undefined && DatabaseHelper.singleInstanceByPath.get(dbPath) === dbId) {
      DatabaseHelper.singleInstanceByPath.delete(dbPath);
    }
  }

}