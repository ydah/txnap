# frozen_string_literal: true

module Txnap
  class Notifier
    EVENT_NAME = "idle_gap.txnap"

    def initialize(configuration:, logger:)
      @configuration = configuration
      @logger = logger
    end

    def call(report)
      return false unless report
      return false unless report.longest_gap.duration >= configuration.gap_threshold
      return false unless report.transaction_duration >= configuration.min_transaction_duration
      return false if configuration.only_with_locks && report.locks.empty?
      return false if ExecutionState.suppressed?
      return false if ignored?(report)

      ActiveSupport::Notifications.instrument(EVENT_NAME, report.to_h)
      message = Formatter.new.call(report)

      raise IdleGapDetected, raise_message(message, report) if configuration.mode == :raise

      logger.warn(message)
      true
    end

    private

    attr_reader :configuration, :logger

    def ignored?(report)
      predicate = configuration.ignore_if
      return false unless predicate

      predicate.arity.zero? ? predicate.call : predicate.call(report)
    end

    def raise_message(message, report)
      suffix =
        if report.outcome.to_sym == :commit
          "The transaction has already been committed; this exception cannot roll it back."
        else
          "The transaction has already finished; this exception cannot change its outcome."
        end

      "#{message}\n\n#{suffix}"
    end
  end
end
