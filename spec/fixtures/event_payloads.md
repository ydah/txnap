# Active Record transaction event spike

Captured on 2026-07-28 with `script/event_probe.rb`.

The probe covered Active Record 7.2.3 and 8.0.2 with SQLite and PostgreSQL
16. The object IDs and monotonic timestamps are intentionally omitted; they
change on every run.

## Conclusions used by the implementation

- `sql.active_record`, `start_transaction.active_record`, and
  `transaction.active_record` all include `payload[:connection]`.
- `start_transaction.active_record` exists in both 7.2.3 and 8.0.2. It fires
  just after the SQL BEGIN notification finishes, for real transactions and
  savepoints. The BEGIN SQL finish remains the more exact timeline origin.
- `transaction.active_record` starts just after BEGIN or SAVEPOINT completes
  and finishes after COMMIT, ROLLBACK, or RELEASE SAVEPOINT completes.
- A query-cache hit keeps its normal event name and sets
  `payload[:cached] == true`; it is not reliably named `CACHE`.
- The outer SQL notification which triggers lazy materialization starts before
  the nested BEGIN notification and finishes after it. The same nesting occurs
  when a query materializes a savepoint. Consumers must clamp an event start to
  the previous observed finish to avoid negative gaps and double-counted DB
  time.
- BEGIN payloads carry a transaction object. COMMIT payloads may omit it, so
  connection identity is the stable registry key.
- Savepoint lifecycle events use a different transaction object than the real
  transaction. The first `start_transaction.active_record` following a BEGIN
  binds the root lifecycle transaction to the connection trace, preventing a
  savepoint completion from finalizing the root trace.
- Runtime observations produced `commit`, `rollback`, and `restart` outcomes.
  Rails 7.2.3 and 8.0.2 source also emits `incomplete` when a materialized
  transaction is abandoned after a connection failure.

## SQL transaction forms

| Active Record | Adapter | BEGIN | COMMIT | ROLLBACK | Savepoint |
| --- | --- | --- | --- | --- | --- |
| 7.2.3 | SQLite | `begin transaction` | `commit transaction` | `rollback transaction` | `SAVEPOINT active_record_1` / `RELEASE SAVEPOINT active_record_1` |
| 8.0.2 | SQLite | `BEGIN immediate TRANSACTION` | `COMMIT TRANSACTION` | `ROLLBACK TRANSACTION` | `SAVEPOINT active_record_1` / `RELEASE SAVEPOINT active_record_1` |
| 7.2.3 | PostgreSQL | `BEGIN` | `COMMIT` | `ROLLBACK` | `SAVEPOINT active_record_1` / `RELEASE SAVEPOINT active_record_1` |
| 8.0.2 | PostgreSQL | `BEGIN` | `COMMIT` | `ROLLBACK` | `SAVEPOINT active_record_1` / `RELEASE SAVEPOINT active_record_1` |

## Representative event sequences

Real commit:

```text
sql.active_record                TRANSACTION BEGIN       connection, transaction
start_transaction.active_record                         connection, transaction
sql.active_record                INSERT ...              connection, transaction
sql.active_record                TRANSACTION COMMIT      connection
transaction.active_record        outcome=commit          connection, transaction
```

Savepoint inside a real transaction:

```text
sql.active_record                TRANSACTION SAVEPOINT   connection, nested transaction
start_transaction.active_record                         connection, nested transaction
sql.active_record                INSERT ...              connection, nested transaction
sql.active_record                TRANSACTION RELEASE     connection, root transaction
transaction.active_record        outcome=commit          connection, nested transaction
```

Restartable nested transaction rollback on SQLite 7.2:

```text
sql.active_record                begin transaction
start_transaction.active_record                         root lifecycle transaction
sql.active_record                INSERT ...
transaction.active_record        outcome=restart         root lifecycle transaction
sql.active_record                rollback transaction
sql.active_record                begin transaction
start_transaction.active_record                         root lifecycle transaction
sql.active_record                INSERT ...
sql.active_record                commit transaction
transaction.active_record        outcome=commit          root lifecycle transaction
```

Query cache:

```text
sql.active_record name="EventProbeRecord Load" cached=nil
sql.active_record name="EventProbeRecord Load" cached=true
```

## Reproduction

```bash
ruby script/event_probe.rb 7.2.3 sqlite3
ruby script/event_probe.rb 8.0.2 sqlite3
DATABASE_URL=postgresql://... ruby script/event_probe.rb 7.2.3 postgresql
DATABASE_URL=postgresql://... ruby script/event_probe.rb 8.0.2 postgresql
```
