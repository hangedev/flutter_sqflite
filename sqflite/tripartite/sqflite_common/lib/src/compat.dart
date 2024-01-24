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

import 'factory_mixin.dart';

///
/// internal options.
///
/// Used internally.
///
/// deprecated since 1.1.1
///
@Deprecated('Dev only')
class SqfliteOptions {
  /// deprecated
  SqfliteOptions({this.logLevel});

  // true =<0.7.0
  /// deprecated
  @Deprecated('remove usage')
  bool? queryAsMapList;

  /// deprecated
  int? androidThreadPriority;

  /// deprecated
  int? androidThreadCount;

  /// deprecated
  int? logLevel;

  /// deprecated
  Map<String, Object?> toMap() {
    final map = <String, Object?>{};
    if (queryAsMapList != null) {
      map['queryAsMapList'] = queryAsMapList;
    }
    if (androidThreadPriority != null) {
      map['androidThreadPriority'] = androidThreadPriority;
    }
    if (androidThreadCount != null) {
      map['androidThreadCount'] = androidThreadCount;
    }
    if (logLevel != null) {
      map[paramLogLevel] = logLevel;
    }
    return map;
  }

  /// deprecated
  void fromMap(Map<String, Object?> map) {
    final dynamic queryAsMapList = map['queryAsMapList'];
    if (queryAsMapList is bool) {
      this.queryAsMapList = queryAsMapList;
    }
    final dynamic androidThreadPriority = map['androidThreadPriority'];
    if (androidThreadPriority is int) {
      this.androidThreadPriority = androidThreadPriority;
    }
    final dynamic androidThreadCount = map['androidThreadCount'];
    if (androidThreadCount is int) {
      this.androidThreadCount = androidThreadCount;
    }
    final dynamic logLevel = map[paramLogLevel];
    if (logLevel is int) {
      this.logLevel = logLevel;
    }
  }
}
