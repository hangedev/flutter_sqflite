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
import 'package:sqflite_common/src/constant.dart';
import 'package:sqflite_common/src/factory_mixin.dart';
import 'package:sqflite_common/src/mixin/factory.dart';
import 'package:test/test.dart';

import 'src_mixin_test.dart';

void main() {
  group('mixin_factory', () {
    test('public', () {
      // ignore: unnecessary_statements
      buildDatabaseFactory;
      // ignore: unnecessary_statements
      SqfliteInvokeHandler;
    });
    test('buildDatabaseFactory', () async {
      final methods = <String>[];
      final factory = buildDatabaseFactory(
          tag: 'mock',
          invokeMethod: (String method, [Object? arguments]) async {
            final dynamic result = mockResult(method, arguments);
            methods.add(method);
            return result;
          });
      expect((factory as SqfliteDatabaseFactoryMixin).tag, 'mock');
      // ignore: unnecessary_type_check
      expect(factory is SqfliteInvokeHandler, isTrue);
      await factory.openDatabase(inMemoryDatabasePath);
      expect(methods, <String>['openDatabase']);
    });
  });
}
