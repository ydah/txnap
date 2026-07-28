# frozen_string_literal: true

require "json"

active_record_version = ARGV.fetch(0) { ENV.fetch("ACTIVE_RECORD_VERSION") }
adapter = ARGV.fetch(1) { ENV.fetch("ADAPTER", "sqlite3") }

gem "activerecord", active_record_version
gem (adapter == "postgresql") ? "pg" : "sqlite3"

require "active_record"
require "active_support/notifications"

database_config =
  if adapter == "postgresql"
    {
      adapter: "postgresql",
      url: ARGV.fetch(2) do
        ENV.fetch("DATABASE_URL", "postgresql://postgres:postgres@127.0.0.1:55433/txnap")
      end
    }
  else
    {adapter: "sqlite3", database: ":memory:"}
  end

ActiveRecord::Base.establish_connection(database_config)
connection = ActiveRecord::Base.connection
connection.create_table(:event_probe_records, force: true) do |table|
  table.string :name, null: false
end

class EventProbeRecord < ActiveRecord::Base
end

events = []
subscriptions = %w[
  sql.active_record
  start_transaction.active_record
  transaction.active_record
].map do |event_name|
  ActiveSupport::Notifications.monotonic_subscribe(event_name) do |name, start, finish, _id, payload|
    events << {
      event: name,
      start: start,
      finish: finish,
      duration_ms: (finish - start) * 1000,
      name: payload[:name],
      sql: payload[:sql],
      cached: payload[:cached],
      outcome: payload[:outcome],
      connection_id: payload[:connection]&.object_id,
      transaction_id: payload[:transaction]&.object_id
    }.compact
  end
end

ActiveRecord::Base.transaction do
  sleep 0.01
  EventProbeRecord.create!(name: "commit")

  ActiveRecord::Base.transaction(requires_new: true) do
    EventProbeRecord.create!(name: "savepoint")
  end

  connection.cache do
    EventProbeRecord.first
    EventProbeRecord.first
  end
  sleep 0.01
end

begin
  ActiveRecord::Base.transaction do
    EventProbeRecord.create!(name: "rollback")
    raise ActiveRecord::Rollback
  end

  ActiveRecord::Base.transaction do
    ActiveRecord::Base.transaction(requires_new: true) do
      EventProbeRecord.create!(name: "restart")
      raise ActiveRecord::Rollback
    end
    EventProbeRecord.create!(name: "after restart")
  end
ensure
  subscriptions.each { |subscription| ActiveSupport::Notifications.unsubscribe(subscription) }
end

puts JSON.pretty_generate(
  active_record: ActiveRecord.version.to_s,
  adapter: connection.adapter_name,
  connection_id: connection.object_id,
  events: events
)
