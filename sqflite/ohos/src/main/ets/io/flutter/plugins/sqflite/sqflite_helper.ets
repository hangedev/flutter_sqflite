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

import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import MethodChannel, {
  MethodCallHandler,
  MethodResult
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { Tools } from './tools';
import { BusinessError } from '@ohos.base';
import { Constant } from './OhosConstant';
import deviceInfo from '@ohos.deviceInfo';
import { ValueType } from '@ohos.data.ValuesBucket';
import { SqlHelper } from './sql_helper';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import fs from '@ohos.file.fs';

const TAG: string = "SqfLiteHelper";

type HandleCallback = (x: Object) => void;

export class SqfLiteHelper {
  /// 已加载的数据库
  public static dataBaseList: Map<string, relationalStore.RdbStore> = new Map<string, relationalStore.RdbStore>();
  /// 加载的数据库的list
  public static dBIdList: Map<number, string> = new Map<number, string>();
  /// 加载的数据库的list
  private static databaseId: number = 0;
  private static lastTransactionId: number = 0;
  private static currentTransactionId: number | null;
  private static transactionDepth: number = 0;
  private static noResult: boolean;
  private static insertResult: number = -1;
  private static updateResult: number = -1;
  private static queryResult: Map<String, object> = new Map();
  private static operationError: OperationError;

  /// 创建一个数据库
  public static async getDataBase(context: common.Context, call: MethodCall, result: MethodResult): Promise<number> {
    let id: number = -1;
    let dbPath: string = call.argument(Constant.PARAM_PATH);
    let dbPathNameList: string[] = dbPath.split('/');
    let dbName: string = dbPathNameList[dbPathNameList.length - 1];
    let endWithDb: boolean = Tools.stringEndWith(dbName, '.db');

    if (!endWithDb) {
      dbName = dbName + '.db';
    }

    const isExisted: boolean = await SqfLiteHelper.checkDatabaseExisted(dbPath);
    if (isExisted) {
      // 从已有的数据库里面获取
      let local: relationalStore.RdbStore | null = SqfLiteHelper.getOnlyLocal(dbName);
      if (local != null) {
        Log.d(TAG, '~~createDatabase from local: ' + local);
        SqfLiteHelper.dBIdList.forEach((value, key) => {
          if (dbName == value) {
            Log.d(TAG, '~~createDatabase from local DBId: ' + key);
            id = key
          }
        })
        let map: Record<string, Object> = {
          'id': id,
          'recovered': false,
          'recoveredInTransaction': false,
        }
        result.success(map);
        return id;
      }
    }

    // 自定义数据库路径
    let customDir: string = '';
    for (let index = 5; index < dbPathNameList.length - 1; index++) {
      if (customDir.length > 0) {
        customDir = customDir + '/' + dbPathNameList[index];
      } else {
        customDir = dbPathNameList[index];
      }
    }

    Log.i(TAG, '~~custom db Dir:' + customDir + ' system version:' + deviceInfo.osFullName, '');

    // 从系统中获取
    let config: relationalStore.StoreConfig;
    let readOnly:boolean = call.argument(Constant.PARAM_READ_ONLY) == undefined ? false : call.argument(Constant.PARAM_READ_ONLY);
    if (customDir.length > 0) {
      config = {
        name: dbName, // 数据库文件名
        securityLevel: relationalStore.SecurityLevel.S1, // 数据库安全级别
        customDir: customDir,
        // isReadOnly:readOnly
      };
    } else {
      config = {
        name: dbName, // 数据库文件名
        securityLevel: relationalStore.SecurityLevel.S1, // 数据库安全级别
        // isReadOnly:readOnly
      }
    }

    try {
      let rdbStore = await relationalStore.getRdbStore(context, config);
      Log.d(TAG, '~~createDatabase success' + dbName + ' 正常', '%{public}s');

      SqfLiteHelper.dataBaseList.set(dbName, rdbStore);
      SqfLiteHelper.databaseId = SqfLiteHelper.databaseId + 1;
      id = SqfLiteHelper.databaseId;
      SqfLiteHelper.dBIdList.set(id, dbName);
      let map: Record<string, Object> = {
        'id': id,
        'recovered': false,
        'recoveredInTransaction': false,
      }
      result.success(map);
    } catch (err) {
      let code = (err as BusinessError).code;
      let message = (err as BusinessError).message;
      result.error(Constant.SQLITE_ERROR, message + '' + code, 'open database failed');
      Log.d(TAG, '~~createDatabase failed: ' + err + ' system version:' + deviceInfo.osFullName + '---api version:' + deviceInfo.sdkApiVersion + 'major version:' + deviceInfo.majorVersion + '--osReleaseType:' + deviceInfo.osReleaseType + 'displayVersion:' + deviceInfo.displayVersion + 'buildVersion:' + deviceInfo.buildVersion, '%{public}s');
    }
    // result.error(Constant.SQLITE_ERROR, Constant.SQLITE_OPEN_FAILED + "" + path, null);
    return id;
  }

  /// 检查数据库是否存在
  public static async checkDatabaseExisted(dbPath: string): Promise<boolean> {
    let dbPathNameList: Array<string> = dbPath.split('/');
    let dbName: string = dbPathNameList[dbPathNameList.length - 1];
    let endWithDb: boolean = Tools.stringEndWith(dbName, '.db');

    // //获取应用的bundleName
    // let bundleName: string = (await bundleManager.getBundleInfoForSelf(1)).name;
    // Log.i(TAG, "Begin check databases exists bundleName:" + bundleName + '~~~');

    let trueDbPath: string = '';
    if (dbPathNameList.length > 6) {
      Log.i(TAG, "handleDatabaseExistsCall length > 5");
      for (let index = 0; index < dbPathNameList.length; index++) {
        const element = dbPathNameList[index] as string;
        if ((index < 5) || (index > 5 && index != dbPathNameList.length - 1)) {
          trueDbPath = trueDbPath + element + '/';
        } else if (index == 5) {
          trueDbPath = trueDbPath + 'rdb' + '/';
          trueDbPath = trueDbPath + element + '/';
        } else {
          if (!endWithDb) {
            trueDbPath = trueDbPath + element + '.db';
          } else {
            trueDbPath = trueDbPath + element;
          }
        }
      }
    } else {
      Log.i(TAG, "handleDatabaseExistsCall length <= 5");
      for (let index = 0; index < dbPathNameList.length; index++) {
        const element = dbPathNameList[index] as string;
        if (index != dbPathNameList.length - 1) {
          trueDbPath = trueDbPath + element + '/';
        } else {
          trueDbPath = trueDbPath + 'rdb' + '/';
          if (!endWithDb) {
            trueDbPath = trueDbPath + element + '.db';
          } else {
            trueDbPath = trueDbPath + element;
          }
        }
      }
    }
    Log.i(TAG, "End check databases exists result:" + trueDbPath + ' ---length:' + dbPathNameList.toString() + '--:' + dbPathNameList.length);
    let isExists: boolean = await fs.access(trueDbPath);
    return isExists;
  }

  /// 从已加载的列表里获取一个数据库
  private static getOnlyLocal(dataBaseName: string): relationalStore.RdbStore | null {
    if (SqfLiteHelper.dataBaseList.has(dataBaseName)) {
      return SqfLiteHelper.dataBaseList.get(dataBaseName) as relationalStore.RdbStore | null;
    }
    Log.i(TAG, '没有加载这个数据库', '%{public}s');
    return null;
  }

  /// 从已加载的列表里获取一个数据库
  public static getDatabaseOrError(call: MethodCall, result: MethodResult): relationalStore.RdbStore | null {
    let dataBaseId: number = call.argument("id");
    let databaseName: string | undefined = SqfLiteHelper.dBIdList.get(dataBaseId);
    if (typeof databaseName == undefined) {
      result.error('sqlite_error', "database_closed" + "" + dataBaseId, null);
      return null;
    }
    let rdbStore = SqfLiteHelper.getOnlyLocal(databaseName as string);
    if (rdbStore != null) {
      return rdbStore;
    } else {
      result.error('sqlite_error', "database_closed" + "" + dataBaseId, null);
      return null;
    }
    Log.i(TAG, '没有加载这个数据库', '%{public{}s');
    return null;
  }

  /// 关闭一个数据库
  public static closeDataBase(call: MethodCall, result: MethodResult): void {
    let databaseId: number = call.argument(Constant.PARAM_ID);
    let dataBaseName: string | undefined = SqfLiteHelper.dBIdList.get(databaseId);
    if (dataBaseName == undefined) return;
    if (SqfLiteHelper.dataBaseList.has(dataBaseName)) {
      SqfLiteHelper.dataBaseList.delete(dataBaseName);
      let id: number = -1;
      SqfLiteHelper.dBIdList.forEach((value, key) => {
        if (dataBaseName == value) {
          id = key;
        }
      })
      if (id > -1) {
        SqfLiteHelper.dBIdList.delete(id);
        result.success(null);
        Log.i(TAG, '-----database close:' + dataBaseName + 'closed', '');
        return;
      }
    }
    result.error('sqlite_error', "close database failed, database is not exist, can not close" + " " + databaseId, null);
  }

  /// 删除一个数据库
  public static async deleteDataBase(context: common.Context, dataBaseName: string): Promise<boolean> {
    let result: boolean = false;
    let dbNameList: string[] = dataBaseName.split('/');
    let dbName: string = dbNameList[dbNameList.length - 1];
    let endWithDb: boolean = Tools.stringEndWith(dbName, '.db');
    Log.i(TAG, 'step:-1 delete action, got database name:' + dataBaseName + 'endWithDb:' + endWithDb);
    if (!endWithDb) {
      dbName = dbName + '.db';
      dataBaseName = dataBaseName + '.db';
    }

    Log.i(TAG, 'step:0 delete action, got database name:' + dataBaseName + 'endWithDb:' + endWithDb);

    //自定义数据库路径
    let customDir: string = '';
    for (let index = 5; index < dbNameList.length - 1; index++) {
      if (customDir.length > 0) {
        customDir = customDir + '/' + dbNameList[index];
      } else {
        customDir = dbNameList[index];
      }
    }

    Log.i(TAG, '~~custom db Dir: ' + customDir + ' system version:' + deviceInfo.osFullName, '');

    // 从系统中获取
    let config: relationalStore.StoreConfig;
    if (customDir.length > 0) {
      config = {
        name: dbName, // 数据库文件名
        securityLevel: relationalStore.SecurityLevel.S1, // 数据库安全级别
        customDir: customDir,
      };
    } else {
      config = {
        name: dbName, // 数据库文件名
        securityLevel: relationalStore.SecurityLevel.S1, // 数据库安全级别
      }
    }

    if (SqfLiteHelper.dataBaseList.has(dataBaseName)) {
      Log.i(TAG, 'step:1 already loaded database, trying delete' + dataBaseName);
      SqfLiteHelper.dataBaseList.delete(dataBaseName);
      let id: number = -1;
      SqfLiteHelper.dBIdList.forEach((value, key) => {
        if (dataBaseName == value) {
          id = key;
        }
      })
      if (id > -1) {
        SqfLiteHelper.dBIdList.delete(id);
        await relationalStore.deleteRdbStore(context, config);
        result = true;
        return result;
      }
      return result;
    } else {
      Log.i(TAG, 'step:3 unload database, trying delete' + dataBaseName);
      try {
        // todo 这里需要注意一下
        if (await SqfLiteHelper.checkTable(dataBaseName, 'defaultTable') == true) {
          await SqfLiteHelper.deleteTable(dataBaseName, 'defaultTable');
        }

        await relationalStore.deleteRdbStore(context, config);
        result = true;
        return result;
      } catch (e) {
        Log.i(TAG, 'step:5 deleted database error' + e, '%{public}s');
        return result;
      }
    }

  }

  public static async insert(call: MethodCall, result: MethodResult, dataBase: relationalStore.RdbStore): Promise<number> {

    let rowId: number = -1;
    let list: ValueType[] = call.argument(Constant.PARAM_SQL_ARGUMENTS);
    let sqlString: string = call.argument(Constant.PARAM_SQL)! as string;
    Log.i(TAG, "insert data, get sqlString:" + sqlString + '--------' + arguments);

    if (list == undefined || list.length < 1) {

      try {
        // let tableName: string = SqlHelper.getRawInsertSqlTableName(sqlString);
        // Log.i(TAG, "insert data, get tableName1:" + tableName);
        //
        // let dataNames: string[] = SqlHelper.getRawSqlDataName(sqlString);
        // Log.i(TAG, "insert data, get dataName1:" + dataNames);
        //
        // let dataValues: string[] = SqlHelper.getRawSqlDataValues(sqlString);
        // Log.i(TAG, "insert data, get dataValues:" + dataValues);

        const valuesBucket: relationalStore.ValuesBucket = {}
        // dataNames.forEach((value, index) => {
        //   valuesBucket[value] = dataValues[index];
        // })

        // rowId = await dataBase.insert(tableName, valuesBucket);
        // Log.i(TAG, "insert data, return row id:" + rowId);
        // result.success(rowId);
      } catch (err) {
        let code = (err as BusinessError).code;
        let message = (err as BusinessError).message;
        result.error(Constant.SQLITE_ERROR, message + '' + code, 'insert data, failed');
      }
    } else {
      try {
        let dataName: string[] = SqlHelper.getSqlDataName(sqlString);
        let tableName: string = SqlHelper.getInsertSqlTableName(sqlString);

        const valuesBucket: relationalStore.ValuesBucket = {}
        dataName.forEach((value, index) => {
          valuesBucket[value] = list[index];
        })

        rowId = await dataBase.insert(tableName, valuesBucket);
        Log.i(TAG, "insert data, return row id:" + rowId);
        result.success(rowId);
      } catch (err) {
        let code = (err as BusinessError).code;
        let message = (err as BusinessError).message;
        result.error(Constant.SQLITE_ERROR, message + '' + code, 'insert data, failed');
      }
    }

    return rowId;
  }

  /// 插入一条数据
  public static async insertSql(sql: string, sqlArguments: ValueType[] | undefined, call: MethodCall, result: MethodResult, dataBase: relationalStore.RdbStore): Promise<boolean> {

    let dataBaseId: number = call.argument(Constant.PARAM_ID);
    let databaseName: string = SqfLiteHelper.dBIdList.get(dataBaseId) as string;
    String
    let tableName: string = SqlHelper.getInsertSqlTableName(sql);
    Log.i(TAG, "insertSql data: get tableName :" + tableName + databaseName);

    let tableExisted = await SqfLiteHelper.checkTable(databaseName, tableName);
    if (tableName.length > 0 && !tableExisted) {
      result.error(Constant.SQLITE_ERROR, 'no such table:' + tableName, '');
      return false;
    }

    return await SqfLiteHelper.execute(sql, sqlArguments, call, result, dataBase, (rows) => {
      SqfLiteHelper.insertResult = rows as number;
      result.success(rows);
    });
  }

  /// 执行一个sql语句
  public static async execute(sql: string, sqlArguments: ValueType[] | undefined, call: MethodCall, result: MethodResult, dataBase: relationalStore.RdbStore, callback?: HandleCallback): Promise<boolean> {
    Log.i(TAG, "lz execute" + ' sql:' + sql + '---sqlArguments:' + sqlArguments);

    let inTransactionChange: Boolean = SqfLiteHelper.getInTransactionChange(call);
    let enteringTransaction: boolean = (inTransactionChange == true && SqfLiteHelper.hasNullTransactionId(call));
    if (enteringTransaction) {
      SqfLiteHelper.currentTransactionId = ++(SqfLiteHelper.lastTransactionId);
    }
    if (!SqfLiteHelper.executeOrError(sql, sqlArguments, call, result, dataBase)) {
      // Revert if needed
      if (enteringTransaction) {
        SqfLiteHelper.currentTransactionId = null;
      }
      return false;
    } else if (enteringTransaction) {
      /// Return the transaction id
      if (SqfLiteHelper.currentTransactionId != null) {
        let res: Map<String, Object> = new Map();
        res.set(Constant.PARAM_TRANSACTION_ID, SqfLiteHelper.currentTransactionId);
        result.success(res);
      } else {
        result.success(null);
      }
    } else {
      if (inTransactionChange == false) {
        SqfLiteHelper.currentTransactionId = null;
      }

      if (callback != undefined) {
        callback(1);
      } else {
        result.success(null);
      }
    }
    return true;
  }

  /// 读取一条数据
  public static async querySql(sql: string, sqlArguments: ValueType[] | undefined, call: MethodCall, result: MethodResult, dataBase: relationalStore.RdbStore, cursorPageSize: number | undefined): Promise<boolean> {

    if(sql == 'PRAGMA user_version') {
      let results: Map<String, object> = new Map<String, Object>();
      results.set(Constant.PARAM_COLUMNS, ['user_version']);
      results.set(Constant.PARAM_ROWS, [[dataBase.version]]);
      result.success(results);
      return true;
    }

    let dataBaseId: number = call.argument(Constant.PARAM_ID);
    let databaseName: string = SqfLiteHelper.dBIdList.get(dataBaseId) as string;
    let tableName: string = SqlHelper.getQuerySqlTableName(sql);
    Log.i(TAG, "querySql data: get tableName :" + tableName + databaseName);

    let tableExisted = await SqfLiteHelper.checkTable(databaseName, tableName);
    if(tableName.length > 0 && !tableExisted) {
      result.error(Constant.SQLITE_ERROR, 'no such table: ' + tableName, '');
      return false;
    }

    let suc: boolean = false;
    if(sqlArguments != undefined && sqlArguments.length > 0) {
      try{
        await dataBase.querySql(sql, sqlArguments, (err, resultSet) => {
          suc = SqfLiteHelper.handleQuerySql1(result, err, resultSet, cursorPageSize);
        });
        return suc;
      } catch(err) {
        SqfLiteHelper.handleSqliteError(result, err);
        return false;
      }
    } else {
      try{
        await dataBase.querySql(sql, (err, resultSet) => {
          suc = SqfLiteHelper.handleQuerySql1(result, err, resultSet, cursorPageSize);
        })
        return suc;
      } catch(err) {
        SqfLiteHelper.handleSqliteError(result, err);
        return false;
      }
    }
  }

  private static handleQuerySql1(result: MethodResult, err: BusinessError<void>, resultSet: relationalStore.ResultSet, cursorPageSize: number | undefined): boolean {
    if (err) {
      SqfLiteHelper.handleSqliteError(result, err);
      return false;
    }
    let results: Map<String, object> = new Map<String, Object>();
    let rows: Array<Array<Object>> = new Array<Array<Object>>();
    let columns: Array<string> | null = null;
    let columnCount: number = 0;

    // resultSet是一个数据集合的游标，默认指向第-1个记录，有效的数据从0开始。
    while (resultSet.goToNextRow()) {
      if (columns == null) {
        columnCount = resultSet.columnCount;
        columns = new Array<string>();
        rows = new Array<Array<Object>>();
        for (let i = 0; i < columnCount; i++) {
          columns.push(resultSet.getColumnName(i));
        }
        results.set(Constant.PARAM_COLUMNS, columns);
        results.set(Constant.PARAM_ROWS, rows);
      }

      let row = SqfLiteHelper.cursorRowToList(resultSet, columnCount);
      rows.push(row);
      if (cursorPageSize != null) {
        if (rows.length >= cursorPageSize) {
          break;
        }
      }
    }

    let str = JSON.stringify(results)
    Log.d(TAG, "query data result: " + str.toString());

    SqfLiteHelper.queryResult = results;
    result.success(results);
    // 释放数据集的内存
    resultSet.close();
    return true;
  }

  static cursorRowToList(cursor: relationalStore.ResultSet, length: number): Array<Object> {
    let list = new Array<Object>();

    for (let i = 0; i < length; i++) {
      let value: Object = SqfLiteHelper.cursorValue(cursor, i);
      // let value: Object = 'cursorValue(cursor, i)';
      // if(Debug.EXTRA_LOGV){
      // String type = null;
      // if(value != null){
      // if(value.getClass().isArray()) {
      // type = "array(" + value.getClass().getComponentType().getName() + ")";
      // } else {
      // type = value.getCalss().getName();
      // }
      // }
      // Log.d(TAG, "column " + i + "" + cursor.getType(i) + ": " + value + (type == null ? "" : "(" + type + ")"));
      // }
      list.push(value);
    }
    return list;
  }

  static cursorValue(cursor: relationalStore.ResultSet, index: number): string {
    return cursor.getString(index);
  }

  /// 更新/删除数据--使用Sql方式
  public static async updateSql(sql: string, sqlArguments: ValueType[] | undefined, call: MethodCall, result: MethodResult, dataBase: relationalStore.RdbStore): Promise<boolean> {

    let dataBaseId: number = call.argument(Constant.PARAM_ID);
    let databaseName: string = SqfLiteHelper.dBIdList.get(dataBaseId) as string;
    let tableName: string = SqlHelper.getUpdateSqlTableName(sql);
    Log.i(TAG, "updataSql data: get tableName:" + tableName + databaseName);

    let tableExisted = await SqfLiteHelper.checkTable(databaseName, tableName);
    if (tableName.length > 0 && !tableExisted) {
      result.error(Constant.SQLITE_ERROR, 'no such table:' + tableName, '');
      return false;
    }

    return SqfLiteHelper.execute(sql, sqlArguments, call, result, dataBase, (rows) => {
      SqfLiteHelper.updateResult = rows as number;
      result.success(rows);
    });
  }

  /// batch操作
  public static async batch(call: MethodCall, result: MethodResult, dataBase: relationalStore.RdbStore): Promise<void> {

    result.error(Constant.SQLITE_ERROR, 'ohos does not currently support batch operations', '')
    return;
    // let noResult: boolean = SqfLiteHelper.getNoResult(call);
    // SqfLiteHelper.noResult = noResult;
    // let continueOnError: boolean = SqfLiteHelper.getContinueOnError(call);
    //
    // let operations: Array<Map<string, Object>> = SqfLiteHelper.getAragument(call, Constant.PARAM_OPERATIONS) as Array<Map<string, Object>>;
    // let results: Array<Map<string, Object>> = new Array();
    //
    // for(let index = 0; index < operations.length; index++) {
    //   const map: Map<String, Object> = operations[index];
    //   const method: string = map.get(Constant.PARAM_METHOD) as string;
    //
    //   let sql: string = map.get(Constant.PARAM_SQL) as string;
    //   let sqlArguments: ValueType[] | undefined = map.get(Constant.PARAM_SQL_ARGUMENTS) as (ValueType[] | undefined);
    //   let cursorPageSize: number | undefined = call.argument(Constant.PARAM_CURSOR_PAGE_SIZE);
    //
    //   Log.i(TAG, "hanle batch:" + method + '----' + sql + ' map:' + map.toString() + 'operations:' + operations.toString());
    //
    //   switch(method) {
    //     case Constant.METHOD_EXECUTE:
    //       if(await SqfLiteHelper.execute(sql, sqlArguments, call, result, dataBase)) {
    //         SqfLiteHelper.handleSuccess(results, '');
    //       } else if(continueOnError) {
    //         SqfLiteHelper.handleErrorContinue(results);
    //       } else {
    //         return;
    //       }
    //       break;
    //     case Constant.METHOD_INSERT:
    //       if(await SqfLiteHelper.insertSql(sql, sqlArguments, call, result, dataBase)) {
    //         SqfLiteHelper.handleSuccess(results, SqfLiteHelper.insertResult);
    //       } else if(continueOnError) {
    //         SqfLiteHelper.handleErrorContinue(results);
    //       } else {
    //         SqfLiteHelper.handleError(result);
    //         return;
    //       }
    //       break;
    //     case Constant.METHOD_QUERY:
    //       if(await SqfLiteHelper.querySql(sql, sqlArguments, call, result, dataBase, cursorPageSize)) {
    //         SqfLiteHelper.handleSuccess(results, SqfLiteHelper.queryResult);
    //       } else if(continueOnError) {
    //         SqfLiteHelper.handleErrorContinue(results);
    //       } else {
    //         SqfLiteHelper.handleError(result);
    //         return;
    //       }
    //       break;
    //     case Constant.METHOD_UPDATE:
    //       if(await SqfLiteHelper.updataSql(sql, sqlArguments, call, result, dataBase)) {
    //         SqfLiteHelper.handleSuccess(results, SqfLiteHelper.updataResult);
    //       } else if(continueOnError) {
    //         SqfLiteHelper.handleErrorContinue(results);
    //       } else {
    //         SqfLiteHelper.handleError(result);
    //         return;
    //       }
    //       break;
    //     default:
    //       result.error(Constant.ERROR_BAD_PARAM, "Batch method" + method + "no supported", null);
    //       return;
    //   }
    // }
    // Log.d(TAG, "handle batch result data SUCCESS:" + typeof results + '-----' + results + '------q:' + JSON.stringify(results) + 'noResult:' + noResult);
    // if(noResult) {
    //   result.success(null);
    // } else {
    //   result.success(results);
    // }
    //SqfLiteHelper.execute(call, result, dataBase, (rows) => result.success(rows));
  }

  /// Options操作，设置LogLevel，仅限开发，已被废弃
  public static async options(call: MethodCall, result: MethodResult): Promise<void> {
    let logLevel: number | undefined = call.argument(Constant.PARAM_LOG_LEVEL);
    Log.i(TAG, "handle options:" + logLevel);
    result.success(null);
  }

  /// 设置debug模式，查看SQL查询，已弃用
  public static async debugMode(call: MethodCall, result: MethodResult): Promise<void> {
    let on: boolean = call.args;
    Log.i(TAG, "debugMode:" + on);
    result.success(null);
  }

  /// 获取设备版本信息
  public static async getPlatformVersion(call: MethodCall, result: MethodResult): Promise<void> {
    result.success('ohos' + deviceInfo.osFullName);
  }


  private static async executeOrError(sql: string, sqlArguments: ValueType[] | undefined, call: MethodCall, result: MethodResult, dataBase: relationalStore.RdbStore): Promise<boolean> {

    let operationInTransaction: boolean = SqfLiteHelper.getInTransactionChange(call);
    try {
      if (sqlArguments == undefined || sqlArguments.length < 1) {
        await dataBase.executeSql(sql);
      } else {
        await dataBase.executeSql(sql, sqlArguments);
      }
      SqfLiteHelper.enterOrLeaveInTransaction(operationInTransaction);
      return true;
    } catch (err) {
      let code = (err as BusinessError).code;
      let message = (err as BusinessError).message;
      result.error(Constant.SQLITE_ERROR, message + '' + code + sql, sql);
      SqfLiteHelper.operationError = new OperationError(code.toString(), message, sql);
      Log.i(TAG, "lz execute error: " + message + '--sql:' + sql + '--code:' + code);
      return false;
    }
    // try{
    //     getWritableDatabase().execSQL(command.getSql(), command.getSqlArguments());
    //     enterOrLeaveInTransaction(operationInTransaction);
    //     return true;
    // } catch(Exception exception) {
    //     handleException(exception, operation);
    //     return false;
    // }
  }

  private static enterOrLeaveInTransaction(value: boolean): void {
    if (value == true) {
      SqfLiteHelper.transactionDepth++;
    } else if (value == false) {
      SqfLiteHelper.transactionDepth--;
    }
  }

  private static hasNullTransactionId(call: MethodCall): boolean {
    let rawId: object = call.argument(Constant.PARAM_TRANSACTION_ID);
    if (rawId == null || rawId == undefined) {
      return true;
    }
    return false;
  }

  private static getInTransactionChange(call: MethodCall): boolean {
    let inTransactionChange: object = call.argument(Constant.PARAM_IN_TRANSACTION_CHANGE);
    Log.i(TAG, 'inTransactionChange' + 'type:' + typeof inTransactionChange);
    if (inTransactionChange instanceof Boolean) {
      return inTransactionChange.valueOf();
    }
    return false;
  }

  private static getTransactionId(call: MethodCall): Number | undefined {
    let rawId: object = call.argument(Constant.PARAM_TRANSACTION_ID);
    if (rawId instanceof Number) {
      return rawId;
    }
    return undefined;
  }

  /// Sqlite错误处理
  private static handleSqliteError(result: MethodResult, err: BusinessError<void>) {
    let code = err.code;
    let message = err.message;
    result.error(Constant.SQLITE_ERROR, message + '' + code, '');
  }

  private static getNoResult(call: MethodCall): boolean {
    let noResult: boolean = call.argument(Constant.PARAM_NO_RESULT);
    return noResult;
  }

  private static getContinueOnError(call: MethodCall): boolean {
    let noResult: boolean = call.argument(Constant.PARAM_CONTINUE_OR_ERROR);
    return noResult;
  }

  private static getArgument(call: MethodCall, key: string): object {
    return call.argument(key);
  }

  public static handleError(result: MethodResult) {
    result.error(SqfLiteHelper.operationError.errorCode, SqfLiteHelper.operationError.errorMessage, SqfLiteHelper.operationError.errorData);
  }

  private static handleErrorContinue(results: Array<Map<String, Object>>) {
    if (!SqfLiteHelper.noResult) {
      let error: Map<String, Object> = new Map();
      let errorDetail: Map<String, Object> = new Map();
      errorDetail.set(Constant.PARAM_ERROR_CODE, SqfLiteHelper.operationError.errorCode);
      errorDetail.set(Constant.PARAM_ERROR_MESSAGE, SqfLiteHelper.operationError.errorMessage);
      errorDetail.set(Constant.PARAM_ERROR_DATA, SqfLiteHelper.operationError.errorData);

      error.set(Constant.PARAM_ERROR_DATA, errorDetail);
      results.push(error);
    }
  }


  /// 检查数据库
  public static databaseExists(dataBaseName: string): boolean {
    // let sql: string = "SHOW DATABASES LIKE " + dataBaseName;
    //
    // let dataBase: relationalStore.RdbStore | null = SqfLiteHelper.getOnlyLocal(dataBaseName);
    // if (dataBase == null) return success;

    // todo 这里还没有实现
    return true;
  }

  /// 检查表
  public static async checkTable(dataBaseName: string, tableName: string): Promise<boolean> {
    let success: boolean = false;

    let dataBase: relationalStore.RdbStore | null = SqfLiteHelper.getOnlyLocal(dataBaseName);
    if (dataBase == null) return success;
    try {
      let predicates = new relationalStore.RdbPredicates(tableName);
      let result = await dataBase.query(predicates);
      if (result.columnCount > 0) {
        Log.i(TAG, '检查表' + tableName + '已存在', '%{public}s');
        success = true;
      } else {
        Log.i(TAG, '检查表' + tableName + '不存在', '%{public}s');
      }
    } catch (e) {
      Log.i(TAG, '检查表' + tableName + '出现异常： ' + e, '%{public}s');
    }

    return success;
  }

  /// 创建表
  public static async createTable(dataBaseName: string, tableName: string, data: string = ''): Promise<boolean> {
    let success: boolean = false;
    let dataBase: relationalStore.RdbStore | null = SqfLiteHelper.getOnlyLocal(dataBaseName);
    if (dataBase == null) return success;

    try {
      await dataBase.executeSql('CREATE TABLE IF NOT EXISTS ' + tableName + '(' + data + ')')
      Log.i(TAG, '创建表' + tableName + '成功', '%{public}s');
      success = true;
    } catch (e) {
      Log.i(TAG, '创建表' + tableName + '出现异常： ' + e, '%{public}s');
    }
    return success;
  }

  /// 删除表
  public static async deleteTable(dataBaseName: string, tableName: string): Promise<boolean> {
    let success: boolean = false;
    let dataBase: relationalStore.RdbStore | null = SqfLiteHelper.getOnlyLocal(dataBaseName);
    if (dataBase == null) return success;
    let checkTableSql = 'DROP TABLE ' + tableName;
    try {
      await dataBase.executeSql(checkTableSql);
      Log.i(TAG, '删除表' + tableName + '成功', '%{public}s');
      success = true;
    } catch (e) {
      Log.i(TAG, '删除表' + tableName + '出现异常： ' + e, '%{public}s');
    }
    return success;
  }

  /// 插入一条数据
  public static async insertData(dataBaseName: string, tableName: string, valuesBucket: relationalStore.ValuesBucket): Promise<number> {
    let rowId: number = -1;

    let dataBase: relationalStore.RdbStore | null = SqfLiteHelper.getOnlyLocal(dataBaseName);
    if (dataBase == null) return rowId;

    try {
      rowId = await dataBase.insert(tableName, valuesBucket);
      if (rowId >= 0) {
        Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表插入数据成功, 行id: ' + rowId, '%{public}s');
      } else {
        Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表插入数据返回值不正常: ' + rowId, '%{public}s');
      }
    } catch (e) {
      Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表插入数据出现异常: ' + e.code + '---' + e.message, '%{public}s');
    }
    return rowId;
  }

  /// 读取一条数据
  /// [columns] 查询的咧
  /// [queryColumnName] 对应的列的名称
  /// [queryColumnData] 对应的列的值
  public static async readOneData(dataBaseName: string, tableName: string, queryColumnName: string, queryColumnData: relationalStore.ValueType, columns: Array<string> = []): Promise<Map<string, Map<string, Object>> | null> {
    let maps: Map<string, Map<string, Object>> = new Map<string, Map<string, Object>>();
    try {
      Log.i(TAG, "新的>查询数据执行readOneData");
      let dataBase: relationalStore.RdbStore | null = SqfLiteHelper.getOnlyLocal(dataBaseName);
      if (dataBase == null) return null;
      let predicates = new relationalStore.RdbPredicates(tableName);
      predicates.equalTo(queryColumnName, queryColumnData);

      let resultSet = await dataBase.query(predicates, columns);
      Log.i(TAG, "新的>鸿蒙查询数据成功");
      while (resultSet.goToNextRow()) {
        let map: Map<string, Object> = new Map<string, Object>();
        for (let i = 0; i < resultSet.columnCount; i++) {
          let key = resultSet.getColumnName(i);
          let value = resultSet.getString(i);
          map.set(key, value);
        }
        Log.i(TAG, '取出的值 -> ' + map, '%{public}s');
        maps.set(maps.size.toString(), map);
      }
      Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表读取数据成功: ', '%{public}s');
      return maps;
    } catch (e) {
      Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表读取数据出现异常: ' + e.code + '---' + e.message, '%{public}s');
    }
    return null;
  }

  /// 更新一条数据
  public static async updateData(dataBaseName: string, tableName: string, queryColumnName: string, queryColumnData: relationalStore.ValueType, valuesBucket: relationalStore.ValuesBucket): Promise<number> {
    let rowId: number = 0;
    try {
      Log.i(TAG, "新的>更新数据执行updateData");
      let dataBase: relationalStore.RdbStore | null = SqfLiteHelper.getOnlyLocal(dataBaseName);
      if (dataBase == null) return rowId;

      let predicates = new relationalStore.RdbPredicates(tableName);
      predicates.equalTo(queryColumnName, queryColumnData);

      rowId = await dataBase.update(valuesBucket, predicates);
      Log.i(TAG, "新的>鸿蒙更新数据成功");
      if (rowId > 0) {
        Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表更新数据成功, 影响行数: ' + rowId, '%{public}s');
      } else {
        Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表更新数据成功, 返回值不正常: ' + rowId, '%{public}s');
      }
    } catch (e) {
      Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表更新数据出现异常: ' + e.code + '---' + e.message, '%{public}s');
    }
    return rowId;
  }

  /// 删除一条数据
  public static async deleteData(dataBaseName: string, tableName: string, queryColumnName: string, queryColumnData: relationalStore.ValueType): Promise<number> {
    let rowId: number = -1;

    let dataBase: relationalStore.RdbStore | null = SqfLiteHelper.getOnlyLocal(dataBaseName);
    if (dataBase == null) return rowId;

    try {
      let predicates = new relationalStore.RdbPredicates(tableName);
      predicates.equalTo(queryColumnName, queryColumnData);
      rowId = await dataBase.delete(predicates);
      if (rowId >= 0) {
        // todo 这里删除0行暂时视为成功
        Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表删除数据成功, 影响行数: ' + rowId, '%{public}s');
      } else {
        Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表删除数据失败, 影响行数: ' + rowId, '%{public}s');
      }
    } catch (err) {
      Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表删除数据出现异常: ' + err.message, '%{public}s');
    }
    return rowId;
  }

  /// 为一个表添加一个新的属性
  public static async addNewProperty(dataBaseName: string, tableName: string, propertyName: string): Promise<boolean> {
    let success: boolean = false;
    let dataBase: relationalStore.RdbStore | null = SqfLiteHelper.getOnlyLocal(dataBaseName);
    if (dataBase == null) return false;

    try {
      await dataBase.executeSql('ALTER TABLE ' + tableName + ' ADD ' + propertyName);
      Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表添加属性成功', '%{public}s');
      success = true;
    } catch (err) {
      Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表添加属性出现异常: ' + err.message, '%{public}s');
    }
    return success;
  }

  /// 为一个表删除一个的属性
  public static async deleteProperty(dataBaseName: string, tableName: string, propertyName: string): Promise<boolean> {
    let success: boolean = false;
    let dataBase: relationalStore.RdbStore | null = SqfLiteHelper.getOnlyLocal(dataBaseName);
    if (dataBase == null) return false;

    try {
      await dataBase.executeSql('ALTER TABLE ' + tableName + ' DROP COLUMN ' + propertyName);
      success = true;
      // Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表删除属性成功', '%{public}s');
    } catch (err) {
      // Log.i(TAG, dataBaseName + ' 的 ' + tableName + ' 表删除属性出现异常: ' + err.message, '%{public}s');
    }
    return success;
  }
}

class OperationError {
  public errorCode: string;
  public errorMessage: string;
  public errorData: string;

  constructor(errorCode: string, errorMessage: string,  errorData: string) {
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
    this.errorData = errorData;
  }
}




