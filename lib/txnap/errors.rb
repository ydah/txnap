# frozen_string_literal: true

module Txnap
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class IdleGapDetected < Error; end
end
