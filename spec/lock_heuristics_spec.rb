# frozen_string_literal: true

RSpec.describe Txnap::LockHeuristics do
  describe ".detect" do
    {
      'INSERT INTO "users" ("name") VALUES ("A")' => ["INSERT", "users", "row lock"],
      "insert into users (name) values ('A')" => ["INSERT", "users", "row lock"],
      "INSERT OR REPLACE INTO `users` VALUES (1)" => ["INSERT", "users", "row lock"],
      'UPDATE "users" SET "name" = ?' => ["UPDATE", "users", "row lock"],
      "update public.users set name = 'A'" => ["UPDATE", "public.users", "row lock"],
      "UPDATE ONLY [users] SET name = 'A'" => ["UPDATE", "users", "row lock"],
      'DELETE FROM "public"."users" WHERE id = 1' => ["DELETE", "public.users", "row lock"],
      "delete from only users where id = 1" => ["DELETE", "users", "row lock"],
      "SELECT * FROM users WHERE id = 1 FOR UPDATE" => ["SELECT", "users", "row lock"],
      'select * from "users" for no key update' => ["SELECT", "users", "row lock"],
      "SELECT * FROM public.users FOR SHARE" => ["SELECT", "public.users", "row lock"],
      "SELECT * FROM users FOR KEY SHARE" => ["SELECT", "users", "row lock"],
      "LOCK TABLE users IN EXCLUSIVE MODE" => ["LOCK TABLE", "users", "table lock"],
      'lock table only "public"."users"' => ["LOCK TABLE", "public.users", "table lock"],
      "SELECT pg_advisory_xact_lock(42)" => ["ADVISORY LOCK", "pg_advisory_xact_lock", "advisory lock"],
      "SELECT pg_try_advisory_lock(42)" => ["ADVISORY LOCK", "pg_try_advisory_lock", "advisory lock"],
      "SELECT GET_LOCK('key', 1)" => ["ADVISORY LOCK", "get_lock", "advisory lock"],
      "/* request id */ -- write follows\nUPDATE users SET name = 'A'" => ["UPDATE", "users", "row lock"]
    }.each do |sql, expected|
      it "recognizes #{sql.lines.last.strip}" do
        candidate = described_class.detect(sql, call_site: "app/models/user.rb:12")

        expect([candidate.statement, candidate.table, candidate.kind]).to eq(expected)
        expect(candidate.call_site).to eq("app/models/user.rb:12")
      end
    end

    [
      "SELECT * FROM users",
      "SELECT 'FOR UPDATE' AS text",
      "PRAGMA table_info(users)",
      "BEGIN",
      ""
    ].each do |sql|
      it "ignores #{sql.inspect}" do
        expect(described_class.detect(sql)).to be_nil
      end
    end
  end
end
