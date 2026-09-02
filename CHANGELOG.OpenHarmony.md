## 2.2.8-ohos-1.0.1 - 2026.8

### Changed

* OHOS: open databases are now keyed by full path instead of file name, so same-named databases in different directories are no longer wrongly reused/overwritten.

### Fixed

* OHOS: multiple instances of the same path (`singleInstance: false`) no longer overwrite each other: loaded stores are keyed by database id instead of path, so closing one instance no longer closes another instance's store. `deleteDatabase` closes every open instance of that path before deleting the file.
* OHOS: RDB generic error 14800000 is no longer blanket-converted to `success(null)`: only `noResult` batch operations keep the historical tolerance (now with a warning log); every other failure is reported as `sqlite_error`.
* OHOS: SQL with placeholders executed with an empty argument list (`rawQuery('... WHERE name = ?', [])`, `rawDelete`, `rawInsert`) no longer fails with 14800000: empty-argument queries take the no-args `querySql` overload, and unbound-placeholder writes fall back to `querySql` reporting 0 affected rows (NULL-comparison semantics, matching Android).
* OHOS: a `ROLLBACK` failure is no longer silently swallowed: it is logged and propagated as `sqlite_error` (aligned with the `COMMIT` handler), and a `ResultSet.close()` failure in the `query` finally block no longer masks the reply. A failed `ROLLBACK` still clears the local transaction bookkeeping (depth and tables-created-in-transaction set) so `isInTransaction()` and empty-result checks do not stay stale; the depth is clamped at zero, while a failed `COMMIT` still keeps it (the transaction may still be open, aligned with Android).
* OHOS: `openDatabase` failures now match Android semantics: unreachable paths reply `sqlite_error` / `open_failed <path>`; an existing corrupted file (14800011) keeps the lazy-failure behaviour (open succeeds with a placeholder id, next operation reports `file is not a database`), the placeholder is registered in the single-instance table so re-opens recover the same id, and closing it now properly removes the entry instead of leaking it in the bookkeeping maps.
* OHOS: `openDatabase` now honours the `singleInstance` argument (default true, forced false for in-memory databases): an already-open instance is reused and reported with `recovered: true` / `recoveredInTransaction`, matching Android.
* OHOS: `queryCursorNext` now reuses the page size captured at query time (previously every page after the first returned all remaining rows), and end-of-data detection covers the after-last/empty state, removing one extra empty round-trip when the row count is a multiple of the page size.
* OHOS: `insert` with `ON CONFLICT IGNORE` now returns `null` instead of `0` when no row was inserted (matching Android).
* OHOS: `deleteDatabase` now closes and removes open instances of that path before deleting the file, and no longer reports an error to Dart on deletion failure (aligned with Android).
* OHOS: `debugMode` and `options` now actually apply the requested log level (`on` -> verbose, `off` -> none), and `debug` returns the real path, actual `singleInstance` flag and `logLevel` instead of a hardcoded file name.
* OHOS: `execute` operations inside a `batch` now track transaction depth and tables created within the transaction, keeping the shared transaction state consistent when BEGIN/COMMIT statements run through a batch.
* OHOS: paged query cursors are tracked per database id and closed when that database is closed or deleted; an abandoned cursor no longer leaks its ResultSet handles, and a query that fails after saving its cursor closes it. `queryCursorNext` validates the database first and reports `database_closed <id>` instead of a misleading `Cursor not found`. Closing a cursor always removes its cache entry even when `ResultSet.close()` throws (previously the over-limit eviction loop could spin forever on it, hanging the worker queue).
* OHOS: the worker cleans up orphaned `temp_memory_*.db` files (in-memory backing files left over after a hot restart or re-attach) on its first message, matching only the exact `temp_memory_<digits>.db` naming so user databases like `temp_memory_custom.db` are never deleted. Deletion uses `fs.unlink` (main file plus `-wal`/`-shm`) instead of `deleteRdbStore`, so a backing file still held open by another engine survives the cleanup while a true orphan is reclaimed just the same.
* OHOS: query error paths (`doQuery`, the `PRAGMA user_version` shortcut and empty-result-set detection) now await the async error-mapping helper before replying, so a failed query can no longer resolve with `null` on the Dart side instead of the mapped error envelope.
* OHOS: if the worker thread terminates with an uncaught error, all in-flight method-channel replies are completed with `null` immediately instead of hanging until the engine detaches.
* OHOS: `closeDatabase`/`deleteDatabase` now cancel the 5-second close-timeout timer once the close race settles, instead of leaving one zombie timer per close.
* OHOS: closing a database now resets the whole shared transaction state (depth, current transaction id and tables-created set), but only when the closed database is the one holding the active transaction, so closing or deleting an unrelated database no longer wipes its in-flight transaction. `BEGIN`/`COMMIT` interception also replies with a `sqlite_error` envelope instead of a generic `error` code.
* OHOS: malformed method-call arguments are now rejected with `bad_param` instead of crashing or misfiring: batch `operations` missing/not an array, `ATTACH`/`DETACH` placeholders without bind arguments, missing/ill-typed `path`/`id` on open/close/databaseExists/deleteDatabase, and a missing `sql` field in `execute`.
* iOS: removed one extra blank line in `SqflitePlugin.m` introduced by commit `a756891` (the OHOS fork import), restoring the iOS/macOS plugin sources byte-identical and fixing the `sqflite_macos_impl_test` consistency check.

## 2.2.8-ohos-1.0.0

* Publish the official release

## 2.2.8-ohos-1.0.0-beta.2

### Added

* OHOS: sqflite platform-channel handling moved off the platform main thread onto a self-managed background `ThreadWorker`, fixing main-thread blocking on heavy database operations (issues #45, #65). Method-call decode and execution now run on the worker — equivalent to Android's `makeBackgroundTaskQueue` + single-thread worker pool — so large inserts (500k/1M rows) no longer trigger `THREAD_BLOCK_6S` appfreeze on low-end devices. Replies are routed by a monotonic sequence id with a single-install `onmessage` handler, sidestepping the cross-call reply mix-up of the engine `BackgroundMethodChannel` `setSingleThreadMode`.
* OHOS: diagnostic logs for transaction control commands (BEGIN/COMMIT/ROLLBACK) to help troubleshoot transaction-related issues.
* Stress test demo `stress_test_page.dart` to guard against large-insert regressions (frame timing + crash monitoring for chunked and single-batch inserts).
* Regression demo `rw_split_test_page.dart` to guard read/write landing-point consistency.

### Changed

* OHOS: hardened the worker queue (`running` reset in `finally`; every message is guaranteed a reply) and the plugin lifecycle (terminate any previous worker on re-attach; null-safe reply on worker unavailability and on detach).
* OHOS: `hasTransactionId` was derived from `!hasNullTransactionId()`, which misclassified non-transactional queries as in-transaction and routed them to the reuse branch, making the TaskPool query path dead code. Changed to `getTransactionId() != null`.

### Removed

* OHOS: obsolete per-operation TaskPool path (`TaskDatabase`) and its `dbIdConfigMap` / `getStoreConfigByDbId` helpers; the worker uses a single RdbStore connection, so the issue #89 read/write landing-point fix holds without the TaskPool config cache.

### Fixed

* OHOS: `DatabaseException (error code 14800021)` thrown when executing `BEGIN TRANSACTION`, `COMMIT TRANSACTION` and `ROLLBACK TRANSACTION`. These statements, commonly issued by ORMs such as drift, are now intercepted and routed to the native `beginTransaction()` / `commit()` / `rollBack()` APIs instead of falling through to `execute()`, which the OHOS relationalStore does not support for raw transaction control SQL.
* Read/write divergence (issue #89): when opening a database with a sub-directory path, queries could not read inserted data because the read path rebuilt a StoreConfig without customDir, landing on a different physical db file than the write path. The read path now reuses the cached StoreConfig (with customDir) captured at open time.
