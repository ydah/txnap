# frozen_string_literal: true

module Txnap
  class Registry
    def initialize(&warning_handler)
      @warning_handler = warning_handler
      @mutex = Mutex.new
      @traces = {}.compare_by_identity
    end

    def start(connection, trace)
      stale_trace = @mutex.synchronize do
        stale = @traces[connection]
        @traces[connection] = trace
        stale
      end
      @warning_handler&.call("discarded a stale trace before a new BEGIN") if stale_trace
      trace
    end

    def fetch(connection)
      @mutex.synchronize { @traces[connection] }
    end

    def bind_transaction(connection, transaction)
      return unless transaction

      @mutex.synchronize { @traces[connection]&.bind_transaction(transaction) }
    end

    def finalize(connection, transaction)
      @mutex.synchronize do
        trace = @traces[connection]
        return unless trace
        matches_transaction = trace.matches_transaction?(transaction)
        matches_terminal_without_binding = trace.transaction.nil? && trace.terminal?
        return unless matches_transaction || matches_terminal_without_binding

        @traces.delete(connection)
      end
    end

    def size
      @mutex.synchronize { @traces.size }
    end

    def reset!
      @mutex.synchronize { @traces.clear }
    end
  end
end
