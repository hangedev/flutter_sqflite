// Copyright (c) 2025 Huawei Device Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_HW file.
// Based on Camera.java originally written by
// Copyright 2013 The Flutter Authors.

import 'package:process_run/shell.dart';

Future<void> main(List<String> arguments) async {
  var shell = Shell(workingDirectory: 'ohos');
  await shell.run('''
 # Java unit test
./gradlew test

# With a emulator running
./gradlew connectedAndroidTest
 ''');
}
