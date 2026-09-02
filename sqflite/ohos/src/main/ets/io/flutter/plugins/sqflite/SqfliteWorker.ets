/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
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

// 本 worker 由 SqflitePlugin 自建，主线程按 seq 路由 reply，物理上不串号。
// decode + handler 全在 worker 线程（治 B 层解码应用无响应 + A 层执行掉帧），
// 等价 Android makeBackgroundTaskQueue + DatabaseWorkerPool(THREAD_COUNT=1)。
// context 不存字段，随每条 message 透传。
// worker 内串行队列（queue + running 逐条 await）：worker async onmessage 会并发，
// 必须串行化以保证全局 static（transactionDepth/cursorMap/currentTransactionId）不竞态，
// 等价 Android 单工作线程 FIFO。

import { ErrorEvent, MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import common from '@ohos.app.ability.common';
import relationalStore from '@ohos.data.relationalStore';
import fs from '@ohos.file.fs';
// 用非 Sendable 的 StandardMethodCodec，而非 SendableStandardMethodCodec：
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';
import StringUtils from '@ohos/flutter_ohos/src/main/ets/util/StringUtils';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import Any from '@ohos/flutter_ohos/src/main/ets/plugin/common/Any';
import { Database } from './Database';
import { DatabaseHelper } from './DatabaseHelper';
import { MethodCallOperation } from './operation/MethodCallOperation';
import { Constant } from './OhosConstant';

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;
// worker 本地实例（非 Sendable 类每个 worker 各自模块静态），不与主线程共享。
const codec = StandardMethodCodec.INSTANCE;

interface SqfliteTask {
  seq: number;
  message: ArrayBuffer;
  context: common.Context;
}

// 串行队列：逐条 await，保证 worker 内一次只处理一条 message（等价 Android THREAD_COUNT=1）。
const queue: SqfliteTask[] = [];
let running: boolean = false;

workerPort.onmessage = (e: MessageEvents): void => {
  queue.push(e.data as SqfliteTask);
  if (!running) {
    runQueue();
  }
};

// worker 内同步路径未捕获异常的恢复：分页游标依附的执行状态可能已损坏，
// 统一关闭全部缓存游标释放 native 句柄（后续续页请求将收到 Cursor not found，属可接受降级）。
// 异步路径的异常由 handleOne/runQueue 的 catch/finally 兜底，不经过此处。
workerPort.onerror = (e: ErrorEvent): void => {
  Log.e('SqfliteWorker', `worker onerror, closing all cached cursors: ${e.message}`);
  Database.closeAllCursors();
};

// running 必须在 finally 里复位：若 handleOne reject（例如 postMessage 传输失败），
// 不复位会让此后到达的每条 message 永久滞留队列、never 派发，整条 sqflite 通道假死。
async function runQueue(): Promise<void> {
  running = true;
  try {
    while (queue.length > 0) {
      const task: SqfliteTask = queue.shift() as SqfliteTask;
      await handleOne(task.seq, task.message, task.context);
    }
  } finally {
    running = false;
  }
}

// 内存库孤儿临时文件补偿清理标记：每个 worker 生命周期只清理一次
let orphanMemoryDbCleaned: boolean = false;

// 严格匹配内存库临时文件名 temp_memory_<纯数字时间戳>.db：临时文件命名固定为
// MEMORY_DB_TEMP_PREFIX + Date.now() + '.db'（DatabaseHelper.openDatabase），
// 中段校验为纯数字可避免误删用户以 temp_memory_ 开头命名的常规数据库（如 temp_memory_custom.db）
const orphanMemoryDbNamePattern: RegExp =
  new RegExp('^' + Constant.MEMORY_DB_TEMP_PREFIX + '[0-9]+\\.db$');

// 内存库孤儿临时文件补偿清理：worker 每次重建（热重启/重新 attach）后，静态 memoryDbMap
// 随旧 worker 销毁，上一生命周期残留的 temp_memory_*.db 成为无人认领的孤儿文件。
// 本 worker 首条消息时扫描默认库目录，按文件名删除补偿清理（串行队列保证先于任何新开库执行）。
async function cleanupOrphanMemoryDatabases(context: common.Context): Promise<void> {
  if (orphanMemoryDbCleaned) {
    return;
  }
  orphanMemoryDbCleaned = true;
  try {
    const databaseDir: string = context.getApplicationContext().databaseDir;
    // 内存库创建时不带 customDir，只可能位于默认库目录（databaseDir 及其 rdb 子目录），两处都扫一遍
    const candidateDirs: string[] = [databaseDir, databaseDir + '/rdb'];
    const orphanPaths: Set<string> = new Set<string>();
    for (const dir of candidateDirs) {
      try {
        const names: string[] = await fs.listFile(dir);
        names.forEach((name: string) => {
          if (orphanMemoryDbNamePattern.test(name)) {
            orphanPaths.add(dir + '/' + name);
          }
        });
      } catch (e) {
        // 目录不存在（本应用尚未创建过数据库）属正常情况，跳过
      }
    }
    for (const filePath of orphanPaths) {
      try {
        await fs.unlink(filePath);
        Log.i('SqfliteWorker', `cleaned orphan memory database file: ${filePath}`);
        for (const suffix of ['-wal', '-shm']) {
          try {
            await fs.unlink(filePath + suffix);
          } catch (e) {
            // 伴随文件不存在属正常情况，跳过
          }
        }
      } catch (e) {
        Log.e('SqfliteWorker', `clean orphan memory database ${filePath} failed: ${e}`);
      }
    }
  } catch (e) {
    Log.e('SqfliteWorker', `scan orphan memory databases failed: ${e}`);
  }
}

async function handleOne(seq: number, message: ArrayBuffer, context: common.Context): Promise<void> {
  // worker 生命周期内首条消息时补偿清理孤儿内存库临时文件（详见 cleanupOrphanMemoryDatabases）
  await cleanupOrphanMemoryDatabases(context);
  let result: ArrayBuffer | null = null;
  try {
    const call: MethodCall = codec.decodeMethodCall(message);
    // reply 包装：success/error/notImplemented 把编码后的 envelope 写入 captured，
    // dispatch 完成后随 seq 回主线程（主线程按 seq 精确路由，不重写 onmessage）。
    let captured: ArrayBuffer | null = null;
    const methodResult: MethodResult = {
      success: (r: Any): void => {
        captured = codec.encodeSuccessEnvelope(r);
      },
      error: (errorCode: string, errorMessage: string, errorDetails: Any): void => {
        captured = codec.encodeErrorEnvelope(errorCode, errorMessage, errorDetails);
      },
      notImplemented: (): void => {
        captured = StringUtils.stringToArrayBuffer('');
      }
    };
    await dispatch(call, methodResult, context);
    result = captured;
    // 回执必须在 try 内发出：postMessage 自身若抛（transfer 失败/worker 已终止），
    // 走 catch 回 error envelope，并由 runQueue 的 finally 兜底复位 running，不会假死。
    workerPort.postMessage({ seq: seq, result: result }, result ? [result] : []);
  } catch (err) {
    // 兜底：保证每条 message 一定有回执（哪怕是 error），
    // 否则主线程 pending 永久残留该 seq。
    result = codec.encodeErrorEnvelope('error', String(err), null);
    try {
      workerPort.postMessage({ seq: seq, result: result }, [result]);
    } catch (e) {
      // workerPort 彻底不可用，已无法回执；记录后只能放弃
      // （runQueue 的 finally 仍会让队列复位）。
      Log.e('SqfliteWorker', `postMessage failed for seq=${seq}: ${e}`);
    }
  }
}

async function dispatch(call: MethodCall, result: MethodResult, context: common.Context): Promise<void> {
  switch (call.method) {
    case Constant.METHOD_OPEN_DATABASE:
      await DatabaseHelper.openDatabase(context, call, result);
      break;
    case Constant.METHOD_GET_DATABASES_PATH:
      handleGetDatabasesPathCall(context, result);
      break;
    case Constant.METHOD_DATABASE_EXISTS:
      await handleDatabaseExistsCall(call, result);
      break;
    case Constant.METHOD_EXECUTE:
      await handleExecuteCall(call, result);
      break;
    case Constant.METHOD_INSERT:
      await handleInsertCall(call, result);
      break;
    case Constant.METHOD_QUERY:
      await handleQueryCall(call, result);
      break;
    case Constant.METHOD_QUERY_CURSOR_NEXT:
      await handleQueryCursorNextCall(call, result);
      break;
    case Constant.METHOD_UPDATE:
      await handleUpdateCall(call, result);
      break;
    case Constant.METHOD_BATCH:
      await handleBatchCall(call, result);
      break;
    case Constant.METHOD_OPTIONS:
      DatabaseHelper.options(call, result);
      break;
    case Constant.METHOD_DEBUG:
      DatabaseHelper.onDebug(call, result);
      break;
    case Constant.METHOD_DEBUG_MODE:
      DatabaseHelper.debugMode(call, result);
      break;
    case Constant.METHOD_GET_PLATFORM_VERSION:
      DatabaseHelper.getPlatformVersion(call, result);
      break;
    case Constant.METHOD_CLOSE_DATABASE:
      await handleCloseDatabaseCall(call, result);
      break;
    case Constant.METHOD_DELETE_DATABASE:
      await handleDeleteDatabaseCall(context, call, result);
      break;
    default:
      result.notImplemented();
      break;
  }
}

///获取数据库路径
function handleGetDatabasesPathCall(context: common.Context, result: MethodResult): void {
  let appContext = context.getApplicationContext();
  let path: string = appContext.databaseDir + '/rdb';
  result.success(path);
}

///检查数据库是否存在
async function handleDatabaseExistsCall(call: MethodCall, result: MethodResult): Promise<void> {
  let dbPath: string = call.argument(Constant.PARAM_PATH) as string;
  // 参数校验：path 缺失/类型错误时回 bad_param，避免 fs.access 收到畸形路径
  if (typeof dbPath !== 'string' || dbPath.length === 0) {
    result.error(Constant.ERROR_BAD_PARAM, 'Invalid null or empty path argument', null);
    return;
  }
  let isExist: boolean = await DatabaseHelper.checkDatabaseExists(dbPath);
  result.success(isExist);
}

///执行Sql
async function handleExecuteCall(call: MethodCall, result: MethodResult): Promise<void> {
  let rdbStore: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseOrError(call, result);
  if (rdbStore == null) {
    return;
  }
  let operation: MethodCallOperation = new MethodCallOperation(call, result);
  await Database.execute(operation, rdbStore);
}

///插入数据
async function handleInsertCall(call: MethodCall, result: MethodResult): Promise<void> {
  let rdbStore: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseOrError(call, result);
  if (rdbStore == null) {
    return;
  }
  let operation: MethodCallOperation = new MethodCallOperation(call, result);
  await Database.insert(operation, rdbStore);
}

///查询数据
async function handleQueryCall(call: MethodCall, result: MethodResult): Promise<void> {
  let rdbStore: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseOrError(call, result);
  if (rdbStore == null) {
    return;
  }
  const operation: MethodCallOperation = new MethodCallOperation(call, result);
  await Database.query(operation, rdbStore);
}

///查询游标下一页数据
async function handleQueryCursorNextCall(call: MethodCall, result: MethodResult): Promise<void> {
  // 对齐 Android onQueryCursorNextCall：先校验数据库存活，库已关闭时报
  // database_closed <id>，而非误导性的 Cursor not found: <id>
  let rdbStore: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseOrError(call, result);
  if (rdbStore == null) {
    return;
  }
  let operation: MethodCallOperation = new MethodCallOperation(call, result);
  await Database.queryCursorNext(operation);
}

///更新（包括删除）数据
async function handleUpdateCall(call: MethodCall, result: MethodResult): Promise<void> {
  let rdbStore: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseOrError(call, result);
  if (rdbStore == null) {
    return;
  }
  let operation: MethodCallOperation = new MethodCallOperation(call, result);
  await Database.update(operation, rdbStore);
}

///batch操作
async function handleBatchCall(call: MethodCall, result: MethodResult): Promise<void> {
  let rdbStore: relationalStore.RdbStore | null = DatabaseHelper.getDatabaseOrError(call, result);
  if (rdbStore == null) {
    return;
  }
  await Database.batch(call, result, rdbStore);
}

///关闭数据库
async function handleCloseDatabaseCall(call: MethodCall, result: MethodResult): Promise<void> {
  // close 不经 getDatabaseOrError：占位数据库（损坏文件懒失败）的条目在该入口会被
  // "file is not a database" 拦截，导致 closeDatabase 永不被调用、占位条目无法清理；
  // closeDatabase 内部自带 id 校验与 database_closed 回执，可独立处理占位条目
  const dbId: number = call.argument(Constant.PARAM_ID) as number;
  if (typeof dbId !== 'number') {
    result.error(Constant.ERROR_BAD_PARAM, 'Invalid null id argument', null);
    return;
  }
  // 关闭数据库前重置全局事务状态（深度/当前事务 id/事务内建表记录），
  // 避免多个数据库共享静态变量导致状态残留泄漏到下一个库；
  // 仅当被关的库恰是当前事务持有者时才真正清零（关闭无关库不影响其他库的进行中事务）
  Database.resetTransactionState(dbId);
  await DatabaseHelper.closeDatabase(call, result);
}

///删除数据库
// 对齐 Android onDeleteDatabaseCall：先关闭该路径已打开的单实例再删除文件，
// 删除失败吞掉异常（DatabaseHelper 内部记录日志），恒定 success(null)。
async function handleDeleteDatabaseCall(context: common.Context, call: MethodCall,
  result: MethodResult): Promise<void> {
  let dbPath: string = call.argument(Constant.PARAM_PATH) as string;
  // 参数校验：path 缺失/类型错误时回 bad_param，避免删除操作收到畸形路径
  if (typeof dbPath !== 'string' || dbPath.length === 0) {
    result.error(Constant.ERROR_BAD_PARAM, 'Invalid null or empty path argument for deleteDatabase', null);
    return;
  }
  await DatabaseHelper.deleteDatabase(context, dbPath);
  result.success(null);
}
