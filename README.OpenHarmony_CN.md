<p align="center">
  <h1 align="center">sqflite</h1>
</p>

本项目基于 [sqflite@2.4.2](https://pub.dev/packages/sqflite/versions/2.4.2) 开发。

## 简介

sqflite 是 SQLite 的 [Flutter 插件](https://flutter.io)，提供嵌入式 SQL 数据库能力。
* 支持事务和批量操作
* 打开时自动进行版本管理
* 提供插入/查询/更新/删除操作的辅助方法

## 下载安装

### 环境准备

构建前请先准备 OpenHarmony 开发环境：

1. 安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)（5.1.0.828 及以上，见[兼容性](#兼容性)），并启动一次以完成自带工具链（OH SDK、node、ohpm、hvigor、hdc）的下载与配置。
2. 从 [flutter_flutter](https://gitcode.com/CPF-Flutter/flutter_flutter) 仓库获取与框架版本匹配的 Flutter ohos 发行版（如 `oh-3.27.0-release` 或 `oh-3.35.7-release`，见 [TAG 版本对应表](#tag-版本对应表)），将其 `bin` 目录加入 `PATH`，并检查工具链：

```bash
export PATH=/path/to/flutter/bin:$PATH   # Windows：请添加到 PATH 环境变量
flutter doctor                           # ohos 相关检查项应全部通过
```

3. 连接 OpenHarmony 设备或启动模拟器，确认 `hdc list targets` 能识别到设备。
4. 添加本插件依赖（见下文），然后在工程目录执行构建与运行：

```bash
flutter pub get
flutter run                       # 在已连接设备上调试运行
flutter build hap --release       # 构建 OpenHarmony release HAP 包
```

### 添加依赖

在工程的 pubspec.yaml 中添加依赖:

```yaml
dependencies:
  sqflite:
    git:
      url: "https://gitcode.com/CPF-Flutter/flutter_sqflite.git"
      # ref: 请根据下方TAG版本对应表选择TAG
      ref: TAG # 根据下方表格选择不同框架适配的TAG版本  
      path: sqflite
```

执行命令：

```bash
flutter pub get
```

### TAG 版本对应表

| Flutter 框架版本 | TAG                | 分支               |
|--------------|--------------------|------------------|
| 3.7          | 2.2.8-ohos-1.0.0   | master           |
| 3.22         | 2.2.8-ohos-1.0.0   | master           |
| 3.27         | 2.4.2-ohos-1.0.1   | br_v2.4.2_ohos   |
| 3.35         | 2.4.2-ohos-1.0.1   | br_v2.4.2_ohos   |

### 升级迁移

从旧的 OpenHarmony 适配版本（如基于上游 sqflite 2.2.8 的 `2.2.8-ohos-1.0.0`）升级到当前 `2.4.2-ohos-1.0.1`（基于上游 sqflite 2.4.2）的步骤：

1. 修改 pubspec.yaml 中依赖的 `ref` 为目标 TAG，然后执行 `flutter pub get`：

```yaml
dependencies:
  sqflite:
    git:
      url: "https://gitcode.com/CPF-Flutter/flutter_sqflite.git"
      ref: 2.4.2-ohos-1.0.1
      path: sqflite
```

2. 框架版本需与 TAG 匹配：`2.4.2-ohos-1.0.1` 要求 Flutter 3.27 / 3.35 的 ohos 发行版（见上方 TAG 版本对应表及[兼容性](#兼容性)）；跨大版本升级框架时，还需同步升级配套的 DevEco Studio / OH SDK 工具链。
3. 升级前请查阅 [CHANGELOG.OpenHarmony.md](./CHANGELOG.OpenHarmony.md) 了解目标版本的行为变更。从 2.2.x 升级到 2.4.x 的主要 OHOS 变化：
   * 平台通道处理从 UI 线程迁移到后台 worker：大批量插入不再触发 `THREAD_BLOCK_6S` 应用冻结（issue #45、#65），大结果集查询不再受 SharedBlock 2MB 传输上限限制（issue #75）。
   * `VACUUM` 不再被误报为 `syntax error`：RDB 引擎会尝试真实执行，被拒绝时返回明确的“平台不支持（OpenHarmony RDB）”错误。若代码中依赖 `VACUUM`，请显式处理该错误。
   * REAL 列数值恢复无损读取：此前一处查询侧回归会把 `-1.1` 之类的 double 截断为 `-1`（读回 int），根因是 RDB 的 `getString()` 对 DOUBLE 列会丢精度。若曾为此做过二次解析的兼容处理，升级后可移除。另请注意：`databaseFactory.deleteDatabase` 会在原生侧关闭数据库，应用侧仍持有的 `Database` 句柄将失效（再使用时报 `database_closed`）——请丢弃旧句柄后重新打开，与 Android/iOS 行为一致。
4. Dart API 与上游 sqflite 保持兼容（2.2.x → 2.4.x 仅新增 `queryCursor` 等接口），除依赖 `ref` 外应用代码无需修改。升级后请重新运行数据库相关测试。

## 约束与限制

### 兼容性

在以下版本中已测试通过：

1. Flutter: 3.27.5-ohos-0.0.1; SDK: 5.0.5(17); IDE: DevEco Studio: 5.1.0.828; ROM: 5.1.0.130 SP8;
2. Flutter: 3.35.8-ohos-0.0.1; SDK: 5.0.5(17); IDE: DevEco Studio: 6.0.2.640; ROM: 6.0.0.328 SP22;

### 权限要求

> 以下权限中包含 `system_basic` 权限。默认应用等级为 `normal`，仅允许使用 `normal` 权限，可能在安装 HAP 时出现错误码 9568289。请参考 [安装 HAP 失败提示 9568289](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/bm-tool-V5#ZH-CN_TOPIC_0000001884757326__%E5%AE%89%E8%A3%85hap%E6%97%B6%E6%8F%90%E7%A4%BAcode9568289-error-install-failed-due-to-grant-request-permissions-failed)，将应用等级调整为 `system_basic`。

### 已知平台差异

1. **BigInt 参数以 TEXT 落库（SDK API ≥ 20）**：超出 `Number.MAX_SAFE_INTEGER` 的整数参数会以字符串绑定（规避 RDB bigint 绑定缺陷的折中方案），落库类型为 TEXT 而非 INTEGER，回读为 `string`/`BigInt` 而非 `number`。此类列不具备整数语义：`ORDER BY`、比较、聚合均按文本规则处理（如 `'10' < '9'`），且 TEXT 值与 INTEGER 值做 `=` 比较恒不相等。请将该列按文本处理，或读出后自行转换数值。


## 使用示例

```dart
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

Future<void> runDemo() async {
  final String dbPath = p.join(await getDatabasesPath(), 'demo.db');
  final Database db = await openDatabase(
    dbPath,
    version: 1,
    onCreate: (Database db, int version) async {
      await db.execute(
        'CREATE TABLE user(id INTEGER PRIMARY KEY, name TEXT, age INTEGER)',
      );
    },
  );

  final int id = await db.insert('user', <String, Object?>{
    'name': 'Alice',
    'age': 18,
  });

  final List<Map<String, Object?>> rows = await db.query(
    'user',
    where: 'id = ?',
    whereArgs: <Object?>[id],
  );

  print('rows: $rows'); // [{id: 1, name: Alice, age: 18}]
  await db.close();
}
```

更多示例请参考 [sqflite/example](./sqflite/example)。

## 使用说明

导入 `sqflite.dart`
```dart
import 'package:sqflite/sqflite.dart';
```

### 打开数据库

SQLite 数据库是文件系统中的一个通过路径标识的文件。如果是相对路径，则该路径相对于通过 `getDatabasesPath()` 获取的路径，这是 OpenHarmony 上的默认数据库目录。

```dart
var db = await openDatabase('my_db.db');
```

在打开文件时，有一个基本的迁移机制来处理模式变更。

许多应用程序使用一个数据库，并且可能不会需要关闭它（当应用程序终止时，它将被关闭）。如果想释放资源，可以关闭数据库。

```dart
await db.close();
```

* 查看 [更多关于开启数据库的信息](https://github.com/tekartik/sqflite/blob/master/sqflite/doc/opening_db.md)
* 完整 [迁移示例](https://github.com/tekartik/sqflite/blob/master/sqflite/doc/migration_example.md)

### 增删改查

以下示例中 `db` 为已打开的 Database 实例。

```dart
await db.insert('user', <String, Object?>{'name': 'Bob', 'age': 20});
final List<Map<String, Object?>> list = await db.query('user');
await db.update('user', <String, Object?>{'age': 21}, where: 'name = ?', whereArgs: <Object?>['Bob']);
await db.delete('user', where: 'name = ?', whereArgs: <Object?>['Bob']);
```

占位符参数建议统一使用 `?` + `whereArgs`/`arguments`，避免字符串拼接。
SQL 细节与常见陷阱详见 [sql.md](https://github.com/tekartik/sqflite/blob/master/sqflite/doc/sql.md)。

### 事务

```dart
await db.transaction((txn) async {
  await txn.insert('user', <String, Object?>{'name': 'Tom', 'age': 19});
  await txn.update(
    'user',
    <String, Object?>{'age': 20},
    where: 'name = ?',
    whereArgs: <Object?>['Tom'],
  );
});
```

事务中应使用 `txn` 访问数据库；在事务回调里直接使用 `db` 可能导致死锁。

### 批处理

```dart
final Batch batch = db.batch();
batch.insert('user', <String, Object?>{'name': 'Cathy', 'age': 22});
batch.update('user', <String, Object?>{'age': 23}, where: 'name = ?', whereArgs: <Object?>['Cathy']);
await batch.commit();
```

大批量写入且不关心每条结果时可使用：

```dart
await batch.commit(noResult: true);
```

需要失败后继续执行可使用：

```dart
await batch.commit(continueOnError: true);
```

### 读取结果说明

`query`/`rawQuery` 返回的结果列表及其元素 Map 为只读对象。
若需在内存中修改，请先拷贝：

```dart
final List<Map<String, Object?>> rows = await db.query('user');
final Map<String, Object?> mutable = Map<String, Object?>.from(rows.first);
mutable['age'] = 30;
```

### 支持的SQLite类型

目前尚不对数值进行有效性检查，因此请避免使用不支持的类型。[https://www.sqlite.org/datatype3.html](https://www.sqlite.org/datatype3.html)

`DateTime` 不支持SQLite类型，建议存储为 int（millisSinceEpoch）或字符串（iso8601）。

`bool` 不支持SQLite类型。请使用 0 和 1 作为值。

关于支持类型的更多信息 [请见此处](https://github.com/tekartik/sqflite/blob/master/sqflite/doc/supported_types.md).

| 名称 | 描述 | 类型 | OpenHarmony 平台支持 |
| --- | --- | --- | --- |
| INTEGER | 存储整数值 | int | yes |
| REAL | 存储浮点数值 | num/double | yes |
| TEXT | 存储文本值 | String | yes |
| BLOB | 存储二进制值 | Uint8List | yes |
| NULL | 空值 | null | yes |

## 接口说明

> “OpenHarmony 平台支持”列中，yes 表示支持，no 表示不支持，partially 表示部分支持。

### SqfliteOhos

`SqfliteOhos` 是 sqflite 平台接口的 OpenHarmony 实现类（`sqflite_ohos` 包，在 pubspec.yaml 中声明为 `dartPluginClass`）。它仅对外暴露一个入口；下文列出的完整 sqflite API 继承自 `SqflitePlatform` 基类与 `sqflite` 应用层包。

| 名称         | 类型     | 参数类型 | 返回值 | OpenHarmony 平台支持 | 描述                                                                                                                                           |
|------------|--------|------|-----|-----------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| registerWith | 静态方法 | -    | void | yes             | 插件注册入口，由 Flutter 引擎在插件加载时自动调用，将基于 MethodChannel 的数据库工厂注册为默认 `databaseFactory`（幂等：已有工厂时不会覆盖）。 |

应用通常无需自行调用。如需显式注册（例如自定义宿主或测试环境）：

```dart
import 'package:sqflite_ohos/sqflite_ohos.dart';

SqfliteOhos.registerWith();
```

### 顶层方法

| 名称                   | 类型 | 参数类型                                                              | 返回值                           | OpenHarmony 平台支持 | 描述 |
|----------------------| --- |-------------------------------------------------------------------|-------------------------------| --- | --- |
| openDatabase         | 方法 | String path, [OpenDatabaseOptions](#opendatabaseoptions)? options | Future<[Database](#database)> | yes | 打开指定路径的数据库，可配置打开选项 |
| openReadOnlyDatabase | 方法 | String path, {bool singleInstance = true}                         | Future<[Database](#database)> | yes | 以只读模式打开指定路径下的数据库 |
| getDatabasesPath     | 方法 | -                                                                 | Future\<String\>              | yes | 获取数据库默认存储路径 |
| deleteDatabase       | 方法 | String path                                                       | Future\<void\>                | yes | 删除指定路径的数据库 |
| databaseExists       | 方法 | String path                                                       | Future\<bool\>                | yes | 检查指定路径的数据库是否存在 |


### Batch

| 名称         | 类型 | 参数类型                                                     | 返回值                   | OpenHarmony 平台支持 | 描述 |
|------------| --- |----------------------------------------------------------|-----------------------|------------------| --- |
| get length | 方法 | -                                                        | int                   | yes              | 获取累计操作数量 |
| apply      | 方法 | {bool? noResult, bool? continueOnError}                  | Future<List<Object?>> | yes              | 执行并提交批量操作，建议优先使用 [commit] 来运行批次，而不是此方法 |
| commit     | 方法 | {bool? exclusive, bool? noResult, bool? continueOnError} | Future<List<Object?>> | yes              | 提交并执行批量操作，返回每项结果 |
| delete     | 方法 | String table, String? where, List<Object?>? whereArgs    | void                  | yes              | 在批处理中排队删除操作 |
| execute    | 方法 | String sql, List<Object?>? arguments                     | void                  | yes              | 在批处理中排队执行任意 SQL 语句 |
| insert     | 方法 | [InsertOption](#insertoption)                            | void                  | yes              | 在批处理中排队插入操作 |
| query      | 方法 | [QueryOption](#queryoption)                              | void                  | yes              | 在批处理中排队查询操作 |
| rawDelete  | 方法 | String sql, List<Object?>? arguments                     | void                  | yes              | 在批处理中排队原始删除语句 |
| rawInsert  | 方法 | String sql, List<Object?>? arguments                     | void                  | yes              | 在批处理中排队原始插入语句 |
| rawQuery   | 方法 | String sql, List<Object?>? arguments                     | void                  | yes              | 在批处理中排队原始查询语句 |
| rawUpdate  | 方法 | String sql, List<Object?>? arguments                     | void                  | yes              | 在批处理中排队原始更新语句 |
| update     | 方法 | [UpdateOption](#updateoption)                            | void                  | yes              | 在批处理中排队更新操作 |

### Database
继承自[DatabaseExecutor](#databaseexecutortransaction)，重复方法不再赘述

| 名称                 | 类型              | 参数类型                                                                                          | 返回值            | OpenHarmony 平台支持 | 描述 |
|--------------------|-----------------|-----------------------------------------------------------------------------------------------|----------------| --- | --- |
| path               | 属性              | -                                                                                             | String         | yes | 数据库路径 |
| isOpen             | 属性              | -                                                                                             | bool           | yes | 数据库是否打开；在调用 `close()` 后返回 false |
| close              | 方法              | -                                                                                             | Future\<void\> | yes | 关闭数据库 |
| transaction        | 方法              | Future\<T\> Function([Transaction](#databaseexecutortransaction) txn) action, bool? exclusive | Future\<T\>    | yes | 事务执行入口 |
| devInvokeMethod    | 方法 (Deprecated) | String method, [Object? arguments]                                                            | Future\<T\>    | yes | 开发/测试用方法；按源码为开发专用（已标记为 `@Deprecated('Dev only')`） |
| devInvokeSqlMethod | 方法 (Deprecated) | String method, String sql, [List<Object?>? arguments]                                         | Future\<T\>    | yes | 开发/测试用方法；执行 SQL 的开发专用方法（已标记为 `@Deprecated('Dev only')`） |

### DatabaseExecutor/Transaction

| 名称             | 类型 | 参数类型                                                  | 返回值                                 | OpenHarmony 平台支持 | 描述 |
|----------------| --- |-------------------------------------------------------|-------------------------------------| --- | --- |
| batch          | 方法 | -                                                     | Batch                               | yes | 获取批处理操作对象 |
| delete         | 方法 | String table, String? where, List<Object?>? whereArgs | Future\<int\>                       | yes | 删除符合条件的数据行 |
| execute        | 方法 | String sql, List<Object?>? arguments                  | Future\<void\>                      | yes | 执行 SQL 语句 |
| getVersion     | 方法 | /                                                     | Future\<int\>                       | yes | 获取数据库内部版本 |
| insert         | 方法 | [InsertOption](#insertoption)                         | Future\<int\>                       | yes | 插入 SQL 并返回最后插入的行ID |
| query          | 方法 | [QueryOption](#queryoption)                           | Future<List<Map<String, Object?>>>  | yes | 查询返回结果集列表 |
| queryCursor    | 方法 | [QueryCursor](#querycursoroption)                     | Future<[QueryCursor](#querycursor)> | yes | 查询返回游标对象 |
| rawDelete      | 方法 | String sql, List<Object?>? arguments                  | Future\<int\>                       | yes | 直接执行 SQL 删除符合条件的数据行 |
| rawInsert      | 方法 | String sql, List<Object?>? arguments                  | Future\<int\>                       | yes | 执行原始 SQL INSERT 查询并返回最后插入的行ID |
| rawQuery       | 方法 | String sql, List<Object?>? arguments                  | Future<List<Map<String, Object?>>>  | yes | 直接执行 SQL 查询返回结果集列表 |
| rawQueryCursor | 方法 | String sql, List<Object?>? arguments, int? bufferSize | Future<[QueryCursor](#querycursor)> | yes | 执行原始 SQL 查询返回游标对象 |
| rawUpdate      | 方法 | String sql, List<Object?>? arguments                  | Future\<int\>                       | yes | 直接执行更新 SQL 返回影响行数 |
| setVersion     | 方法 | int version                                           | Future\<void\>                      | yes | 设置数据库内部版本，用于内部打开助手和自动版本控制 |
| update         | 方法 | [UpdateOption](#updateoption)                         | Future\<int\>                       | yes | 执行更新 SQL 返回影响行数 |


### DatabaseFactory

| 名称               | 类型 | 参数类型                                                              | 返回值                  | OpenHarmony 平台支持 | 描述 |
|------------------| --- |-------------------------------------------------------------------|----------------------| --- | --- |
| openDatabase     | 方法 | String path, [OpenDatabaseOptions](#opendatabaseoptions)? options | Future\<Database\>   | yes | 打开指定路径的数据库，可配置打开选项 |
| getDatabasesPath | 方法 | -                                                                 | Future\<String\>     | yes | 获取数据库默认存储路径 |
| setDatabasesPath | 方法 | String path                                                       | Future\<void\>       | yes | 设置默认数据库存储路径 |
| deleteDatabase   | 方法 | String path                                                       | Future\<void\>       | yes | 删除指定路径的数据库 |
| databaseExists   | 方法 | String path                                                       | Future\<bool\>       | yes | 检查指定路径的数据库是否存在 |

### QueryCursor

| 名称        | 类型   | 参数类型 | 返回值                  | OpenHarmony 平台支持 | 描述 |
|-----------|------|---|----------------------| --- | --- |
| current   | 属性   | - | Map<String, Object?> | yes | 当前行数据 |
| close     | 方法   | - | Future\<void\>       | yes | 手动关闭游标 |
| moveNext  | 方法   | - | Future\<bool\>       | yes | 移动到下一行，返回 false 时游标自动关闭 |

### DatabaseException

`DatabaseException` 为抽象类（实现 `Exception`），是 sqflite 对原生 SQLite 错误的统一封装；OpenHarmony 平台使用具体实现 `SqfliteDatabaseException`。任何内部异常都会被包装为 `DatabaseException` 抛出。

| 名称                       | 类型 | 参数类型          | 返回值   | OpenHarmony 平台支持 | 描述 |
|--------------------------| --- |---------------|-------| --- | --- |
| result                   | 属性 | -             | Object? | yes | 平台相关的原生错误结果，内容依平台而定，供内部及诊断使用 |
| getResultCode            | 方法 | -             | int?  | yes | 获取 SQLite 结果码；Android/FFI 为扩展码，iOS 为普通码，需同时处理 |
| isNoSuchTableError       | 方法 | [String? table] | bool  | yes | 是否为"no such table"错误，可指定表名匹配 |
| isDuplicateColumnError   | 方法 | [String? column] | bool  | yes | 是否为"duplicate column name"错误，可指定列名匹配 |
| isSyntaxError            | 方法 | -             | bool  | yes | 是否为 SQL 语法错误 |
| isOpenFailedError        | 方法 | -             | bool  | yes | 是否为数据库打开失败错误（含 `open_failed`） |
| isDatabaseClosedError    | 方法 | -             | bool  | yes | 是否为数据库已关闭错误 |
| isReadOnlyError          | 方法 | -             | bool  | yes | 是否为只读错误（含 `readonly`） |
| isUniqueConstraintError  | 方法 | [String? field] | bool  | yes | 是否为 UNIQUE 约束冲突，可指定字段匹配 |
| isNotNullConstraintError | 方法 | [String? field] | bool  | yes | 是否为 NOT NULL 约束冲突，可指定字段匹配 |

### OpenDatabaseOptions

| 名称             | 参数类型                                | 必填  | OpenHarmony平台支持 | 描述 |
|----------------|-------------------------------------|-----| --- | --- |
| version        | int?                                   | 否   | yes | 数据库版本，必须为大于 0 的 32 位整数 |
| onConfigure    | [OnDatabaseConfigureFn](#回调类型)?     | 否   | yes | 数据库配置回调，参数：`Database db` |
| onCreate       | [OnDatabaseCreateFn](#回调类型)?        | 否   | yes | 数据库创建回调，参数：`Database db, int version` |
| onUpgrade      | [OnDatabaseVersionChangeFn](#回调类型)? | 否   | yes | 数据库版本升级回调，参数：`Database db, int oldVersion, int newVersion` |
| onDowngrade    | [OnDatabaseVersionChangeFn](#回调类型)? | 否   | yes | 数据库版本降级回调，参数：`Database db, int oldVersion, int newVersion` |
| onOpen         | [OnDatabaseOpenFn](#回调类型)?          | 否   | yes | 数据库打开完成回调，参数：`Database db` |
| readOnly       | bool?                                 | 否   | yes | 是否以只读模式打开数据库；默认 `false` |
| singleInstance | bool?                                 | 否   | yes | 是否启用单例数据库实例；默认 `true` |

### InsertOption

| 名称                | 参数类型                      | 必填  | OpenHarmony平台支持 | 描述 |
|-------------------|---------------------------|-----| --- | --- |
| table             | String                    | 是   | yes | 要插入的表名 |
| values            | Map<String, Object?>      | 是   | yes | 要插入的列和值映射 |
| nullColumnHack    | String?                   | 否   | yes | 可选，用于在 values 为空时指定列名以插入 NULL |
| conflictAlgorithm | [ConflictAlgorithm](#conflictalgorithm)? | 否   | yes | 冲突解决策略（原名 ConflictAlgorithm） |

### QueryOption

| 名称        | 参数类型           | 必填 | OpenHarmony平台支持 | 描述 |
|-----------|----------------| --- | --- | --- |
| table     | String         | 是 | yes | 要查询的表名 |
| distinct  | bool?          | 否 | yes | 是否去重 |
| columns   | List<String>?  | 否 | yes | 返回的列名列表，缺省为所有列 |
| where     | String?        | 否 | yes | WHERE 子句（不含 WHERE 关键字） |
| whereArgs | List<Object?>? | 否 | yes | WHERE 子句中占位符对应的参数列表 |
| groupBy   | String?        | 否 | yes | GROUP BY 子句（不含关键字） |
| having    | String?        | 否 | yes | HAVING 子句（不含关键字） |
| orderBy   | String?        | 否 | yes | ORDER BY 子句（不含关键字） |
| limit     | int?           | 否 | yes | 最大返回行数 |
| offset    | int?           | 否 | yes | 返回偏移量 |

### QueryCursorOption

| 名称         | 参数类型           | 必填 | OpenHarmony平台支持 | 描述 |
|------------|----------------| --- | --- | --- |
| table      | String         | 是 | yes | 要查询的表名 |
| distinct   | bool?          | 否 | yes | 是否去重 |
| columns    | List<String>?  | 否 | yes | 返回的列名列表 |
| where      | String?        | 否 | yes | WHERE 子句（不含关键字） |
| whereArgs  | List<Object?>? | 否 | yes | WHERE 子句中占位符对应的参数列表 |
| groupBy    | String?        | 否 | yes | GROUP BY 子句 |
| having     | String?        | 否 | yes | HAVING 子句 |
| orderBy    | String?        | 否 | yes | ORDER BY 子句 |
| limit      | int?           | 否 | yes | 最大返回行数 |
| offset     | int?           | 否 | yes | 返回偏移量 |
| bufferSize | int?           | 否 | yes | 游标缓冲区大小，影响底层批量读取行为 |
    
### UpdateOption

| 名称                | 参数类型                      | 必填 | OpenHarmony平台支持 | 描述 |
|-------------------|---------------------------| --- | --- | --- |
| table             | String                    | 是 | yes | 要更新的表名 |
| values            | Map<String, Object?>      | 是 | yes | 列和值映射 |
| where             | String?                   | 否 | yes | WHERE 子句（不含关键字） |
| whereArgs         | List<Object?>?            | 否 | yes | WHERE 子句中占位符对应的参数列表 |
| conflictAlgorithm | [ConflictAlgorithm](#conflictalgorithm)? | 否 | yes | 冲突解决策略 |

### ConflictAlgorithm

| 名称         | 参数类型 | OpenHarmony平台支持 | 描述 |
|------------| --- | --- | --- |
| rollback   | 枚举值 | yes | 冲突时回滚事务并终止 |
| abort      | 枚举值 | yes | 冲突时终止当前语句 |
| fail       | 枚举值 | yes | 冲突时终止语句但保留之前变更 |
| ignore     | 枚举值 | yes | 冲突时忽略当前行并继续 |
| replace    | 枚举值 | yes | 冲突时替换已有行 |

### 回调类型

| 回调                        | 参数类型                                                                                 | OpenHarmony平台支持 | 描述 |
|---------------------------|--------------------------------------------------------------------------------------| --- | --- |
| OnDatabaseConfigureFn     | FutureOr\<void\> Function([Database](#database) db)                                  | yes | 参数：`Database db`；返回：`FutureOr<void>`；数据库打开后、其它回调之前触发 |
| OnDatabaseCreateFn        | FutureOr\<void\> Function([Database](#database) db, int version)                     | yes | 参数：`Database db, int version`；返回：`FutureOr<void>`；数据库创建时触发 |
| OnDatabaseVersionChangeFn | FutureOr\<void\> Function([Database](#database) db, int oldVersion, int newVersion); | yes | 参数：`Database db, int oldVersion, int newVersion`；返回：`FutureOr<void>`；数据库升级或降级时触发 |
| OnDatabaseOpenFn          | FutureOr\<void\> Function([Database](#database) db)                                  | yes | 参数：`Database db`；返回：`FutureOr<void>`；数据库打开完成后触发 |

## 常见问题

### 是否支持 OpenHarmony

支持。OpenHarmony 适配版本在本仓库维护，具体可用版本见“兼容性”章节。

### sqflite_common 依赖地址如何配置

OpenHarmony 适配版本依赖 GitCode 仓库地址。若项目已使用 pub.dev 的 sqflite，请切换为本文档的 git 依赖方式。

## 遗留问题

- [ ] OpenHarmony 查询返回数据量特别大时，受 taskPool 限制，可能导致序列化失败，无法正常返回数据。参见 [issue #75](https://gitcode.com/CPF-Flutter/flutter_sqflite/issues/75)。

## 目录结构
```
sqflite
├── packages/                   # 扩展包与工具示例（如控制台测试应用）
├── packages_web/               # Web 相关实现与测试
├── sqflite/                    # Flutter sqflite 插件主体
│   └── android/ios             # Android/iOS 平台原生实现
│   └── doc/                    # 插件使用文档与开发说明
│   └── example/                # 示例工程
│   └── lib/                    # Dart API 与核心实现
│   └── ohos/                   # OpenHarmony 平台适配实现
├── sqflite_common/             # 跨平台通用实现
├── sqflite_common_ffi/         # FFI 相关实现与测试
├── sqflite_common_test/        # 公共测试用例
├── sqflite_support/            # 支撑库与辅助测试代码
├── sqflite_test_app/           # 插件集成测试应用
├── README.OpenHarmony_CN.md   # 中文文档
├── README.OpenHarmony.md      # 英文文档
```

## 贡献代码

使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/CPF-Flutter/flutter_sqflite/issues) ，当然，也非常欢迎发 [PR](https://gitcode.com/CPF-Flutter/flutter_sqflite/pulls) 共建。

## 开源协议

本项目基于[BSD 2-Clause License](https://gitcode.com/CPF-Flutter/flutter_sqflite/blob/master/LICENSE) ，请自由地享受和参与开源。
