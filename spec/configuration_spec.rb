# frozen_string_literal: true

RSpec.describe Txnap::Configuration do
  subject(:configuration) { described_class.new }

  it "uses safe production defaults" do
    expect(configuration.mode).to eq(:log)
    expect(configuration.gap_threshold).to eq(0.1)
    expect(configuration.min_transaction_duration).to eq(0.0)
    expect(configuration.only_with_locks).to be(false)
    expect(configuration.capture_call_sites).to eq(:always)
  end

  it "accepts all documented values" do
    configuration.mode = :raise
    configuration.capture_call_sites = :sampled
    configuration.ignore_if = ->(_report) { false }

    expect(configuration.validate!).to be(configuration)
  end

  it "rejects an invalid mode" do
    configuration.mode = :silent

    expect { configuration.validate! }
      .to raise_error(Txnap::ConfigurationError, /mode/)
  end

  it "rejects negative thresholds" do
    configuration.gap_threshold = -0.1

    expect { configuration.validate! }
      .to raise_error(Txnap::ConfigurationError, /gap_threshold/)
  end

  it "rejects non-callable ignore predicates" do
    configuration.ignore_if = true

    expect { configuration.validate! }
      .to raise_error(Txnap::ConfigurationError, /ignore_if/)
  end

  it "rejects a non-boolean lock filter" do
    configuration.only_with_locks = nil

    expect { configuration.validate! }
      .to raise_error(Txnap::ConfigurationError, /only_with_locks/)
  end
end
