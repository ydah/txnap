# frozen_string_literal: true

RSpec.describe Txnap::CallSite do
  def capture_from_application
    described_class.capture
  end

  it "returns the first application frame relative to the working directory" do
    expect(capture_from_application).to match(/\Aspec\/call_site_spec\.rb:\d+\z/)
  end

  it "returns nil when no application frame is available" do
    internal = Struct.new(:absolute_path, :path, :lineno).new(
      File.join(described_class::LIB_ROOT, "internal.rb"),
      nil,
      1
    )

    expect(described_class.capture([internal])).to be_nil
  end
end
