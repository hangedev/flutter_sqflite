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
import BasicMessageChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/BasicMessageChannel';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import MessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/MessageCodec';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import { SqlHelper } from './sql_helper';


const TAG: string = "Message";

export default class Messages {
  static wrapError(exception: Error): Array<ESObject> {
    const errorList: Array<ESObject> = new Array();
    if (exception instanceof FlutterError) {
      const error = exception;
      errorList.push(error.code);
      errorList.push(error.message);
      errorList.push(error.details);
    } else {
      errorList.push(exception.name);
      errorList.push(exception.message);
      errorList.push(exception.stack);
    }
    return errorList;
  }
}

export class FlutterError extends Error {
  code: string;
  details: ESObject;

  constructor(code: string, message: string, details: ESObject) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

export abstract class SqfliteApi {
  abstract getPlatformVersion(): string;

  /// 打开数据库
  abstract options(data: Map<string, Object>): Promise<void>;

  /// 获取数据库存储的基本路径
  abstract getDatabasesPath(): string;

  /// 打开数据库
  abstract openDatabase(dataBaseName: string): Promise<number>;

  /// 增加数据
  abstract insert(data: Map<string, Object>): Promise<number>;

  /// 查询数据
  abstract query(data: Map<string, Object>): Promise<Map<string, Object>>;

  /// 修改数据
  abstract update(data: Map<string, Object>): Promise<number>;

  /// 关闭数据库
  abstract closeDatabase(dataBaseName: string): Promise<void>;

  /// 删除数据库
  abstract deleteDatabase(dataBaseName: string): Promise<boolean>;

  /// 执行sql语句
  abstract execute(data: Map<string, Object>): Promise<void>;

  /// 检查数据库是否存在
  abstract databaseExists(dataBaseName: string): Promise<boolean>;

  static getCodec(): MessageCodec<ESObject> {
    return new StandardMessageCodec();
  }

  static setup(binaryMessenger: BinaryMessenger, api: SqfliteApi) {
    Log.i(TAG, "鸿蒙setup成功 ");
    {
      Log.i(TAG, "鸿蒙options初始化成功");
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.SqfliteApi.options",
        SqfliteApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: async (message: ESObject, reply: ESObject) => {
            Log.i(TAG, "鸿蒙调用options成功 ");
            let wrapped: Array<ESObject> = new Array<ESObject>();
            try {
              Log.i(TAG, "鸿蒙 options 通道接收的数据: " + SqlHelper.mapToJson(message as Map<string, Object>));
              await api.options(message as Map<string, Object>);
              wrapped.push(null);
            } catch (err) {
              const wrappedError: Array<ESObject> = Messages.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped);
          }
        })
      } else {
        Log.i(TAG, "鸿蒙返回null ");
        channel.setMessageHandler(null);
      }
    }
    {
      Log.i(TAG, "鸿蒙getPlatformVersion初始化成功");
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.SqfliteApi.getPlatformVersion",
        SqfliteApi.getCodec());
      if (api != null) {

        channel.setMessageHandler({
          onMessage: (message: ESObject, reply: ESObject) => {
            Log.i(TAG, "鸿蒙调用getPlatformVersion成功 ");
            let wrapped: Array<ESObject> = new Array<ESObject>();
            try {
              Log.i(TAG, "鸿蒙 getPlatformVersion 通道接收的数据: " + SqlHelper.mapToJson(message as Map<string, Object>));
              const output = api.getPlatformVersion();
              wrapped.push(output);
            } catch (err) {
              const wrappedError: Array<ESObject> = Messages.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped);
          }
        })
      } else {
        Log.i(TAG, "鸿蒙返回null ");
        channel.setMessageHandler(null);
      }
    }
    {
      Log.i(TAG, "鸿蒙getDatabasesPath初始化成功");
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.SqfliteApi.getDatabasesPath",
        SqfliteApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: (message: ESObject, reply: ESObject) => {
            Log.i(TAG, "鸿蒙调用getDatabasesPath成功 ");
            let wrapped: Array<ESObject> = new Array<ESObject>();
            try {
              const output = api.getDatabasesPath();
              Log.i(TAG, "getDatabasesPath 通道获取的数据: " + output as string);
              wrapped.push(output);
            } catch (err) {
              const wrappedError: Array<ESObject> = Messages.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped);
          }
        })
      } else {
        Log.i(TAG, "鸿蒙返回null ");
        channel.setMessageHandler(null);
      }
    }
    {
      Log.i(TAG, "鸿蒙openDatabase初始化成功");
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.SqfliteApi.openDatabase",
        SqfliteApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: async (message: ESObject, reply: ESObject) => {
            Log.i(TAG, "鸿蒙调用openDatabase成功 ");
            let wrapped: Array<ESObject> = new Array<ESObject>();
            try {
              Log.i(TAG, "鸿蒙 openDatabase 通道接收的数据: " + SqlHelper.mapToJson(message as Map<string, Object>));
              let dbName: string = SqlHelper.getLastPathName((message as Map<string, Object>).get('path')!.toString());
              const output = await api.openDatabase(dbName);
              if (output >= 0) {
                let returnMap = new Map<string, number>();
                returnMap.set('id', output);
                // todo 这里是不是需要自己写json返回去
                wrapped.push('{"id":1}');
                // wrapped.push(returnMap);
                Log.i(TAG, "鸿蒙 openDatabase 通道创建数据库成功, 数据库id: " + output);
              } else {
                wrapped.push(null);
                Log.i(TAG, "鸿蒙 openDatabase 通道创建数据库失败");
              }
            } catch (err) {
              Log.i(TAG, "鸿蒙 openDatabase 通道创建数据库在message出现异常: " + err);
              const wrappedError: Array<ESObject> = Messages.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped);
          }
        })
      } else {
        Log.i(TAG, "鸿蒙返回null ");
        channel.setMessageHandler(null);
      }
    }
    {
      Log.i(TAG, "鸿蒙insert初始化成功");
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.SqfliteApi.insert",
        SqfliteApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: async (message: ESObject, reply: ESObject) => {
            Log.i(TAG, "鸿蒙调用insert成功 ");
            let wrapped: Array<ESObject> = new Array<ESObject>();
            try {
              Log.i(TAG, "鸿蒙 insert 通道接收的数据: " + SqlHelper.mapToJson(message as Map<string, Object>));
              const output = await api.insert(message as Map<string, Object>);
              wrapped.push(output);
            } catch (err) {
              const wrappedError: Array<ESObject> = Messages.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped);
          }
        })
      } else {
        Log.i(TAG, "鸿蒙返回null ");
        channel.setMessageHandler(null);
      }
    }
    {
      Log.i(TAG, "鸿蒙query初始化成功");
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.SqfliteApi.query",
        SqfliteApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: async (message: ESObject, reply: ESObject) => {
            Log.i(TAG, "鸿蒙调用query成功 ");
            let wrapped: Array<ESObject> = new Array<ESObject>();
            try {
              Log.i(TAG, "鸿蒙 query 通道接收的数据: " + SqlHelper.mapToJson(message as Map<string, Object>));
              const output = await api.query(message as Map<string, Object>);
              wrapped.push(output);
            } catch (err) {
              const wrappedError: Array<ESObject> = Messages.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped);
          }
        })
      } else {
        Log.i(TAG, "鸿蒙返回null ");
        channel.setMessageHandler(null);
      }
    }

    {
      Log.i(TAG, "鸿蒙update初始化成功");
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.SqfliteApi.update",
        SqfliteApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: async (message: ESObject, reply: ESObject) => {
            Log.i(TAG, "鸿蒙调用update成功 ");
            let wrapped: Array<ESObject> = new Array<ESObject>();
            try {
              Log.i(TAG, "鸿蒙 update 通道接收的数据: " + SqlHelper.mapToJson(message as Map<string, Object>));
              const output = await api.update(message as Map<string, Object>);
              wrapped.push(output);
            } catch (err) {
              const wrappedError: Array<ESObject> = Messages.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped);
          }
        })
      } else {
        Log.i(TAG, "鸿蒙返回null ");
        channel.setMessageHandler(null);
      }
    }
    {
      Log.i(TAG, "鸿蒙closeDatabase初始化成功");
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.SqfliteApi.closeDatabase",
        SqfliteApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: async (message: ESObject, reply: ESObject) => {
            Log.i(TAG, "鸿蒙调用closeDatabase成功 ");
            let wrapped: Array<ESObject> = new Array<ESObject>();
            try {
              Log.i(TAG, "鸿蒙 closeDatabase 通道接收的数据: " + SqlHelper.mapToJson(message as Map<string, Object>));
              let dbName: string = SqlHelper.getLastPathName((message as Map<string, Object>).get('path') as string);
              const output = await api.closeDatabase(dbName);
              wrapped.push(output);
            } catch (err) {
              const wrappedError: Array<ESObject> = Messages.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped);
          }
        })
      } else {
        Log.i(TAG, "鸿蒙返回null ");
        channel.setMessageHandler(null);
      }
    }

    {
      Log.i(TAG, "鸿蒙deleteDatabase初始化成功");
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.SqfliteApi.deleteDatabase",
        SqfliteApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: async (message: ESObject, reply: ESObject) => {
            Log.i(TAG, "鸿蒙调用deleteDatabase成功 ");
            let wrapped: Array<ESObject> = new Array<ESObject>();
            try {
              Log.i(TAG, "鸿蒙 deleteDatabase 通道接收的数据: " + SqlHelper.mapToJson(message as Map<string, Object>));
              let dbName: string = SqlHelper.getLastPathName((message as Map<string, Object>).get('path') as string);
              const output = await api.deleteDatabase(dbName);
              wrapped.push(output);
            } catch (err) {
              const wrappedError: Array<ESObject> = Messages.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped);
          }
        })
      } else {
        Log.i(TAG, "鸿蒙返回null ");
        channel.setMessageHandler(null);
      }
    }

    {
      Log.i(TAG, "鸿蒙execute初始化成功");
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.SqfliteApi.execute",
        SqfliteApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: async (message: ESObject, reply: ESObject) => {
            Log.i(TAG, "鸿蒙调用execute成功 ");
            let wrapped: Array<ESObject> = new Array<ESObject>();
            try {
              Log.i(TAG, "鸿蒙 execute 通道接收的数据: " + SqlHelper.mapToJson(message as Map<string, Object>));
              const output = await api.execute(message as Map<string, Object>);
              wrapped.push(output);
            } catch (err) {
              const wrappedError: Array<ESObject> = Messages.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped);
          }
        })
      } else {
        Log.i(TAG, "鸿蒙返回null ");
        channel.setMessageHandler(null);
      }
    }

    {
      Log.i(TAG, "鸿蒙databaseExists初始化成功");
      const channel: BasicMessageChannel<ESObject> =
      new BasicMessageChannel<ESObject>(
        binaryMessenger,
        "dev.flutter.pigeon.SqfliteApi.databaseExists",
        SqfliteApi.getCodec());
      if (api != null) {
        channel.setMessageHandler({
          onMessage: async (message: ESObject, reply: ESObject) => {
            Log.i(TAG, "鸿蒙调用databaseExists成功 ");
            let wrapped: Array<ESObject> = new Array<ESObject>();
            try {
              Log.i(TAG, "鸿蒙 databaseExists 通道接收的数据: " + SqlHelper.mapToJson(message as Map<string, Object>));
              let dbName: string = SqlHelper.getLastPathName((message as Map<string, Object>).get('path') as string);
              const output = await api.databaseExists(dbName);
              wrapped.push(output);
            } catch (err) {
              const wrappedError: Array<ESObject> = Messages.wrapError(err);
              wrapped = wrappedError;
            }
            reply.reply(wrapped);
          }
        })
      } else {
        Log.i(TAG, "鸿蒙返回null ");
        channel.setMessageHandler(null);
      }
    }
  }
}