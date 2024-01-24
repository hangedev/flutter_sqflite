# Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Method call protocol

This protocol is used in a similar way for:
- sqflite plugin
- sqflite_common_ffi isolate communication
- sqflite_common_ffi_web web worker communication

## Methods

### openDatabase

```
in:
    path: database path (String)
    readOnly: <true|false>
    singleInstance: <true|false>

out:
    id: database id (int)
    clientId:
    recoveredInTransaction: <true|false>
```

### query

`SELECT` method

```
in:
    sql: select query (String)
    arguments: [<param1>, <param2>...] (binding parameters)
    cursorPageSize: <count> new in 2022-10-17 if non null the cursor is kept

out:
    columns: [<name1>, <name2>...]
    rows: [
            [row1 value1, row2 value2, ...]
            [row2 value1, row2 value2, ...]
            ...
          ] 
    cursorId: <id> optional cursor id for queryNext, null if end is reached
```

### queryCursorNext

Added in 2022-10-17 to support pages queries

```
in:
    cursorId: <id>
    cancel: <true|false> true if the query should be cancelled

out:
    columns: [<name1>, <name2>...]
    rows: [
            [row1 value1, row2 value2, ...]
            [row2 value1, row2 value2, ...]
            ...
          ] 
    cursorId: <id> optional cursor id for queryNext, null if end is reached
```

### Transaction

#### Transaction v1

Up to 2022-10-21

```
in:
    BEGIN TRANSACTION:
    inTransaction: true
```

```
in:
    <any commmand in transaction>
```

```
in:
    END TRANSACTION:
    inTransaction: false
```

#### Transaction v2

As of 2022-10-21 a new transaction mechanism is added, being compatible with the existing

```
in:
    BEGIN TRANSACTION:
    'inTransaction': true
    'transactionId': null // This tells
out:
    // This tells that the implementation supports the new transaction model
    transactionId: <nnn>
```

```
in:
    <any commmand in transaction>
```

```
in:
    END TRANSACTION:
    transactionId: <nnn>
    inTransaction: false
```