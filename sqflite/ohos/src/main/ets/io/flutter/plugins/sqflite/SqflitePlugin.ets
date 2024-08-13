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
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import {
  AbilityPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodChannel, {
  MethodCallHandler,
  MethodResult
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { SqfliteApi } from './Messages';
import { SqfLiteHelper } from './sqflite_helper';
import relationalStore from '@ohos.data.relationalStore';
import { ValueType } from '@ohos.data.ValuesBucket';
import { SqlHelper } from './sql_helper';
import { Constant } from './OhosConstant';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { Database } from './Database';
import { MethodCallOperation } from './operation/MethodCallOperation';

const TAG: string = "SqflitePlugin";

export default class SqflitePlugin extends SqfliteApi implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private pluginBinding: FlutterPluginBinding | null = null;
  private abilityPluginBinding: AbilityPluginBinding | null = null;
  private context: common.Context | null = null;
  private channel: MethodChannel | null = null;

  constructor(context?: common.Context) {
    super();
    if (context) {
      this.context = context;
    }
  }

  getUniqueClassName(): string {
    return "SqflitePlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = binding;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), Constant.PLUGIN_KEY);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    Log.d(TAG, '-----onMethodCall step in ---' + call.method)
    switch (call.method) {
      case Constant.METHOD_OPEN_DATABASE:
        this.handleOpenDatabaseCall(call, result);
        break;
      case Constant.METHOD_GET_DATABASES_PATH:
        this.handleGetDatabasesPathCall(call, result);
        break;
      case Constant.METHOD_DATABASE_EXISTS:
        this.handleDatabaseExistsCall(call, result);
        break;
      case Constant.METHOD_EXECUTE:
        this.handleExecuteCall(call, result);
        break;
      case Constant.METHOD_INSERT:
        this.handleInsertCall(call, result);
        break;
      case Constant.METHOD_QUERY:
        this.handleQueryCall(call, result);
        break;
      case Constant.METHOD_UPDATE:
        this.handleUpdateCall(call, result);
        break;
      case Constant.METHOD_BATCH:
        this.handleBatchCall(call, result);
        break;
      case Constant.METHOD_OPTIONS:
        this.handleOptionsCall(call, result);
        break;
      case Constant.METHOD_DEBUG_MODE:
        this.handleDebugModeCall(call, result);
        break;
      case Constant.METHOD_GET_PLATFORM_VERSION:
        this.handleGetPlatformVersionCall(call, result);
        break;
      case Constant.METHOD_CLOSE_DATABASE:
        this.handleCloseDatabaseCall(call, result);
        break;
      case Constant.METHOD_DELETE_DATABASE:
        this.handleDeleteDatabaseCall(call, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    Log.i(TAG, "flutter-sqflite-onAttachedToAbility");
    this.setup(this.pluginBinding!.getBinaryMessenger(), this.pluginBinding!.getApplicationContext());
    this.abilityPluginBinding = binding;
    this.channel?.setMethodCallHandler(this);
  }

  onDetachedFromAbility(): void {
  }

  static registerWith(): void {
  }

  setup(messenger: BinaryMessenger, context: common.Context) {
    try {
      SqfliteApi.setup(messenger, this);
    } catch (err) {
      Log.e(TAG, "Received exception while setting up SqflitePlugin", err);
    }
    this.context = context;
  }

  async options(data: Map<string, Object>): Promise<void> {
    data.forEach((value, key) => {
      Log.i(TAG, 'options收到数据: ' + key + ' -> ' + value);
    })
  }

  getPlatformVersion(): string {
    Log.i(TAG, "HarmonyOS 通信正常");
    return "HarmonyOS 通信正常";
  }

  //----------begin
  ///打开数据库
  async handleOpenDatabaseCall(call: MethodCall, result: MethodResult): Promise<void> {
    await SqfLiteHelper.getDataBase(this.context!, call, result);
  }

  ///获取数据库路径
  handleGetDatabasesPathCall(call: MethodCall, result: MethodResult) {
    let appContext = this.context!.getApplicationContext();
    let path: string = appContext.databaseDir;
    result.success(path);
  }

  ///检查数据库是否存在
  async handleDatabaseExistsCall(call: MethodCall, result: MethodResult): Promise<void> {
    let dbPath: string = call.argument(Constant.PARAM_PATH);
    let isExist: boolean = await SqfLiteHelper.checkDatabaseExisted(dbPath);
    result.success(isExist);
  }

  ///执行Sql
  async handleExecuteCall(call: MethodCall, result: MethodResult): Promise<void> {
    let rdbStore = SqfLiteHelper.getDatabaseOrError(call, result);
    if (rdbStore == null) {
      return;
    }
    let operation: MethodCallOperation = new MethodCallOperation(call, result);

    Database.execute(operation, rdbStore);
  }

  ///插入数据
  async handleInsertCall(call: MethodCall, result: MethodResult): Promise<void> {
    let rdbStore = SqfLiteHelper.getDatabaseOrError(call, result);
    if (rdbStore == null) {
      return;
    }

    let sql: string = call.argument(Constant.PARAM_SQL);
    let dataBaseId: number = call.argument(Constant.PARAM_ID);
    let databaseName: string = SqfLiteHelper.dBIdList.get(dataBaseId) as string;
    let tableName: string = SqlHelper.getInsertSqlTableName(sql);

    let tableExisted = await SqfLiteHelper.checkTable(databaseName, tableName);
    if(tableName.length > 0 && !tableExisted) {
      result.error(Constant.SQLITE_ERROR, 'no such table:' + tableName, '');
      return;
    }

    let operation: MethodCallOperation = new MethodCallOperation(call, result);
    Database.insert(operation, rdbStore);
  }

  ///查询数据
  async handleQueryCall(call: MethodCall, result: MethodResult): Promise<void> {
    Log.i(TAG, "begin query data");
    let rdbStore = SqfLiteHelper.getDatabaseOrError(call, result);
    if (rdbStore == null) {
      return;
    }

    let sql: string = call.argument(Constant.PARAM_SQL);
    let dataBaseId: number = call.argument(Constant.PARAM_ID);
    let databaseName: string = SqfLiteHelper.dBIdList.get(dataBaseId) as string;
    let tableName: string = SqlHelper.getQuerySqlTableName(sql);

    let tableExisted = await SqfLiteHelper.checkTable(databaseName, tableName);
    if(tableName.length > 0 && !tableExisted) {
      result.error(Constant.SQLITE_ERROR, 'no such table:' + tableName, '');
      return;
    }

    let operation: MethodCallOperation = new MethodCallOperation(call, result);
    Database.query(operation, rdbStore);
  }

  ///更新（包括删除）数据
  async handleUpdateCall(call: MethodCall, result: MethodResult): Promise<void> {
    let rdbStore = SqfLiteHelper.getDatabaseOrError(call, result);
    if (rdbStore == null) {
      return;
    }

    let sql: string = call.argument(Constant.PARAM_SQL);
    let dataBaseId: number = call.argument(Constant.PARAM_ID);
    let databaseName: string = SqfLiteHelper.dBIdList.get(dataBaseId) as string;
    let tableName: string = SqlHelper.getUpdateSqlTableName(sql);

    let tableExisted = await SqfLiteHelper.checkTable(databaseName, tableName);
    if(tableName.length > 0 && !tableExisted) {
      result.error(Constant.SQLITE_ERROR, 'no such table:' + tableName, '');
      return;
    }

    let operation: MethodCallOperation = new MethodCallOperation(call, result);
    Database.update(operation, rdbStore);
  }

  ///batch操作
  async handleBatchCall(call: MethodCall, result: MethodResult): Promise<void> {
    let rdbStore = SqfLiteHelper.getDatabaseOrError(call, result);
    if (rdbStore == null) {
      return;
    }
    Database.batch(call, result, rdbStore);
  }

  ///Options操作，设置LogLevel，仅限开发，已废弃
  async handleOptionsCall(call: MethodCall, result: MethodResult): Promise<void> {
    SqfLiteHelper.options(call, result);
  }

  ///设置debug模式，已废弃
  async handleDebugModeCall(call: MethodCall, result: MethodResult): Promise<void> {
    SqfLiteHelper.debugMode(call, result);
  }

  ///获取设备信息
  async handleGetPlatformVersionCall(call: MethodCall, result: MethodResult): Promise<void> {
    SqfLiteHelper.getPlatformVersion(call, result);
  }

  ///关闭数据库
  async handleCloseDatabaseCall(call: MethodCall, result: MethodResult): Promise<void> {
    let rdbStore = SqfLiteHelper.getDatabaseOrError(call, result);
    if (rdbStore == null) {
      return;
    }
    await SqfLiteHelper.closeDataBase(call, result);

  }

  ///删除数据库
  async handleDeleteDatabaseCall(call: MethodCall, result: MethodResult): Promise<void> {
    let dataBaseName: string = call.argument(Constant.PARAM_PATH);
    let res = await SqfLiteHelper.deleteDataBase(this.context!, dataBaseName);
    if (res) {
      result.success(null);
    }else {
      result.error('-1', 'Delete database faile', '');
    }
  }

  //----------end

  /// 获取数据库的路径
  getDatabasesPath(): string {
    let path: string = this.context!.getApplicationContext().databaseDir;
    Log.i(TAG, "鸿蒙 获取数据库路径:" + path);
    /// EL1
    return path;
  }

  /// 打开数据库
  async openDatabaseByInvoke(call: MethodCall, result: MethodResult): Promise<void> {
    let dataBaseName: string = call.argument("path");
    // let id = await SqfLiteHelper.getDataBase(this.context!, dataBaseName) ?? -1;
    // Log.i(TAG, "invoke鸿蒙 打开数据库结果:" + id);
    result.success(-1);
  }

  /// 打开数据库
  async openDatabase(dataBaseName: string): Promise<number> {
    // let id = await SqfLiteHelper.getDataBase(this.context!, dataBaseName) ?? -1;
    // Log.i(TAG, "鸿蒙 打开数据库结果:" + id);
    // result.success(id);
    return -1;
  }

  /// 插入数据
  async insert(data: Map<string, Object>): Promise<number> {
    Log.i(TAG, "鸿蒙 开始插入数据");

    let rowId: number = -1;
    let dbName: string = SqfLiteHelper.dBIdList.get(data.get('id')! as number) ?? '';
    Log.i(TAG, "鸿蒙 插入数据获取数据库名 :" + dbName);
    let dataName: string[] = SqlHelper.getSqlDataName(data.get('sql')! as string);
    Log.i(TAG, "鸿蒙 插入数据获取插入数据列 :" + dataName);
    let tableName: string = SqlHelper.getInsertSqlTableName(data.get('sql')! as string);
    Log.i(TAG, "鸿蒙 插入数据获取表名 :" + tableName);

    try {
      Log.i(TAG, "鸿蒙 取到的arguments 1:" + JSON.stringify(data).toString());
      let txt: string = (data.get('arguments')! as string);
      Log.i(TAG, "鸿蒙 取到的arguments 2:" + txt);
      // let list: string[] = txt.split(",") as string[];
      // todo 这里的数据需要使用flutter传过来的才行
      let list: ValueType[] = [2, 'hi', 2000];
      Log.i(TAG, "鸿蒙 插入数据获取到的值:" + list.toString());
      const valuesBucket: relationalStore.ValuesBucket = {}
      dataName.forEach((value, index) => {
        valuesBucket[value] = list[index];
      })
      rowId = await SqfLiteHelper.insertData(dbName, tableName, valuesBucket);
      Log.i(TAG, "鸿蒙 插入数据返回的行id:" + rowId);
    } catch (e) {
      Log.i(TAG, "鸿蒙 插入数据解析arguments出现异常" + e + rowId);
    }
    return rowId;
  }

  /// 查询数据
  async query(data: Map<string, Object>): Promise<Map<string, Object>> {
    let returnMap: Map<string, Object> = new Map<string, Object>();
    let dbName: string = SqfLiteHelper.dBIdList.get(data.get('id')! as number) ?? '';
    Log.i(TAG, "鸿蒙 查询数据获取数据库名字 :" + dbName);

    if (dbName.length <= 0) {
      Log.i(TAG, "鸿蒙 查询功能没有获取到数据库名字");
      return returnMap;
    }

    if ((data.get('sql')! as string).includes('WHERE') == true) {
      Log.i(TAG, "鸿蒙 开始查询数据");
      let tableName: string = SqlHelper.getQuerySqlTableName(data.get('sql')! as string);
      Log.i(TAG, "鸿蒙 查询数据获取表名 :" + tableName);
      let queryWhere: string[] = SqlHelper.getQuerySqlWhereName(data.get('sql')! as string);
      Log.i(TAG, "鸿蒙 查询数据获取查询数据 :" + queryWhere);
      // let querySELECT: string[] = SqfLiteHelper.getQuerySqlSELECTName(data.get('sql')! as string);
      // Log.i(TAG, "鸿蒙 查询数据获取查询咧 :" + querySELECT);
      let txt: string = (data.get('arguments')! as string);
      // let list: string[] = txt.split(",");
      // todo 这里的数据需要使用flutter传过来的才行
      let list: ValueType[] = [2];
      Log.i(TAG, "鸿蒙 查询数据获取查询值 :" + list.toString());
      Log.i(TAG, "鸿蒙 查询数据获取值完毕");
      Log.i(TAG, "鸿蒙 查询数据传入的数据queryWhere: " + queryWhere[0] + ", list:" + list[0]);

      // querySELECT 先不传 ,list[0] 很奇怪
      // let result = await rdb.query(predicates, querySELECT);
      let result = await SqfLiteHelper.readOneData(dbName, tableName, queryWhere[0], list[0]);
      if (result == null) return returnMap;
      let rowsData: Object[] = [];

      result.forEach((value, key) => {
        let row: Object[] = [];
        value.forEach((v, k) => {
          row.push(v);
        })
        rowsData.push(row);
      })

      returnMap.set('columns', queryWhere);
      returnMap.set('rows', rowsData);
      Log.i(TAG, "鸿蒙 查询数据完毕");
    } else {
      Log.i(TAG, "鸿蒙 开始检查表");
      const tableName = (data.get('sql')! as string).split(" FROM ")[1];
      Log.i(TAG, "鸿蒙 检查表, 表名 :" + tableName, '%{public}s');
      let result = await SqfLiteHelper.checkTable(dbName, tableName);
      returnMap.set('checkTable', result);
    }
    return returnMap;
  }

  /// 更新数据
  async update(data: Map<string, Object>): Promise<number> {
    Log.i(TAG, "鸿蒙 开始修改数据");
    let rowId: number = -1;
    if ((data.get('sql') as string).includes('UPDATE')) {
      let dbName: string = SqfLiteHelper.dBIdList.get(data.get('id')! as number) ?? '';
      Log.i(TAG, "鸿蒙 更新数据获取数据库名:" + dbName);
      let tableName: string = SqlHelper.getUpdateSqlTableName(data.get('sql')! as string);
      Log.i(TAG, "鸿蒙 更新数据获取表名:" + tableName);
      let queryWhere: string[] = SqlHelper.getUpdateSqlWhereName(data.get('sql')! as string);
      Log.i(TAG, "鸿蒙 更新数据获取where:" + queryWhere);
      let querySET: string[] = SqlHelper.getUpdateSqlSETName(data.get('sql')! as string);
      Log.i(TAG, "鸿蒙 更新数据获取列:" + querySET);

      let txt: string = (data.get('arguments')! as string);
      // let list: string[] = txt.split(",");
      // todo 这里的数据需要使用flutter传过来的才行
      let list: ValueType[] = ['hello', 2023, 2];
      Log.i(TAG, "鸿蒙 修改数据获取到的值:" + list.toString());
      const valuesBucket: relationalStore.ValuesBucket = {}
      querySET.forEach((value, index) => {
        valuesBucket[value] = list[index];
      })

      /// todo where的参数在list的后面, 要根据那个where输入的长度来动态获取
      rowId = await SqfLiteHelper.updateData(dbName, tableName, queryWhere[0], list[list.length-1], valuesBucket);
      Log.i(TAG, "鸿蒙 修改数据成功的行id:" + rowId);
    } else {
      rowId = await this.delete(data);
      Log.i(TAG, "鸿蒙 删除数据成功的行id:" + rowId);
    }
    return rowId;
  }

  /// 删除数据
  async delete(data: Map<string, Object>): Promise<number> {
    let rowId: number = -1;

    let dbName: string = SqfLiteHelper.dBIdList.get(data.get('id')! as number) ?? '';
    Log.i(TAG, "鸿蒙 删除数据获取数据库名:" + dbName);
    let tableName: string = SqlHelper.getDeleteSqlTableName(data.get('sql')! as string);
    Log.i(TAG, "鸿蒙 删除数据获取表名:" + tableName);
    let queryWhere: string[] = SqlHelper.getDeleteSqlWhereName(data.get('sql')! as string);
    Log.i(TAG, "鸿蒙 删除数据获取where:" + queryWhere);

    let txt: string = (data.get('arguments')! as string);
    // let list: string[] = txt.split(",");
    // todo 这里的数据需要使用flutter传过来的才行
    let list: ValueType[] = [2];
    Log.i(TAG, "鸿蒙 删除数据获取值:" + list.toString());
    rowId = await SqfLiteHelper.deleteData(dbName, tableName, queryWhere[0], list[0]);

    return rowId;
  }

  /// 关闭一个数据库
  async closeDatabase(dataBaseName: string): Promise<void> {
    // SqfLiteHelper.closeDataBase(dataBaseName);
    Log.i(TAG, "鸿蒙 关闭数据库成功");
  }

  /// 删除数据库
  async deleteDatabase(dataBaseName: string): Promise<boolean> {
    let result = await SqfLiteHelper.deleteDataBase(this.context!, dataBaseName);
    Log.i(TAG, "鸿蒙 删除数据库成功");
    return result;
  }

  /// 执行sql语句
  async execute(data: Map<string, Object>): Promise<void> {
    let dbName: string = SqfLiteHelper.dBIdList.get(data.get('id')! as number) ?? '';
    // await SqfLiteHelper.execute(dbName, data.get('sql')! as string);
    Log.i(TAG, "鸿蒙 执行sql语句成功");
  }

  /// 检查数据库是否存在
  async databaseExists(dataBaseName: string): Promise<boolean> {
    let result: boolean = SqfLiteHelper.databaseExists(dataBaseName);
    Log.i(TAG, "鸿蒙 查询数据库是否存在成功, 结果:" + result.toString());
    return result;
  }
}