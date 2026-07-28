# frozen_string_literal: true

require "logger"

require "active_support"
require "active_support/isolated_execution_state"
require "active_support/notifications"

require_relative "txnap/version"
require_relative "txnap/errors"
require_relative "txnap/configuration"
require_relative "txnap/execution_state"
require_relative "txnap/sql_event_classifier"
require_relative "txnap/call_site"
require_relative "txnap/lock_heuristics"
require_relative "txnap/report"
require_relative "txnap/trace"
require_relative "txnap/registry"
require_relative "txnap/formatter"
require_relative "txnap/notifier"
require_relative "txnap/subscribers/sql_subscriber"
require_relative "txnap/subscribers/transaction_subscriber"

module Txnap
  class << self
    def configure
      yield(configuration)
      configuration.validate!
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def registry
      @registry ||= Registry.new { |message| warn(message) }
    end

    def install!
      return false if @installed

      Subscribers::SqlSubscriber.install
      Subscribers::TransactionSubscriber.install
      @installed = true
    end

    def suppress(&block)
      ExecutionState.suppress(&block)
    end

    def logger
      configuration.logger || rails_logger || default_logger
    end

    def warn(message)
      logger.warn("[txnap] #{message}")
    rescue
      nil
    end

    def notify(report)
      Notifier.new(configuration: configuration, logger: logger).call(report)
    end

    def reset!
      @configuration = Configuration.new
      registry.reset!
    end

    private

    def rails_logger
      Rails.logger if defined?(Rails) && Rails.respond_to?(:logger)
    end

    def default_logger
      @default_logger ||= Logger.new($stderr)
    end
  end
end

require_relative "txnap/railtie" if defined?(Rails::Railtie)
