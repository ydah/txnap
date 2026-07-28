# Txnap

Catch transactions napping with locks held.

`txnap` detects time spent away from the database while an
Active Record transaction is materially open.

A transaction can take one second even when its SQL totals only 30 ms. The
remaining 970 ms may be Ruby computation, file I/O, an external request, a
`sleep`, or Fiber scheduling while row locks are still held. Slow-query tools
do not expose that gap.

This gem measures from the completion of the real `BEGIN` through the start of
`COMMIT` or `ROLLBACK`, then reports the longest interval between database
events. It never changes transaction behavior.

## Installation

The gem has not been published yet. Until the first release, install it from
Git:

```ruby
gem "txnap", github: "ydah/txnap"
```

It supports Active Record 7.2 and 8.0. Rails applications install the
notification subscribers automatically.

## Usage

Configure the detector in an initializer:

```ruby
Txnap.configure do |config|
  config.mode = :log
  config.gap_threshold = 0.1
  config.min_transaction_duration = 0.0
  config.only_with_locks = false
  config.capture_call_sites = :always
  config.ignore_if = nil
end
```

Non-Rails Active Record applications must also call:

```ruby
Txnap.install!
```

A report looks like:

```text
Txnap::IdleGapDetected

Transaction held for 1,024 ms (BEGIN → COMMIT)
Database time: 31 ms
Longest non-database gap: 742 ms

Gap occurred between:
  after:  UPDATE "users" SET ... (app/services/checkout.rb:88)
  before: INSERT INTO "audit_logs" ... (app/services/checkout.rb:131)

Locks possibly held during the gap:
  UPDATE users (row lock)  app/services/checkout.rb:88

Move slow non-database work (I/O, rendering, external calls,
heavy computation) outside the transaction.
```

### Configuration

| Setting | Default | Description |
| --- | --- | --- |
| `mode` | `:log` | `:log` writes a warning. `:raise` is intended for tests. |
| `gap_threshold` | `0.1` | Inclusive longest-gap threshold in seconds. |
| `min_transaction_duration` | `0.0` | Ignore shorter materialized transactions. |
| `only_with_locks` | `false` | Report only when the longest gap follows likely lock acquisition. |
| `capture_call_sites` | `:always` | `:always`, `:sampled`, or `:off`. |
| `ignore_if` | `nil` | A callable receiving the report; truthy suppresses notification. |
| `logger` | Rails logger | Optional logger override. |

`:sampled` calls `caller_locations` only when an SQL event creates a new
longest-gap candidate. This lowers overhead, but one side of a reported gap can
have no call site. `:off` retains SQL text without application locations.

`:raise` runs from the `transaction.active_record` finish notification. A
commit has already succeeded by this point, so the exception cannot roll it
back. The exception message states this explicitly.

### Suppression and filtering

Suppress a known-safe block in the current isolated execution context:

```ruby
Txnap.suppress do
  ApplicationRecord.transaction { rebuild_local_cache }
end
```

Or filter completed reports:

```ruby
Txnap.configure do |config|
  config.ignore_if = ->(report) {
    report.transaction_duration < 0.5 && report.locks.empty?
  }
end
```

### Notifications and APM integration

Every accepted report emits `idle_gap.txnap`. Numeric durations
are unrounded milliseconds; rounding happens only in log formatting.

```ruby
ActiveSupport::Notifications.subscribe("idle_gap.txnap") do |event|
  payload = event.payload

  MyAPM.record_custom_event(
    "ActiveRecordIdleGap",
    transaction_ms: payload[:transaction_duration_ms],
    database_ms: payload[:database_time_ms],
    longest_gap_ms: payload[:longest_gap_ms],
    sql_count: payload[:sql_count]
  )
end
```

The payload also includes the gap's preceding and following SQL metadata, the
three longest gaps, likely locks, and the transaction outcome.

## What is and is not measured

- The origin is the finish of the actual `BEGIN` SQL notification.
- The endpoint is the start of `COMMIT` or `ROLLBACK`.
- Transaction control SQL contributes to database time.
- Schema notifications and query-cache hits are ignored as timeline
  boundaries. Modern Rails marks cache hits with `payload[:cached] == true`;
  their event name is not reliably `CACHE`.
- Savepoints join the real transaction timeline and do not create reports of
  their own.
- Memory is bounded: each trace retains the previous event, the three longest
  gaps, and at most 20 distinct lock candidates rather than all SQL.

Active Record lazily materializes transactions. Therefore this code does not
report the sleep:

```ruby
ApplicationRecord.transaction do
  sleep 0.3
  User.create!
end
```

The database has no open transaction and holds no locks until `User.create!`
causes `BEGIN`. Excluding that pre-BEGIN time is intentional.

Lock reporting is heuristic. It recognizes `INSERT`, `UPDATE`, `DELETE`,
locking `SELECT`, `LOCK TABLE`, and common PostgreSQL/MySQL advisory-lock
functions. It does not parse primary keys or prove that a lock is still held.

Fiber or async scheduler waits count as gaps when the checked-out connection
remains in a transaction. That is intentional: another Fiber may run, but the
database session can still retain locks.

## Related safeguards

[Isolator](https://github.com/palkan/isolator) detects specific side effects
such as HTTP calls or job enqueueing inside transactions. This gem detects
elapsed time regardless of the work type, including CPU-only work and unknown
I/O. The tools are complementary.

For PostgreSQL, also configure
`idle_in_transaction_session_timeout` as a server-side last line of defense.
This gem provides application context and early visibility; it is not a
replacement for the database timeout.

## Compatibility

| Ruby | Active Record 7.2 | Active Record 8.0 |
| --- | --- | --- |
| 3.2 | supported | supported |
| 3.3 | supported | supported |
| 3.4 | supported | supported |
| 4.0 | supported | supported |

Rails 7.1 and earlier are not supported because the implementation relies on
the 7.2 transaction lifecycle notifications. SQLite is used for the main test
suite and PostgreSQL 16 for adapter and concurrent-connection smoke tests.

## Performance

The benchmark measures `transaction { one SQL }` before subscriptions, with
no-op notification subscribers, and with detection enabled:

```bash
bundle exec ruby benchmark/transaction.rb
DATABASE_URL=postgresql://... bundle exec ruby benchmark/transaction.rb
```

On Ruby 4.0.0, Active Record 8.0.5, and a local PostgreSQL 16 Docker container,
with call-site capture disabled, a five-second run measured 1,473 i/s without
the detector and 1,417 i/s with it: **3.78% overhead**. A SQLite in-memory
microbenchmark is dominated by notification and Ruby bookkeeping and is not
representative of networked database latency.

Re-run the benchmark on the same database topology and Ruby version used by
the application. Enable `:sampled` or `:off` call-site capture in
latency-sensitive production environments.

## Development

Install dependencies and run the default RSpec plus Standard Ruby checks:

```bash
bundle install
bundle exec rake
```

Run both supported Active Record families:

```bash
bundle exec appraisal rails_7_2 rspec
bundle exec appraisal rails_8_0 rspec
```

Use `TIME_SCALE=1.5` to relax timing windows on slower CI workers. Event payload
spike results and reproduction commands are in
[`spec/fixtures/event_payloads.md`](spec/fixtures/event_payloads.md).

## License

The gem is available under the [MIT License](LICENSE.txt).
