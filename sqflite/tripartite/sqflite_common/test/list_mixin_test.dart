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

import 'dart:collection';

import 'package:test/test.dart';

class MyList1 extends Object with ListMixin<Map<String, Object?>> {
  MyList1.from(this._list);

  final List<dynamic> _list;

  @override
  Map<String, Object?> operator [](int index) {
    final value = _list[index] as Map<dynamic, dynamic>;
    return value.cast<String, Object?>();
  }

  @override
  void operator []=(int index, Map<String, Object?> value) {
    throw 'read-only';
  }

  @override
  set length(int newLength) {
    throw 'read-only';
  }

  @override
  int get length => _list.length;
}

class MyList2 extends ListBase<Map<String, Object?>> {
  MyList2.from(this._list);

  final List<dynamic> _list;

  @override
  Map<String, Object?> operator [](int index) {
    final value = _list[index] as Map<dynamic, dynamic>;
    return value.cast<String, Object?>();
  }

  @override
  void operator []=(int index, Map<String, Object?> value) {
    throw 'read-only';
  }

  @override
  set length(int newLength) {
    throw 'read-only';
  }

  @override
  int get length => _list.length;
}

void main() {
  group('mixin', () {
    // This fails on beta 1, should work now
    test('ListMixin', () {
      final raw = <dynamic>[
        <dynamic, dynamic>{'col': 1}
      ];
      final rows = MyList1.from(raw);
      expect(rows, raw);
    });

    test('ListBase', () {
      final raw = <dynamic>[
        <dynamic, dynamic>{'col': 1}
      ];
      final rows = MyList2.from(raw);
      expect(rows, raw);
    });
  });
}
