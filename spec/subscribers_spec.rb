# frozen_string_literal: true

RSpec.describe "notification subscribers" do
  let(:output) { StringIO.new }

  before do
    Txnap.configure { |settings| settings.logger = Logger.new(output) }
  end

  it "turns SQL subscriber failures into warnings" do
    registry = instance_double(Txnap::Registry)
    allow(Txnap).to receive(:registry).and_return(registry)
    allow(registry).to receive(:fetch).and_raise("injected SQL failure")

    expect do
      Txnap::Subscribers::SqlSubscriber.new.call(
        "sql.active_record",
        1.0,
        1.1,
        "id",
        connection: Object.new,
        name: "SQL",
        sql: "SELECT 1"
      )
    end.not_to raise_error

    expect(output.string).to include("sql subscriber failed", "injected SQL failure")
  end

  it "turns transaction subscriber failures into warnings" do
    registry = instance_double(Txnap::Registry)
    allow(Txnap).to receive(:registry).and_return(registry)
    allow(registry).to receive(:finalize).and_raise("injected transaction failure")

    expect do
      Txnap::Subscribers::TransactionSubscriber.new.finish(
        "transaction.active_record",
        1.0,
        1.1,
        "id",
        connection: Object.new,
        transaction: Object.new,
        outcome: :commit
      )
    end.not_to raise_error

    expect(output.string).to include("transaction finish subscriber failed", "injected transaction failure")
  end

  %i[commit rollback restart incomplete].each do |outcome|
    it "removes the root trace for the #{outcome} outcome" do
      connection = Object.new
      transaction = Object.new
      trace = Txnap::Trace.new(start: 0.0, finish: 0.01, sql: "BEGIN")
      Txnap.registry.start(connection, trace)
      Txnap.registry.bind_transaction(connection, transaction)

      Txnap::Subscribers::TransactionSubscriber.new.finish(
        "transaction.active_record",
        1.0,
        1.1,
        "id",
        connection: connection,
        transaction: transaction,
        outcome: outcome
      )

      expect(Txnap.registry.size).to eq(0)
    end
  end
end
