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

import 'package:sqflite_common/src/utils.dart';
import 'package:sqflite_common/utils/utils.dart';
import 'package:test/test.dart';

void main() {
  group('sqflite', () {
    test('firstIntValue', () {
      expect(
          firstIntValue(<Map<String, Object?>>[
            <String, Object?>{'test': 1}
          ]),
          1);
      expect(
          firstIntValue(<Map<String, Object?>>[
            <String, Object?>{'test': 1},
            <String, Object?>{'test': 1}
          ]),
          1);
      expect(
          firstIntValue(<Map<String, Object?>>[
            <String, Object?>{'test': null}
          ]),
          null);
      expect(
          firstIntValue(<Map<String, Object?>>[<String, Object?>{}]), isNull);
      expect(firstIntValue(<Map<String, Object?>>[]), isNull);
      expect(
          firstIntValue(<Map<String, Object?>>[<String, Object?>{}]), isNull);
    });

    test('hex', () {
      expect(
          hex(<int>[
            0,
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            12,
            13,
            14,
            15,
            16,
            17,
            255
          ]),
          '000102030405060708090A0B0C0D0E0F1011FF');
      expect(hex(<int>[]), '');
      expect(hex(<int>[32]), '20');

      try {
        hex(<int>[-1]);
        fail('should fail');
      } on FormatException catch (_) {}

      try {
        hex(<int>[256]);
        fail('should fail');
      } on FormatException catch (_) {}
    });

    test('chunk', () {
      expect(listChunk([], null), isEmpty);
      expect(listChunk([1], null), [
        [1]
      ]);
      expect(listChunk([1], 0), [
        [1]
      ]);
      expect(listChunk([1, 2], 0), [
        [1, 2]
      ]);
      expect(listChunk([1, 2], 2), [
        [1, 2]
      ]);
      expect(listChunk([1, 2], 3), [
        [1, 2]
      ]);
      expect(listChunk([1, 2], 1), [
        [1],
        [2]
      ]);
      expect(listChunk([1, 2, 3], 2), [
        [1, 2],
        [3]
      ]);
    });
  });
}
