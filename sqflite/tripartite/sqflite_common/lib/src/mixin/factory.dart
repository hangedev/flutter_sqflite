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

import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/src/factory_mixin.dart';

/// Mixin handler
abstract class SqfliteInvokeHandler {
  /// Invoke method
  Future<T> invokeMethod<T>(String method, [Object? arguments]);
}

class _SqfliteDatabaseFactoryImpl
    with SqfliteDatabaseFactoryMixin
    implements SqfliteInvokeHandler {
  _SqfliteDatabaseFactoryImpl(this._invokeMethod, {String? tag}) {
    this.tag = tag;
  }

  final Future<dynamic> Function(String method, [Object? arguments])
      _invokeMethod;

  @override
  Future<T> invokeMethod<T>(String method, [Object? arguments]) async =>
      (await _invokeMethod(method, arguments)) as T;
}

/// Build a database factory invoking the invoke method instead of going through
/// flutter services.
///
/// To use to enable running without flutter plugins (unit test)
///
/// [tag] is an optional debug
DatabaseFactory buildDatabaseFactory(
    {String? tag,
    required Future<dynamic> Function(String method, [Object? arguments])
        invokeMethod}) {
  final DatabaseFactory impl =
      _SqfliteDatabaseFactoryImpl(invokeMethod, tag: tag);
  return impl;
}
