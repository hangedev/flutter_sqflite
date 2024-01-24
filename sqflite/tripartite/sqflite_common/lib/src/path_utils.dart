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

const _fileUriPrefix = 'file:';

/// True if a database path is in memory
bool isInMemoryDatabasePath(String path) {
  if (path == inMemoryDatabasePath) {
    return true;
  }
  if (isFileUriDatabasePath(path)) {
    if (path.substring(_fileUriPrefix.length) == inMemoryDatabasePath) {
      return true;
    }
  }
  return false;
}

/// True if a database path is a file uri
bool isFileUriDatabasePath(String path) {
  return path.startsWith(_fileUriPrefix);
}
