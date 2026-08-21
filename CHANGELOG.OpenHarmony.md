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
