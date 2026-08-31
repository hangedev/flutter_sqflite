import 'dart:async';

import 'package:flutter/material.dart';
import 'bench_test_page.dart';
import 'big_query_test_page.dart';
import 'package:sqflite_example/batch_test_page.dart';
import 'package:sqflite_example/deprecated_test_page.dart';
import 'package:sqflite_example/exception_test_page.dart';
import 'package:sqflite_example/exp_test_page.dart';
import 'package:sqflite_example/manual_test_page.dart';
import 'package:sqflite_example/src/dev_utils.dart';

import 'model/main_item.dart';
import 'new_features_test_page.dart';
import 'open_test_page.dart';
import 'raw_test_page.dart';
import 'resource_test_page.dart';
import 'rw_split_test_page.dart';
import 'slow_test_page.dart';
import 'stress_test_page.dart';
import 'src/main_item_widget.dart';
import 'transaction_repro_page.dart';
import 'todo_test_page.dart';
import 'type_test_page.dart';

void main() {
  mainExampleApp();
}

/// Example app main entry point, exported for external application
///
/// might move to a different shared package.
void mainExampleApp() {
  WidgetsFlutterBinding.ensureInitialized();
  // debugAutoStartRouteName = testOpenRoute;
  runApp(const SqfliteExampleApp());
}

/// Sqflite test app
class SqfliteExampleApp extends StatefulWidget {
  /// test app.
  const SqfliteExampleApp({Key? key}) : super(key: key);
  // This widget is the root of your application.

  @override
  // ignore: library_private_types_in_public_api
  _SqfliteExampleAppState createState() => _SqfliteExampleAppState();
}

/// Simple test page.
const String testRawRoute = '/test/simple';

/// Open test page.
const String testOpenRoute = '/test/open';

/// Slow test page.
const String testSlowRoute = '/test/slow';

/// Type test page.
const String testTypeRoute = '/test/type';

/// Batch test page.
const String testBatchRoute = '/test/batch';

/// `todo` example test page.
const String testTodoRoute = '/test/todo';

/// Exception test page.
const String testExceptionRoute = '/test/exception';

/// Manual test page.
const String testManualRoute = '/test/manual';

/// Experiment test page.
const String testExpRoute = '/test/exp';

/// Deprecated test page.
const String testDeprecatedRoute = '/test/deprecated';

/// New features test page.
const String testNewFeaturesRoute = '/test/features';

/// 读写分叉 bug 复现页 (issue #89)。
const String testRwSplitRoute = '/test/rwsplit';

/// Stress test page (大数据插入压力测试).
const String testStressRoute = '/test/stress';

/// Bench test page (单次操作耗时基准, 验证 6c42dd2).
const String testBenchRoute = '/test/bench';

/// Big query test page (issue #75 大结果集查询).
const String testBigQueryRoute = '/test/bigquery';

/// Transaction repro test page (issue 14800021).
const String testTransactionReproRoute = '/test/transaction_repro';

/// Resource & stability regression test page (游标/事务/错误信封/临时文件).
const String testResourceRoute = '/test/resource';

class _SqfliteExampleAppState extends State<SqfliteExampleApp> {
  var routes = <String, WidgetBuilder>{
    '/test': (BuildContext context) => MyHomePage(),
    testRawRoute: (BuildContext context) => RawTestPage(),
    testOpenRoute: (BuildContext context) => OpenTestPage(),
    testSlowRoute: (BuildContext context) => SlowTestPage(),
    testTodoRoute: (BuildContext context) => TodoTestPage(),
    testTypeRoute: (BuildContext context) => TypeTestPage(),
    testManualRoute: (BuildContext context) => const ManualTestPage(),
    testBatchRoute: (BuildContext context) => BatchTestPage(),
    testExceptionRoute: (BuildContext context) => ExceptionTestPage(),
    testExpRoute: (BuildContext context) => ExpTestPage(),
    testDeprecatedRoute: (BuildContext context) => DeprecatedTestPage(),
    testNewFeaturesRoute: (BuildContext context) => NewFeaturesTestPage(),
    testRwSplitRoute: (BuildContext context) => RwSplitTestPage(),
    testStressRoute: (BuildContext context) => const StressTestPage(),
    testBenchRoute: (BuildContext context) => const BenchTestPage(),
    testBigQueryRoute: (BuildContext context) => const BigQueryTestPage(),
    testTransactionReproRoute: (BuildContext context) =>
        const TransactionReproPage(),
    testResourceRoute: (BuildContext context) => ResourceTestPage(),
  };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Sqflite Demo',
        theme: ThemeData(
          // This is the theme of your application.
          //
          // Try running your application with 'flutter run'. You'll see
          // the application has a blue toolbar. Then, without quitting
          // the app, try changing the primarySwatch below to Colors.green
          // and then invoke 'hot reload' (press 'r' in the console where
          // you ran 'flutter run', or press Run > Hot Reload App in IntelliJ).
          // Notice that the counter didn't reset back to zero -- the application
          // is not restarted.
          primarySwatch: Colors.blue,
        ),
        home: MyHomePage(title: 'Sqflite Demo Home Page'),
        routes: routes);
  }
}

/// App home menu page.
class MyHomePage extends StatefulWidget {
  /// App home menu page.
  MyHomePage({Key? key, this.title}) : super(key: key) {
    _items.add(MainItem('Raw tests', 'Raw SQLite operations', route: testRawRoute));
    _items.add(MainItem('Open tests', 'Open onCreate/onUpgrade/onDowngrade', route: testOpenRoute));
    _items.add(MainItem('Type tests', 'Test value types', route: testTypeRoute));
    _items.add(MainItem('Batch tests', 'Test batch operations', route: testBatchRoute));
    _items.add(MainItem('Slow tests', 'Lengthy operations', route: testSlowRoute));
    _items.add(MainItem('Todo database example', 'Simple Todo-like database usage example', route: testTodoRoute));
    _items.add(MainItem('Exp tests', 'Experimental and various tests', route: testExpRoute));
    _items.add(MainItem('Exception tests', 'Tests that trigger exceptions', route: testExceptionRoute));
    _items.add(MainItem('Manual tests', 'Tests that requires manual execution', route: testManualRoute));
    _items.add(MainItem('Deprecated test', 'Keeping some old tests for deprecated functionalities', route: testDeprecatedRoute));
    _items.add(MainItem('NewFeatures test', 'Testing of all new features', route: testNewFeaturesRoute));
    _items.add(MainItem('R/W split bug (issue #89)', '读写分叉：能写不能读复现', route: testRwSplitRoute));
    _items.add(MainItem('大数据插入压力测试', '大数据插入 GC/掉帧/崩溃复现 (issue #65)', route: testStressRoute));
    _items.add(MainItem('单次操作耗时基准', '建表/插入/修改/查询单次端到端耗时统计 (验证 6c42dd2)', route: testBenchRoute));
    _items.add(MainItem('大结果集查询 (#75)', '大数据量查询序列化失败复现 + 游标分页对照', route: testBigQueryRoute));
    _items.add(MainItem('Transaction Repro (issue 14800021)', 'Reproduce BEGIN TRANSACTION error 14800021 on OHOS', route: testTransactionReproRoute));
    _items.add(MainItem('稳定性与资源管理回归', '游标关库清理/LRU 上限/事务中断/失败信封/畸形消息/临时文件清理验证', route: testResourceRoute));

    // Uncomment to view all logs
    //Sqflite.devSetDebugModeOn(true);
  }

  final List<MainItem> _items = [];

  /// Page title.
  final String? title;

  @override
  // ignore: library_private_types_in_public_api
  _MyHomePageState createState() => _MyHomePageState();
}

String? _debugAutoStartRouteName;

/// (debug) set the route to start with.
String? get debugAutoStartRouteName => _debugAutoStartRouteName;

/// Deprecated to avoid calls
@Deprecated('Deb only')
set debugAutoStartRouteName(String? routeName) => _debugAutoStartRouteName = routeName;

class _MyHomePageState extends State<MyHomePage> {
  int get _itemCount => widget._items.length;

  @override
  void initState() {
    super.initState();

    Future<void>.delayed(Duration.zero).then((_) async {
      if (mounted) {
        // Use it to auto start a test page
        if (debugAutoStartRouteName != null) {
          // only once

          // await Navigator.of(context).pushNamed(testExpRoute);
          // await Navigator.of(context).pushNamed(testRawRoute);
          final future = Navigator.of(context).pushNamed(debugAutoStartRouteName!);
          // ignore: deprecated_member_use_from_same_package
          debugAutoStartRouteName = null;
          await future;
          // await Navigator.of(context).pushNamed(testExceptionRoute);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Center(child: Text('Sqflite demo', textAlign: TextAlign.center)),
        ),
        body: ListView.builder(itemBuilder: _itemBuilder, itemCount: _itemCount));
  }

  //new Center(child: new Text('Running on: $_platformVersion\n')),

  Widget _itemBuilder(BuildContext context, int index) {
    return MainItemWidget(widget._items[index], (MainItem item) {
      Navigator.of(context).pushNamed(item.route!);
    });
  }
}
