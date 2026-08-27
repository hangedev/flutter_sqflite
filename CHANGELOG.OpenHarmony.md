## 2.4.2-ohos-1.0.1 - 2026.8

### Added

* Added a `VACUUM` regression test in `sqflite_common_test` asserting the statement is never misreported as a `syntax error` on OHOS and that table data remains intact after the attempt.

### Fixed

* OHOS: zero-row query results now always include the `columns` and `rows` keys, matching the upstream Android/iOS contract.
* OHOS: transaction and `ATTACH`/`DETACH` failures now report a proper `sqlite_error` with the failing sql and arguments, instead of a generic error.
* OHOS: unconsumed query cursors are now closed when their database is closed, deleted, or the plugin is disposed — previously the ResultSets leaked. A 64-cursor cap evicts the oldest cursor.
* OHOS: `onDetachedFromEngine` now closes all databases and cursors and clears plugin state, instead of leaking them until process exit.
* OHOS: invalid arguments (empty paths, malformed batch operations, missing `ATTACH`/`DETACH` parameters) now return precise errors instead of a generic failure.
* OHOS: fixed premature null replies on async error paths; a failed `ROLLBACK` is now reported as an error instead of silently succeeding.
* OHOS: hardened error paths around reply routing and database close, preventing unhandled rejections during engine teardown; removed dead code (`debugMode` argument, `SqlCommand.toValue`, `OperationRunnable`).
* OHOS: `VACUUM` is no longer misreported as a `syntax error`. VACUUM statements are now intercepted by a new `VacuumHandler` in the SQL handler chain and guarded in the `execute`/`rawQuery` paths, attempting a real `executeSql` first and returning an explicit `VACUUM is not supported on this platform (OpenHarmony RDB)` error when the RDB engine rejects it.

## 2.4.2-ohos-1.0.0

### Added

* OHOS: sqflite platform-channel handling moved off the platform main thread onto a self-managed background `ThreadWorker`, fixing main-thread blocking on heavy database operations (issues #45, #65). Method-call decode and execution now run on the worker — equivalent to Android's `makeBackgroundTaskQueue` + single-thread worker pool — so large inserts (500k/1M rows) no longer trigger `THREAD_BLOCK_6S` appfreeze on low-end devices. Replies are routed by a monotonic sequence id with a single-install `onmessage` handler, sidestepping the cross-call reply mix-up of the engine `BackgroundMethodChannel` `setSingleThreadMode`.
* OHOS: large result-set queries (decode included) now run off the main thread, bypassing the SharedBlock 2MB transfer limit (issue #75). A 200k-row (~195MB) one-shot `rawQuery` is verified to return successfully.
* Stress test demo `stress_test_page.dart` to guard against large-insert regressions (frame timing + crash monitoring for chunked and single-batch inserts).
* Bench test demo `bench_test_page.dart` to measure single-operation end-to-end latency (CREATE/INSERT/UPDATE/QUERY) for before/after comparison of the worker migration.
* Big-query test demo `big_query_test_page.dart` to verify large result-set retrieval (one-shot `rawQuery` vs paged `rawQueryCursor`).

### Changed

* OHOS: `Database.insert` / `update` / `query` / `queryCursorNext` changed to `async` returning `Promise<void>`. The worker's serial queue awaits these so the reply envelope is captured before posting back; otherwise a `null` reply is returned prematurely (`MissingPluginException` on the Dart side). `queryCursorNext`'s catch branch also `await`s `handleException` since it is async (14800032 path).
* OHOS: `SqflitePlugin` rewritten from `MethodChannel.setMethodCallHandler` to a raw `BinaryMessenger.setMessageHandler` + self-managed `ThreadWorker`, with seq-routed replies and full worker lifecycle management (terminate-on-reattach, null-safe reply on worker unavailability and on detach, pending-flush on detach).
* OHOS: `build-profile.json5` declares `SqfliteWorker.ets` under `sourceOption.workers`.

### Fixed

* OHOS: `THREAD_BLOCK_6S` appfreeze / crash on large batch inserts (issues #45, #65). Root cause was the main thread synchronously decoding a giant single-batch platform message via `StandardMethodCodec.decodeMethodCall` (>6s for a 500k/1M-op batch) before the handler even ran. Decoding and execution now happen on the worker thread.
* OHOS: large result-set query failure / `SharedBlock is full` (issue #75). Query decode moved off the main thread onto the worker (`SendableStandardMethodCodec`), sidestepping the SharedBlock 2MB cap.

## 2.4.2-ohos-1.0.0-beta.2
* fix: `openDatabase` - incorrect single instance recovery flag, error handling when database fails to open, added validation scenarios. [#99](https://gitcode.com/CPF-Flutter/flutter_sqflite/pull/99)
* fix: `debug` returns complete debug information. [#100](https://gitcode.com/CPF-Flutter/flutter_sqflite/pull/100)
* fix: [Code Quality Improvement] OhosConstant file naming does not match. [#102](https://gitcode.com/CPF-Flutter/flutter_sqflite/pull/102)
* fix: [Code Quality Improvement] Add JSDoc-style comments. [#103](https://gitcode.com/CPF-Flutter/flutter_sqflite/pull/103)
* docs: Documentation improvements (br_v2.4.2_ohos). [#105](https://gitcode.com/CPF-Flutter/flutter_sqflite/pull/105)
* fix: Fix dependency error, unable to find sqflite_ohos issue. [#109](https://gitcode.com/CPF-Flutter/flutter_sqflite/pull/109)

