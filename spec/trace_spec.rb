# frozen_string_literal: true

RSpec.describe Txnap::Trace do
  subject(:trace) { described_class.new(start: 0.0, finish: 0.01, sql: "BEGIN") }

  it "aggregates nested notification intervals without double-counting" do
    trace.record_sql(
      start: 0.0,
      finish: 0.03,
      sql: "INSERT INTO users VALUES (1)",
      name: "User Create",
      call_site: "app.rb:1"
    )
    trace.record_sql(
      start: 0.23,
      finish: 0.24,
      sql: "SELECT * FROM users",
      name: "User Load",
      call_site: "app.rb:2"
    )
    trace.record_terminal(start: 0.34, finish: 0.35, sql: "COMMIT")

    report = trace.to_report(:commit)

    expect(report.transaction_duration).to be_within(0.0001).of(0.33)
    expect(report.database_time).to be_within(0.0001).of(0.05)
    expect(report.longest_gap.duration).to be_within(0.0001).of(0.20)
    expect(report.sql_count).to eq(2)
  end

  it "does not include time before BEGIN finishes" do
    trace.record_sql(
      start: -1.0,
      finish: 0.02,
      sql: "SELECT 1",
      name: "SQL",
      call_site: nil
    )
    trace.record_terminal(start: 0.02, finish: 0.03, sql: "COMMIT")

    expect(trace.to_report(:commit).longest_gap.duration).to eq(0.0)
  end

  it "snapshots only locks held before a gap" do
    lock = Txnap::LockCandidate.new(
      statement: "UPDATE",
      table: "users",
      kind: "row lock",
      call_site: "app.rb:1"
    )
    trace.record_sql(
      start: 0.01,
      finish: 0.02,
      sql: "UPDATE users SET name = 'A'",
      name: "User Update",
      call_site: "app.rb:1",
      lock_candidate: lock
    )
    trace.record_terminal(start: 0.22, finish: 0.23, sql: "COMMIT")

    expect(trace.to_report(:commit).locks).to contain_exactly(lock)
  end

  it "keeps a fixed number of top gaps" do
    5.times do |index|
      start = 0.02 + (index * 0.10)
      trace.record_sql(
        start: start,
        finish: start + 0.01,
        sql: "SELECT #{index}",
        name: "SQL",
        call_site: nil
      )
    end
    trace.record_terminal(start: 0.60, finish: 0.61, sql: "COMMIT")

    expect(trace.to_report(:commit).gaps.length).to eq(3)
  end
end
