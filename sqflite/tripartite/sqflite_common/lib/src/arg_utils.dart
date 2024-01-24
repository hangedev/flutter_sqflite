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

import 'dart:typed_data';

String? _argumentToStringTruncate(Object? argument) {
  if (argument == null) {
    return null;
  }
  var text = argument.toString();
  if (text.length > 50) {
    return '${text.substring(0, 50)}...';
  }
  return text;
}

/// Convert an sql argument to a printable string, truncating if necessary
String? argumentToString(Object? argument) {
  if (argument is Uint8List) {
    return 'Blob(${argument.length})';
  }
  return _argumentToStringTruncate(argument);
}

/// Convert sql arguments to a printable string, truncating if necessary
String argumentsToString(List<Object?> arguments) =>
    '[${arguments.map((e) => argumentToString(e)).join(', ')}]';

/// Sql command and arguments formatted for logs
String sqlArgumentsToString(String sql, List<Object?>? arguments) {
  return '$sql${(arguments?.isNotEmpty ?? false) ? ' ${argumentsToString(arguments!)}' : ''}';
}
