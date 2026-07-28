# frozen_string_literal: true

RSpec.describe Txnap do
  it "has a version number" do
    expect(Txnap::VERSION).not_to be nil
  end

  it "configures the detector" do
    described_class.configure do |configuration|
      configuration.gap_threshold = 0.25
    end

    expect(described_class.configuration.gap_threshold).to eq(0.25)
  end

  it "suppresses reports within the current execution context" do
    expect do
      described_class.suppress do
        expect(Txnap::ExecutionState.suppressed?).to be(true)
      end
    end.not_to raise_error

    expect(Txnap::ExecutionState.suppressed?).to be(false)
  end

  it "restores suppression state after an exception" do
    expect do
      described_class.suppress { raise "failure" }
    end.to raise_error("failure")

    expect(Txnap::ExecutionState.suppressed?).to be(false)
  end
end
