# frozen_string_literal: true

RSpec.describe Txnap::Notifier do
  let(:configuration) { Txnap::Configuration.new }
  let(:output) { StringIO.new }
  let(:logger) { Logger.new(output) }
  let(:notifier) { described_class.new(configuration: configuration, logger: logger) }
  let(:gap) do
    Txnap::Gap.new(
      duration: 0.2,
      after: Txnap::EventMetadata.new(sql: "UPDATE users", name: "SQL", call_site: "app.rb:1"),
      before: Txnap::EventMetadata.new(sql: "COMMIT", name: "TRANSACTION", call_site: nil),
      locks: []
    )
  end
  let(:report) do
    Txnap::Report.new(
      outcome: :commit,
      transaction_duration: 0.3,
      database_time: 0.02,
      gaps: [gap],
      sql_count: 1
    )
  end

  before do
    configuration.gap_threshold = 0.2
  end

  it "reports at the inclusive threshold and leaves payload values unrounded" do
    payloads = collect_idle_gap_payloads { expect(notifier.call(report)).to be(true) }

    expect(payloads.first[:longest_gap_ms]).to eq(200.0)
    expect(output.string).to include("Transaction held for 300 ms")
  end

  it "honors the minimum transaction duration" do
    configuration.min_transaction_duration = 0.31

    expect(notifier.call(report)).to be(false)
  end

  it "does not report below the gap threshold" do
    configuration.gap_threshold = 0.201

    expect(notifier.call(report)).to be(false)
  end

  it "honors only_with_locks" do
    configuration.only_with_locks = true

    expect(notifier.call(report)).to be(false)
  end

  it "supports report-aware ignore predicates" do
    configuration.ignore_if = ->(candidate) { candidate.outcome == :commit }

    expect(notifier.call(report)).to be(false)
  end

  it "supports zero-arity ignore predicates" do
    configuration.ignore_if = -> { true }

    expect(notifier.call(report)).to be(false)
  end

  it "raises after a committed transaction with an explicit warning" do
    configuration.mode = :raise

    expect { notifier.call(report) }
      .to raise_error(Txnap::IdleGapDetected, /already been committed/)
  end
end
