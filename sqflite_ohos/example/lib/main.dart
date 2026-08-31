// Copyright (c) 2025 Huawei Device Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_HW file.
// Based on Camera.java originally written by
// Copyright 2013 The Flutter Authors.

import 'package:sqflite_example_common/main.dart';
import 'package:sqflite_ohos/sqflite_ohos.dart';

Future<void> main() async {
  // Explicitly register the ohos implementation as the default database
  // factory. The engine also auto-registers the plugin on ohos, so calling
  // it here again is safe (the registration is idempotent) and keeps the
  // demo usable in hosts that do not auto-register the plugin.
  SqfliteOhos.registerWith();
  // supportsCompatMode = true;
  mainExampleApp();
}
