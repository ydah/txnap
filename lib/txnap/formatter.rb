# frozen_string_literal: true

module Txnap
  class Formatter
    def call(report)
      gap = report.longest_gap
      lines = [
        "Txnap::IdleGapDetected",
        "",
        "Transaction held for #{milliseconds(report.transaction_duration)} ms (BEGIN → #{report.outcome.to_s.upcase})",
        "Database time: #{milliseconds(report.database_time)} ms",
        "Longest non-database gap: #{milliseconds(gap.duration)} ms",
        "",
        "Gap occurred between:",
        "  after:  #{event(gap.after)}",
        "  before: #{event(gap.before)}"
      ]

      append_locks(lines, report.locks)
      lines.concat([
        "",
        "Move slow non-database work (I/O, rendering, external calls,",
        "heavy computation) outside the transaction."
      ])
      lines.join("\n")
    end

    private

    def milliseconds(seconds)
      (seconds * 1000).round
    end

    def event(metadata)
      return "(transaction boundary)" unless metadata

      [metadata.sql, metadata.call_site && "(#{metadata.call_site})"].compact.join(" ")
    end

    def append_locks(lines, locks)
      return if locks.empty?

      lines.concat(["", "Locks possibly held during the gap:"])
      locks.each do |lock|
        location = lock.call_site && "  #{lock.call_site}"
        lines << "  #{lock.statement} #{lock.table} (#{lock.kind})#{location}"
      end
    end
  end
end
