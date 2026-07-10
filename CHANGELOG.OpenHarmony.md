## 2.2.8-ohos-1.0.0-beta.2

* Fixed read/write divergence (issue #89): when opening a database with a sub-directory path, queries could not read inserted data because the read path rebuilt a StoreConfig without customDir, landing on a different physical db file than the write path. The read path now reuses the cached StoreConfig (with customDir) captured at open time.
* Fixed transaction misjudgment: `hasTransactionId` was derived from `!hasNullTransactionId()`, which misclassified non-transactional queries as in-transaction and routed them to the reuse branch, making the TaskPool query path dead code. Changed to `getTransactionId() != null`.
* Added regression demo `rw_split_test_page.dart` to guard read/write landing-point consistency.
