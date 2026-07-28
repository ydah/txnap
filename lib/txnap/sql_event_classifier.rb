# frozen_string_literal: true

module Txnap
  module SqlEventClassifier
    module_function

    def classify(payload)
      return :cache if payload[:cached] == true || payload[:name] == "CACHE"
      return :schema if payload[:name] == "SCHEMA"
      return :sql unless payload[:name] == "TRANSACTION"

      classify_transaction_sql(payload[:sql])
    end

    def classify_transaction_sql(sql)
      statement = Array(sql).join(" ").strip

      return :begin if statement.match?(/\A(?:BEGIN\b|START\s+TRANSACTION\b)/i)
      return :commit if statement.match?(/\ACOMMIT\b/i)
      return :transaction if statement.match?(/\AROLLBACK\s+TO\b/i)
      return :rollback if statement.match?(/\AROLLBACK\b/i)

      :transaction
    end
  end
end
