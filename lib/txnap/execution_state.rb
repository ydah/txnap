# frozen_string_literal: true

module Txnap
  module ExecutionState
    KEY = :txnap_suppression_depth

    module_function

    def suppress
      state[KEY] = suppression_depth + 1
      yield
    ensure
      state[KEY] = [suppression_depth - 1, 0].max
    end

    def suppressed?
      suppression_depth.positive?
    end

    def suppression_depth
      state[KEY] || 0
    end

    def state
      ActiveSupport::IsolatedExecutionState
    end
  end
end
