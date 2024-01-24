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

import 'package:meta/meta.dart';

/// An command object representing the invocation of a named method.
@immutable
class SqfliteMethodCall {
  /// Creates a [MethodCall] representing the invocation of [method] with the
  /// specified [arguments].
  const SqfliteMethodCall(this.method, [this.arguments]);

  /// Build from a map.
  factory SqfliteMethodCall.fromMap(Map map) {
    return SqfliteMethodCall(map['method'] as String, map['arguments']);
  }

  /// The name of the method to be called.
  final String method;

  /// The arguments for the method.
  ///
  /// Must be a valid value for the [MethodCodec] used.
  final Object? arguments;

  /// To map
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'method': method,
      if (arguments != null) 'arguments': arguments
    };
  }

  @override
  String toString() => '$runtimeType($method, $arguments)';
}
