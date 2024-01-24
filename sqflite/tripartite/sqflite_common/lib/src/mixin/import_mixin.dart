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

///
/// Export for implementation: sqflite, sqflite_common_ffi
///
export 'package:sqflite_common/src/compat.dart'
    show
        SqfliteOptions; // ignore: deprecated_member_use, deprecated_member_use_from_same_package
/// Explicit list of needed private import
export 'package:sqflite_common/src/database.dart' // ignore: implementation_imports
    show
        SqfliteDatabaseOpenHelper,
        SqfliteDatabase;
export 'package:sqflite_common/src/database_mixin.dart' // ignore: implementation_imports
    show
        SqfliteDatabaseMixin,
        SqfliteDatabaseBase;

//
// Exception
//
export 'package:sqflite_common/src/exception.dart'
    show SqfliteDatabaseException;
export 'package:sqflite_common/src/factory.dart' show SqfliteDatabaseFactory;

//
// Factory mixin
//
export 'package:sqflite_common/src/factory_mixin.dart'
    show SqfliteDatabaseFactoryBase, SqfliteDatabaseFactoryMixin;

//
// Constant
//
export 'package:sqflite_common/src/mixin/constant.dart'
    show
        methodOpenDatabase,
        methodCloseDatabase,
        methodOptions,
        methodInsert,
        methodQuery,
        methodUpdate,
        methodExecute,
        methodBatch,
        sqliteErrorCode;
export 'package:sqflite_common/src/mixin/factory.dart'
    show buildDatabaseFactory, SqfliteInvokeHandler;
