## 2.4.2_1-ohos-1.0.0 - 2026.9

### Added

* OHOS deltas preserved on top of upstream `2.4.2+1`: the `ohos` platform entry and `sqflite_ohos` path dependency in the `sqflite` pubspec, the OHOS example test pages (`bench`, `big_query`, `debug_info`, `inspection_verify`, `multi_db_transaction`, `open_database_behavior`, `open_error_verify`, `stress`) and their registration in the example menu, and the OHOS-specific test-case changes in `sqflite_common_test/lib/exp_test.dart`.
* Ported upstream fixes accumulated since the old snapshot base, notably: WAL-mode insert behavior fixes with `SQLiteStatement` for insert/update/delete (sqflite_android `2.4.2+3`), sqlite3 wasm shared-worker overrides (sqflite_common_ffi_web, upstream #1199), and the new `sqflite_example_android_wal` upstream example.

### Changed

* Synced every package shared with upstream to the true upstream `sqflite 2.4.2+1` content: `sqflite 2.4.2+1`, `sqflite_common 2.5.6+1`, `sqflite_common_ffi 2.4.0+3`, `sqflite_platform_interface 2.4.2`, `sqflite_android 2.4.2+3`, `sqflite_darwin 2.4.2`, and the support packages (`sqflite_common_ffi_web 1.1.1`, `sqflite_common_ffi_async 0.2.0` line based on `sqlite_async ^0.14.0`, `sqflite_test_app`, `sqflite_common_test`, `sqflite_example_common`). The previous `2.4.2-ohos-1.x` releases were built from an early-2025 upstream snapshot that only carried the `2.4.2` version string; the fork is now content-aligned with upstream `2.4.2+1`.
* Dart SDK constraints of the synced packages follow upstream (`^3.10.0`). Verified against the Flutter 3.41 (Dart 3.11.5) and Flutter 3.44 (Dart 3.12.2) ohos toolchains.
* Adopted the upstream dart 3.7 "tall" code style for all files taken from upstream; OHOS-added code is kept functionally identical and formatted to match.
* `sqflite/example` now takes `sqflite_example_common` from the in-repo path (`packages_flutter/sqflite_example_common`) instead of upstream's floating `git` dependency. The previous OHOS releases pinned the git ref to the `dart3a` branch; upstream `2.4.2+1` floats against the repository HEAD, whose current `sqflite_example_common` requires `sqflite_common >=2.5.9` (Dart >= 3.12) and therefore cannot resolve under the Flutter 3.41 toolchain (Dart 3.11.5). The path dependency keeps the example resolvable on both the 3.41 and 3.44 ohos toolchains and works offline.
* Files upstream removed were dropped accordingly (windows ffi setup restructure, legacy android example gradle files, `LocaleUtils.java`, `io_test.dart` renamed to `io_tests_io.dart`/`io_tests_stub.dart`).
* `sqflite_ohos` and its example pubspec constraints follow the synced release: Dart sdk ^3.10.0, flutter >=3.38.0, sqflite_common >=2.5.6, sqflite_platform_interface >=2.4.0; the plugin code itself is unchanged.
* OHOS: the worker now receives the application context once in an init message when it is created, instead of attaching a `common.Context` copy to every task message. This removes one structured clone per platform message and the associated shared-heap churn under heavy batch load; on device, the runtime `SharedFullGC` abort observed under sustained stress no longer reproduces (GC logs show shared-heap remembered-set processing dropping to zero in steady state).

### Fixed

* Example (experimental page): preserved the OHOS fix where the page no longer queries through a stale pre-delete database handle ("Count record" after "Delete database" on the multiple-databases page keeps working).
* Preserved all OHOS behavioral fixes from `2.4.2-ohos-1.0.0`/`2.4.2-ohos-1.0.1` (worker-thread channel, large-batch insert, large result sets, REAL precision, VACUUM handling) — the `sqflite_ohos` plugin code was not touched by the sync.

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
* OHOS: REAL/double values are read back losslessly again. The RDB `ResultSet.getString()` used for integer detection loses precision on DOUBLE columns (per the OHOS docs), so an integral-looking string such as `-1` (for a stored `-1.1`) was parsed with `parseInt` and truncated the value to an int. Values within the safe integer range now fall back to `ResultSet.getValue()`, which returns the value by its actual stored type (restores the br_v2.4.1_ohos fix 5e0c9f5 that was lost when merging master).
* Example (Multiple databases page): "Count record" no longer fails silently after "Delete database". The page kept querying through its stale pre-delete database handle whose id the native side had already cleaned up, so the query failed with `database_closed` and no result was shown. The page now releases the old handle after deleting; the next count re-opens the recreated database (returning 0 records).

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

