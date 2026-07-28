# frozen_string_literal: true

module Txnap
  module Subscribers
    class TransactionSubscriber
      class << self
        def install
          @subscriptions ||= begin
            subscriber = new
            [
              ActiveSupport::Notifications.monotonic_subscribe("start_transaction.active_record") do |*args|
                subscriber.start(*args)
              end,
              ActiveSupport::Notifications.monotonic_subscribe("transaction.active_record") do |*args|
                subscriber.finish(*args)
              end
            ]
          end
        end
      end

      def start(_name, _start, _finish, _id, payload)
        connection = payload[:connection]
        return unless connection

        Txnap.registry.bind_transaction(connection, payload[:transaction])
      rescue => error
        Txnap.warn("transaction start subscriber failed: #{error.class}: #{error.message}")
      end

      def finish(_name, _start, _finish, _id, payload)
        connection = payload[:connection]
        return unless connection

        trace = Txnap.registry.finalize(connection, payload[:transaction])
        Txnap.notify(trace&.to_report(payload[:outcome]))
      rescue IdleGapDetected
        raise
      rescue => error
        Txnap.warn("transaction finish subscriber failed: #{error.class}: #{error.message}")
      end
    end
  end
end
