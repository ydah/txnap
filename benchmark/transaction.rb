# frozen_string_literal: true

require "benchmark/ips"
require "fileutils"

require "active_record"

database_config = ENV["DATABASE_URL"] || {adapter: "sqlite3", database: ":memory:"}
ActiveRecord::Base.establish_connection(database_config)
connection = ActiveRecord::Base.connection
connection.select_value("SELECT 1")

warmup = ENV.fetch("WARMUP", "2").to_i
time = ENV.fetch("TIME", "5").to_i

measure = lambda do |label|
  Benchmark.ips do |benchmark|
    benchmark.config(warmup: warmup, time: time)
    benchmark.report(label) do
      connection.transaction { connection.select_value("SELECT 1") }
    end
  end.entries.fetch(0).ips
end

baseline_ips = measure.call("without txnap")

require_relative "../lib/txnap"

notification_subscriptions = %w[
  sql.active_record
  start_transaction.active_record
  transaction.active_record
].map do |event_name|
  ActiveSupport::Notifications.monotonic_subscribe(event_name) { nil }
end
notification_ips = measure.call("notification subscribers only")
notification_subscriptions.each { |subscription| ActiveSupport::Notifications.unsubscribe(subscription) }

Txnap.configure do |config|
  config.gap_threshold = 60.0
  config.capture_call_sites = :off
end
Txnap.install!

instrumented_ips = measure.call("with txnap")
overhead = ((baseline_ips - instrumented_ips) / baseline_ips) * 100

puts format(
  "baseline=%.1f i/s notifications=%.1f i/s instrumented=%.1f i/s overhead=%+.2f%%",
  baseline_ips,
  notification_ips,
  instrumented_ips,
  overhead
)
