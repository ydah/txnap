# frozen_string_literal: true

module Txnap
  module Subscribers
    class SqlSubscriber
      class << self
        def install
          @subscription ||= begin
            subscriber = new
            ActiveSupport::Notifications.monotonic_subscribe("sql.active_record") do |*args|
              subscriber.call(*args)
            end
          end
        end
      end

      def call(_name, start, finish, _id, payload)
        connection = payload[:connection]
        return unless connection

        case SqlEventClassifier.classify(payload)
        when :cache, :schema
          nil
        when :begin
          start_trace(connection, start, finish, payload)
        when :commit, :rollback
          registry.fetch(connection)&.record_terminal(start: start, finish: finish, sql: payload[:sql])
        when :transaction
          registry.fetch(connection)&.record_transaction(start: start, finish: finish, sql: payload[:sql])
        when :sql
          record_sql(connection, start, finish, payload)
        end
      rescue => error
        Txnap.warn("sql subscriber failed: #{error.class}: #{error.message}")
      end

      private

      def registry
        Txnap.registry
      end

      def start_trace(connection, start, finish, payload)
        registry.start(
          connection,
          Trace.new(start: start, finish: finish, sql: payload[:sql])
        )
      end

      def record_sql(connection, start, finish, payload)
        trace = registry.fetch(connection)
        return unless trace

        call_site = capture_call_site(trace, start)
        lock_candidate = LockHeuristics.detect(payload[:sql], call_site: call_site)
        trace.record_sql(
          start: start,
          finish: finish,
          sql: payload[:sql],
          name: payload[:name],
          call_site: call_site,
          lock_candidate: lock_candidate
        )
      end

      def capture_call_site(trace, start)
        case Txnap.configuration.capture_call_sites
        when :always
          CallSite.capture
        when :sampled
          CallSite.capture if trace.would_update_longest_gap?(start)
        end
      end
    end
  end
end
