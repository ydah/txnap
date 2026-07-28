# frozen_string_literal: true

RSpec.describe "Active Record integration" do
  let(:delay) { 0.04 * time_scale }

  before do
    TxnapRecord.delete_all
    TxnapRecord.create!(name: "existing")
  end

  it "detects a non-database gap between SQL statements" do
    payloads = collect_idle_gap_payloads do
      ActiveRecord::Base.transaction do
        TxnapRecord.create!(name: "before gap")
        sleep delay
        TxnapRecord.count
      end
    end

    expect(payloads.length).to eq(1)
    expect(payloads.first[:longest_gap_ms]).to be_within(20 * time_scale).of(delay * 1000)
    expect(payloads.first[:database_time_ms]).to be_positive
  end

  it "excludes Ruby time before lazy materialization" do
    payloads = collect_idle_gap_payloads do
      ActiveRecord::Base.transaction do
        sleep delay
        TxnapRecord.create!(name: "after pre-BEGIN sleep")
      end
    end

    expect(payloads).to be_empty
  end

  it "detects a gap immediately after BEGIN" do
    payloads = collect_idle_gap_payloads do
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.materialize_transactions
        sleep delay
        TxnapRecord.count
      end
    end

    expect(payloads.length).to eq(1)
    expect(payloads.first[:gap][:after][:sql]).to match(/\ABEGIN/i)
  end

  it "detects a gap immediately before COMMIT" do
    payloads = collect_idle_gap_payloads do
      ActiveRecord::Base.transaction do
        TxnapRecord.create!(name: "before commit gap")
        sleep delay
      end
    end

    expect(payloads.length).to eq(1)
    expect(payloads.first[:gap][:before][:sql]).to match(/\ACOMMIT/i)
  end

  it "does not let query-cache hits split a gap" do
    payloads = collect_idle_gap_payloads do
      ActiveRecord::Base.cache do
        ActiveRecord::Base.transaction do
          TxnapRecord.first
          sleep(delay / 2)
          TxnapRecord.first
          sleep(delay / 2)
        end
      end
    end

    expect(payloads.length).to eq(1)
    expect(payloads.first[:longest_gap_ms]).to be > delay * 900
  end

  it "ignores an unmaterialized empty transaction" do
    payloads = collect_idle_gap_payloads do
      ActiveRecord::Base.transaction { "no SQL" }
    end

    expect(payloads).to be_empty
    expect(Txnap.registry.size).to eq(0)
  end

  it "does not finalize the root trace when a savepoint commits" do
    payloads = collect_idle_gap_payloads do
      ActiveRecord::Base.transaction do
        TxnapRecord.create!(name: "root")
        ActiveRecord::Base.transaction(requires_new: true) do
          TxnapRecord.create!(name: "nested")
        end
        sleep delay
      end
    end

    expect(payloads.length).to eq(1)
    expect(Txnap.registry.size).to eq(0)
  end

  it "finalizes and reports a rolled-back real transaction" do
    payloads = collect_idle_gap_payloads do
      ActiveRecord::Base.transaction do
        TxnapRecord.create!(name: "rolled back")
        sleep delay
        raise ActiveRecord::Rollback
      end
    end

    expect(payloads.first[:outcome]).to eq(:rollback)
    expect(TxnapRecord.exists?(name: "rolled back")).to be(false)
    expect(Txnap.registry.size).to eq(0)
  end

  it "cleans up restart outcomes before the replacement BEGIN" do
    collect_idle_gap_payloads do
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.transaction(requires_new: true) do
          TxnapRecord.create!(name: "restarted")
          raise ActiveRecord::Rollback
        end
        TxnapRecord.create!(name: "after restart")
      end
    end

    expect(Txnap.registry.size).to eq(0)
    expect(TxnapRecord.exists?(name: "after restart")).to be(true)
  end

  it "warns and prunes an injected stale trace on the next BEGIN" do
    output = StringIO.new
    Txnap.configure { |settings| settings.logger = Logger.new(output) }
    connection = ActiveRecord::Base.connection
    stale_trace = Txnap::Trace.new(start: 0.0, finish: 0.01, sql: "BEGIN")
    Txnap.registry.start(connection, stale_trace)

    ActiveRecord::Base.transaction do
      TxnapRecord.create!(name: "replacement")
    end

    expect(output.string).to include("discarded a stale trace")
    expect(Txnap.registry.size).to eq(0)
  end

  it "filters lock-free transactions when only_with_locks is enabled" do
    Txnap.configure { |settings| settings.only_with_locks = true }

    payloads = collect_idle_gap_payloads do
      ActiveRecord::Base.transaction do
        TxnapRecord.first
        sleep delay
      end
    end

    expect(payloads).to be_empty
  end

  it "reports lock candidates held during the longest gap" do
    Txnap.configure { |settings| settings.only_with_locks = true }

    payloads = collect_idle_gap_payloads do
      ActiveRecord::Base.transaction do
        TxnapRecord.where(name: "existing").update_all(name: "updated")
        sleep delay
      end
    end

    expect(payloads.first[:locks].first).to include(
      statement: "UPDATE",
      table: "txnap_records",
      kind: "row lock"
    )
  end

  it "supports scoped suppression" do
    payloads = collect_idle_gap_payloads do
      Txnap.suppress do
        ActiveRecord::Base.transaction do
          TxnapRecord.create!(name: "suppressed")
          sleep delay
        end
      end
    end

    expect(payloads).to be_empty
  end

  it "raises only after the commit has persisted" do
    Txnap.configure { |settings| settings.mode = :raise }

    expect do
      ActiveRecord::Base.transaction do
        TxnapRecord.create!(name: "committed before raise")
        sleep delay
      end
    end.to raise_error(Txnap::IdleGapDetected, /already been committed/)

    expect(TxnapRecord.exists?(name: "committed before raise")).to be(true)
    expect(Txnap.registry.size).to eq(0)
  end

  it "keeps concurrent connections isolated" do
    if ActiveRecord::Base.connection.adapter_name == "SQLite" && ActiveRecord.version >= Gem::Version.new("8.0")
      skip "SQLite 8 uses BEGIN IMMEDIATE; PostgreSQL smoke covers concurrent transactions"
    end

    ready = Queue.new
    proceed = Queue.new

    payloads = collect_idle_gap_payloads do
      threads = [delay, delay * 1.5].map do |thread_delay|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ActiveRecord::Base.transaction do
              TxnapRecord.count
              ready << true
              proceed.pop
              sleep thread_delay
              TxnapRecord.count
            end
          end
        end
      end

      2.times { ready.pop }
      2.times { proceed << true }
      threads.each(&:join)
    end

    expect(payloads.length).to eq(2)
    expect(payloads.map { |payload| payload[:longest_gap_ms] }.min).to be > delay * 800
    expect(Txnap.registry.size).to eq(0)
  end
end
