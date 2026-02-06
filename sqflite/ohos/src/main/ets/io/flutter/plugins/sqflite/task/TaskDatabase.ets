/*
* Copyright (c) 2025 Hunan OpenValley Digital Industry Development Co., Ltd.
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

import taskPool from '@ohos.taskpool';
import common from '@ohos.app.ability.common';
import { logger } from '../../utils/Logger';
import { Operation } from '../operation/Operation';
import { SqlCommand } from '../SqlCommand';
import { Constant } from '../OhosConstant';
import relationalStore from '@ohos.data.relationalStore';
import { ValueType } from '@ohos.data.ValuesBucket';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { DatabaseHelper } from '../DatabaseHelper';
import { Database } from '../Database';

const TAG = 'TaskDatabase';


@Concurrent
async function query(context: common.Context, config: relationalStore.StoreConfig,
  sql: string, sqlArguments: ValueType[], cursorPageSize: number): Promise<Map<String, Object>> {

  const db = await relationalStore.getRdbStore(context, config);

  const results: Map<String, Object> = new Map<String, Object>();

  let resultSet = await db.querySql(sql, sqlArguments);

  let rows: Array<Array<Object>> = new Array<Array<Object>>();
  let columns: Array<string> | null = null;
  let valuesType: Array<string> | null = null;
  let columnCount: number = 0;

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

    let row = new Array<Object>();

    for (let index = 0; index < columnCount; index++) {
      let rowValue: Object | null = null;
      const valuesTypeItem = valuesType![index];
      if ('number' == valuesTypeItem) {
        // 策略：优先使用 getValue()，只在大整数时用 getString() 精确处理
        let directValue = resultSet.getValue(index);
        
        // 如果不是 number 类型，直接使用（例如 null）
        if (typeof directValue !== 'number') {
          rowValue = directValue;
        } 
        // 如果是安全整数范围内的整数，直接使用
        else if (Number.isInteger(directValue) &&
                 directValue <= Number.MAX_SAFE_INTEGER && 
                 directValue >= Number.MIN_SAFE_INTEGER) {
          rowValue = directValue;
        }
        // 如果是浮点数（有小数部分），直接使用
        else if (!Number.isInteger(directValue)) {
          rowValue = directValue;
        }
        // 可能是大整数，用 getString 精确处理
        else {
          let value = resultSet.getString(index);
          if (!value) {
            rowValue = directValue;
          } else {
            // 判断是否为纯整数格式（不包括科学计数法）
            let isIntegerString = /^-?\d+$/.test(value);
            if (isIntegerString) {
              try {
                let valueBig = BigInt(value);
                if (valueBig > Number.MAX_SAFE_INTEGER || valueBig < Number.MIN_SAFE_INTEGER) {
                  rowValue = valueBig;
                } else {
                  rowValue = Number.parseInt(value);
                }
              } catch (e) {
                rowValue = directValue;
              }
            } else {
              // 其他情况（包括科学计数法），使用原始数值
              rowValue = directValue;
            }
          }
        }
      } else {
        rowValue = resultSet.getValue(index);
      }
      row.push(rowValue!!);
    }
    rows.push(row);
    if (cursorPageSize != null && cursorPageSize != -1) {
      if (rows.length >= cursorPageSize) {
        break;
      }
    }
  }

  // 释放数据集的内存
  resultSet.close();
  db.close();
  return results;
}


@Concurrent
async function insert(context: common.Context, config: relationalStore.StoreConfig,
  sql: string, sqlArguments: ValueType[]): Promise<ValueType | undefined> {
  const db = await relationalStore.getRdbStore(context, config);
  const res: ValueType | undefined = await db.execute(sql,sqlArguments) as ValueType;
  db.close();
  return res;
}

export async function taskPoolExecuteQuery(context: common.Context, operation: Operation,db: relationalStore.RdbStore): Promise<void> {
  try {
    const command: SqlCommand = operation.getSqlCommand();
    const sql: string = command.getSql();
    const sqlArguments: ValueType[] | undefined = operation.getArgument(Constant.PARAM_SQL_ARGUMENTS) as ValueType[];
    const cursorPageSizeRaw: number | null | undefined = operation.getArgument(Constant.PARAM_CURSOR_PAGE_SIZE);
    const config = getStoreConfig(operation);
    // 条件1: 游标分页查询（需要保持 ResultSet 打开）
    const isCursorQuery = typeof cursorPageSizeRaw === 'number' && cursorPageSizeRaw > 0;
    // 条件2: 在事务中的查询（需要共享同一个 db 连接）
    const hasTransactionId = !operation.hasNullTransactionId();
    const inTransaction = hasTransactionId || operation.getInTransactionChange() === true;
    // 条件3: 用户版本查询（特殊处理）
    const isUserVersionQuery = sql == Constant.SQL_PRAGMA_USER_VERSION;

    // 判断是否需要使用 Database.query
    if (isUserVersionQuery) {
      const result: Map<String, Object> = new Map<String, Object>();
      result.set(Constant.PARAM_COLUMNS, [Constant.PARAM_USER_VERSION]);
      result.set(Constant.PARAM_ROWS, [[db.version]]);
      operation.success(result);
    } else if (isCursorQuery || inTransaction) {
      await Database.query(operation, db);
    } else {
      const cursorPageSize = -1; // 普通查询不需要分页
      const task: taskPool.Task =
        new taskPool.Task(query, context, config, sql, sqlArguments ?? [], cursorPageSize);
      const result: Map<String, Object> = await taskPool.execute(task) as Map<String, Object>;
      operation.success(result);
    }
  } catch (err) {
    handleException(operation, err);
  }
}

export async function taskPoolExecuteInsert(context: common.Context, operation: Operation): Promise<void> {
  try {
    const command: SqlCommand = operation.getSqlCommand();
    const sql: string = command.getSql();
    const sqlArguments: ValueType[] | undefined = operation.getArgument(Constant.PARAM_SQL_ARGUMENTS) as ValueType[];
    const config = getStoreConfig(operation);

    const task: taskPool.Task = new taskPool.Task(insert, context, config, sql, sqlArguments ?? []);
    const result: ValueType | undefined = await taskPool.execute(task) as ValueType;
    if(result){
      operation.success(result);
    }
    else{
      operation.success(null);
    }
  } catch (err) {
    handleException(operation, err);
  }
}

function getStoreConfig(operation: Operation):relationalStore.StoreConfig{

  const currentDbId: number | undefined = operation.getArgument(Constant.PARAM_ID) as number;
  const dbName: string = DatabaseHelper.getMemoryDatabaseNameByDatabaseId(currentDbId);
  const isReadOnly: boolean = DatabaseHelper.dbIdOnlyMap.get(currentDbId) ?? false;

  const config: relationalStore.StoreConfig = {
    name: dbName, // 数据库文件名
    securityLevel: relationalStore.SecurityLevel.S1,
    isReadOnly: isReadOnly,
    tokenizer: undefined
  }

  if(deviceInfo.sdkApiVersion >= Constant.API_17){
    config.tokenizer = relationalStore.Tokenizer.ICU_TOKENIZER
  }

  return config;
}

function handleException(operation: Operation, err: BusinessError<void>) {
  let code = err.code;
  let message = err.message;
  if (code == Constant.RDB_ERROR_CODE_801) {
    message = message + " Database is readonly"
  }
  logger.error(TAG, 'error code:' + code + '。' + message);
  operation.error(Constant.SQLITE_ERROR, 'error code:' + code + '。' + message, '');
}