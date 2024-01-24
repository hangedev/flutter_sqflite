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
import 'package:sqflite_common/src/path_utils.dart';
import 'package:test/test.dart';

void main() {
  group('path_utils', () {
    test('inMemory', () {
      // Sounds obvious...
      expect(inMemoryDatabasePath, ':memory:');
      expect(isInMemoryDatabasePath('test.db'), isFalse);
      expect(isInMemoryDatabasePath(':memory:'), isTrue);
      expect(isInMemoryDatabasePath('file::memory:'), isTrue);
    });

    test('fileUri', () {
      expect(isFileUriDatabasePath('file::memory:'), isTrue);
      expect(isFileUriDatabasePath('filememory'), isFalse);
      expect(isFileUriDatabasePath('file:relative'), isTrue);
      expect(isFileUriDatabasePath('file:///abs'), isTrue);
    });
  });
}
