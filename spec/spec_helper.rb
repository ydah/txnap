# frozen_string_literal: true

require "stringio"
require "fileutils"

require "active_record"
require "txnap"

database_url = ENV["DATABASE_URL"]
database_config =
  database_url || {
    adapter: "sqlite3",
    database: File.expand_path("../tmp/txnap_spec.sqlite3", __dir__),
    pool: 8,
    timeout: 5000
  }

ActiveRecord::Base.establish_connection(database_config)
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :txnap_records, force: true do |table|
    table.string :name, null: false
    table.timestamps
  end
end

class TxnapRecord < ActiveRecord::Base
end

TxnapRecord.columns
Txnap.install!

module ReportHelpers
  def collect_idle_gap_payloads
    payloads = []
    mutex = Mutex.new
    subscription = ActiveSupport::Notifications.subscribe(
      Txnap::Notifier::EVENT_NAME
    ) do |_name, _start, _finish, _id, payload|
      mutex.synchronize { payloads << payload }
    end

    yield
    payloads
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  def time_scale
    ENV.fetch("TIME_SCALE", "1.0").to_f
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include ReportHelpers

  config.before do
    Txnap.reset!
    Txnap.configure do |settings|
      settings.gap_threshold = 0.01 * time_scale
      settings.capture_call_sites = :off
      settings.logger = Logger.new(StringIO.new)
    end
  end
end
