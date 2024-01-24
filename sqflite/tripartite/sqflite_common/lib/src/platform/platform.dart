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

export 'platform_io.dart' if (dart.library.js) 'platform_web.dart';

/// IO/web support
abstract class Platform {
  /// True if web
  bool get isWeb => false;

  /// True if IO windows
  bool get isWindows => false;

  /// True if IO ios
  bool get isIOS => false;

  /// True if IO Android
  bool get isAndroid => false;

  /// True if IO Linux
  bool get isLinux => false;

  /// True if IO MacOS
  bool get isMacOS => false;
}
