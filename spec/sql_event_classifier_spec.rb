# frozen_string_literal: true

RSpec.describe Txnap::SqlEventClassifier do
  describe ".classify" do
    {
      "cached flag" => [{name: "Model Load", sql: "SELECT 1", cached: true}, :cache],
      "legacy cache name" => [{name: "CACHE", sql: "SELECT 1"}, :cache],
      "schema" => [{name: "SCHEMA", sql: "PRAGMA table_info"}, :schema],
      "normal SQL" => [{name: "Model Load", sql: "SELECT 1"}, :sql],
      "PostgreSQL begin" => [{name: "TRANSACTION", sql: "BEGIN"}, :begin],
      "SQLite 7.2 begin" => [{name: "TRANSACTION", sql: "begin transaction"}, :begin],
      "SQLite 8.0 begin" => [{name: "TRANSACTION", sql: "BEGIN immediate TRANSACTION"}, :begin],
      "MySQL begin" => [{name: "TRANSACTION", sql: "START TRANSACTION"}, :begin],
      "commit" => [{name: "TRANSACTION", sql: "COMMIT TRANSACTION"}, :commit],
      "rollback" => [{name: "TRANSACTION", sql: "ROLLBACK"}, :rollback],
      "rollback and chain" => [{name: "TRANSACTION", sql: "ROLLBACK AND CHAIN"}, :rollback],
      "rollback savepoint" => [{name: "TRANSACTION", sql: "ROLLBACK TO SAVEPOINT active_record_1"}, :transaction],
      "savepoint" => [{name: "TRANSACTION", sql: "SAVEPOINT active_record_1"}, :transaction],
      "release savepoint" => [{name: "TRANSACTION", sql: "RELEASE SAVEPOINT active_record_1"}, :transaction]
    }.each do |example, (payload, classification)|
      it "classifies #{example}" do
        expect(described_class.classify(payload)).to eq(classification)
      end
    end
  end
end
