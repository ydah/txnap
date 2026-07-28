# frozen_string_literal: true

module Txnap
  EventMetadata = Data.define(:sql, :name, :call_site) do
    def to_h
      {sql: sql, name: name, call_site: call_site}
    end
  end

  Gap = Data.define(:duration, :after, :before, :locks) do
    def to_h
      {
        duration_ms: duration * 1000.0,
        after: after&.to_h,
        before: before&.to_h
      }
    end
  end

  LockCandidate = Data.define(:statement, :table, :kind, :call_site) do
    def to_h
      {statement: statement, table: table, kind: kind, call_site: call_site}
    end
  end

  class Report
    attr_reader :outcome,
      :transaction_duration,
      :database_time,
      :longest_gap,
      :gaps,
      :locks,
      :sql_count

    def initialize(outcome:, transaction_duration:, database_time:, gaps:, sql_count:)
      @outcome = outcome
      @transaction_duration = transaction_duration
      @database_time = database_time
      @gaps = gaps.freeze
      @longest_gap = gaps.first
      @locks = (@longest_gap&.locks || []).freeze
      @sql_count = sql_count
    end

    def to_h
      {
        outcome: outcome,
        transaction_duration_ms: transaction_duration * 1000.0,
        database_time_ms: database_time * 1000.0,
        longest_gap_ms: longest_gap.duration * 1000.0,
        sql_count: sql_count,
        gap: longest_gap.to_h,
        gaps: gaps.map(&:to_h),
        locks: locks.map(&:to_h)
      }
    end
  end
end
