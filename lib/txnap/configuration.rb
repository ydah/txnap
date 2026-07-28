# frozen_string_literal: true

module Txnap
  class Configuration
    MODES = %i[log raise].freeze
    CAPTURE_CALL_SITES = %i[always sampled off].freeze

    attr_accessor :gap_threshold,
      :min_transaction_duration,
      :only_with_locks,
      :capture_call_sites,
      :ignore_if,
      :logger
    attr_reader :mode

    def initialize
      @mode = :log
      @gap_threshold = 0.1
      @min_transaction_duration = 0.0
      @only_with_locks = false
      @capture_call_sites = :always
      @ignore_if = nil
      @logger = nil
    end

    def mode=(value)
      @mode = value&.to_sym
    end

    def validate!
      validate_choice!(:mode, mode, MODES)
      validate_non_negative_number!(:gap_threshold, gap_threshold)
      validate_non_negative_number!(:min_transaction_duration, min_transaction_duration)
      validate_boolean!(:only_with_locks, only_with_locks)
      validate_choice!(:capture_call_sites, capture_call_sites, CAPTURE_CALL_SITES)
      validate_callable!(:ignore_if, ignore_if)
      self
    end

    private

    def validate_choice!(name, value, choices)
      return if choices.include?(value)

      raise ConfigurationError, "#{name} must be one of: #{choices.join(", ")}"
    end

    def validate_non_negative_number!(name, value)
      return if value.is_a?(Numeric) && value.finite? && value >= 0

      raise ConfigurationError, "#{name} must be a finite, non-negative number"
    end

    def validate_boolean!(name, value)
      return if value == true || value == false

      raise ConfigurationError, "#{name} must be true or false"
    end

    def validate_callable!(name, value)
      return if value.nil? || value.respond_to?(:call)

      raise ConfigurationError, "#{name} must respond to call"
    end
  end
end
