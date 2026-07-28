# frozen_string_literal: true

module Txnap
  module LockHeuristics
    IDENTIFIER_PART = /(?:"(?:[^"]|"")*"|`(?:[^`]|``)*`|\[[^\]]+\]|[a-z_][a-z0-9_$]*)/i
    QUALIFIED_IDENTIFIER = /#{IDENTIFIER_PART}(?:\s*\.\s*#{IDENTIFIER_PART})*/
    ADVISORY_FUNCTION = /
      (?:
        pg_(?:try_)?advisory_(?:xact_)?lock(?:_shared)?
        |
        get_lock
      )
    /ix

    module_function

    def detect(sql, call_site: nil)
      statement = strip_leading_comments(Array(sql).join(" "))
      return if statement.empty?

      operation, table, kind =
        case statement
        when /\AINSERT(?:\s+OR\s+\w+)?\s+INTO\s+(#{QUALIFIED_IDENTIFIER})/io
          ["INSERT", normalize_identifier(Regexp.last_match(1)), "row lock"]
        when /\AUPDATE\s+(?:ONLY\s+)?(#{QUALIFIED_IDENTIFIER})/io
          ["UPDATE", normalize_identifier(Regexp.last_match(1)), "row lock"]
        when /\ADELETE\s+FROM\s+(?:ONLY\s+)?(#{QUALIFIED_IDENTIFIER})/io
          ["DELETE", normalize_identifier(Regexp.last_match(1)), "row lock"]
        when /\ALOCK\s+TABLE\s+(?:ONLY\s+)?(#{QUALIFIED_IDENTIFIER})/io
          ["LOCK TABLE", normalize_identifier(Regexp.last_match(1)), "table lock"]
        else
          detect_select_or_advisory(statement)
        end

      return unless operation

      LockCandidate.new(
        statement: operation,
        table: table,
        kind: kind,
        call_site: call_site
      ).freeze
    end

    def detect_select_or_advisory(statement)
      if statement.match?(/\ASELECT\b/im) &&
          statement.match?(/\bFOR\s+(?:NO\s+KEY\s+)?(?:UPDATE|SHARE|KEY\s+SHARE)\b/im)
        table = statement[/\bFROM\s+(#{QUALIFIED_IDENTIFIER})/io, 1]
        return ["SELECT", normalize_identifier(table), "row lock"] if table
      end

      function = statement[ADVISORY_FUNCTION]
      return unless function

      ["ADVISORY LOCK", function.downcase, "advisory lock"]
    end

    def strip_leading_comments(sql)
      remaining = sql.lstrip

      loop do
        stripped =
          if remaining.start_with?("--")
            remaining.sub(/\A--[^\n]*(?:\n|\z)/, "").lstrip
          elsif remaining.start_with?("/*")
            remaining.sub(/\A\/\*.*?\*\//m, "").lstrip
          else
            remaining
          end
        return remaining if stripped == remaining

        remaining = stripped
      end
    end

    def normalize_identifier(identifier)
      return unless identifier

      identifier.split(/\s*\.\s*/).map do |part|
        case part
        when /\A"(.*)"\z/m
          Regexp.last_match(1).gsub('""', '"')
        when /\A`(.*)`\z/m
          Regexp.last_match(1).gsub("``", "`")
        when /\A\[(.*)\]\z/m
          Regexp.last_match(1)
        else
          part
        end
      end.join(".")
    end
  end
end
