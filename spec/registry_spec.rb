# frozen_string_literal: true

RSpec.describe Txnap::Registry do
  let(:warnings) { [] }
  let(:registry) { described_class.new { |message| warnings << message } }
  let(:connection) { Object.new }
  let(:trace) { Txnap::Trace.new(start: 0.0, finish: 0.01, sql: "BEGIN") }

  it "uses connection object identity as its key" do
    connection_class = Class.new do
      def hash = 1
      def eql?(_other) = true
    end
    first = connection_class.new
    second = connection_class.new

    registry.start(first, trace)

    expect(registry.fetch(first)).to be(trace)
    expect(registry.fetch(second)).to be_nil
  end

  it "warns and replaces a stale trace on a new BEGIN" do
    replacement = Txnap::Trace.new(start: 1.0, finish: 1.01, sql: "BEGIN")
    registry.start(connection, trace)

    registry.start(connection, replacement)

    expect(registry.fetch(connection)).to be(replacement)
    expect(warnings).to contain_exactly(/stale trace/)
  end

  it "does not finalize a root trace for a nested lifecycle event" do
    root_transaction = Object.new
    nested_transaction = Object.new
    registry.start(connection, trace)
    registry.bind_transaction(connection, root_transaction)

    expect(registry.finalize(connection, nested_transaction)).to be_nil
    expect(registry.fetch(connection)).to be(trace)
  end

  it "deletes and returns a matching root trace" do
    transaction = Object.new
    registry.start(connection, trace)
    registry.bind_transaction(connection, transaction)

    expect(registry.finalize(connection, transaction)).to be(trace)
    expect(registry.size).to eq(0)
  end
end
