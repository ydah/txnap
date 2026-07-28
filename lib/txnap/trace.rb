# frozen_string_literal: true

module Txnap
  class Trace
    TOP_GAPS_LIMIT = 3
    LOCK_CANDIDATES_LIMIT = 20
    SQL_LENGTH_LIMIT = 500

    attr_reader :started_at, :database_time, :sql_count, :transaction

    def initialize(start:, finish:, sql:)
      @started_at = finish
      @previous_finish = finish
      @previous_event = metadata(sql, "TRANSACTION", nil)
      @database_time = positive_duration(start, finish)
      @sql_count = 0
      @gaps = []
      @lock_candidates = []
      @transaction = nil
      @ended_at = nil
    end

    def bind_transaction(transaction)
      @transaction ||= transaction
    end

    def matches_transaction?(candidate)
      transaction && candidate && transaction.equal?(candidate)
    end

    def terminal?
      !@ended_at.nil?
    end

    def would_update_longest_gap?(start)
      gap_duration(start) > longest_gap_duration
    end

    def record_sql(start:, finish:, sql:, name:, call_site:, lock_candidate: nil)
      event = metadata(sql, name, call_site)
      observe_event(start: start, finish: finish, event: event)
      @sql_count += 1
      add_lock_candidate(lock_candidate)
    end

    def record_transaction(start:, finish:, sql:)
      observe_event(
        start: start,
        finish: finish,
        event: metadata(sql, "TRANSACTION", nil)
      )
    end

    def record_terminal(start:, finish:, sql:)
      effective_start = [start, @previous_finish].max
      @ended_at = effective_start
      record_transaction(start: start, finish: finish, sql: sql)
    end

    def to_report(outcome)
      return unless terminal?

      Report.new(
        outcome: outcome,
        transaction_duration: positive_duration(started_at, @ended_at),
        database_time: database_time,
        gaps: @gaps.dup,
        sql_count: sql_count
      )
    end

    private

    def observe_event(start:, finish:, event:)
      effective_start = [start, @previous_finish].max
      effective_finish = [finish, effective_start].max

      observe_gap(effective_start, event)
      @database_time += effective_finish - effective_start
      @previous_finish = effective_finish
      @previous_event = event
    end

    def observe_gap(next_start, next_event)
      gap = Gap.new(
        duration: gap_duration(next_start),
        after: @previous_event,
        before: next_event,
        locks: @lock_candidates.dup.freeze
      )
      @gaps << gap
      @gaps.sort_by! { |candidate| -candidate.duration }
      @gaps.pop while @gaps.length > TOP_GAPS_LIMIT
    end

    def gap_duration(next_start)
      [next_start - @previous_finish, 0.0].max
    end

    def longest_gap_duration
      @gaps.first&.duration || -Float::INFINITY
    end

    def add_lock_candidate(candidate)
      return unless candidate
      return if @lock_candidates.any? do |existing|
        existing.statement == candidate.statement && existing.table == candidate.table
      end
      return if @lock_candidates.length >= LOCK_CANDIDATES_LIMIT

      @lock_candidates << candidate
    end

    def metadata(sql, name, call_site)
      normalized_sql = Array(sql).join(" ").gsub(/\s+/, " ").strip
      normalized_sql = "#{normalized_sql[0, SQL_LENGTH_LIMIT - 1]}…" if normalized_sql.length > SQL_LENGTH_LIMIT
      EventMetadata.new(sql: normalized_sql.freeze, name: name, call_site: call_site).freeze
    end

    def positive_duration(start, finish)
      [finish - start, 0.0].max
    end
  end
end
