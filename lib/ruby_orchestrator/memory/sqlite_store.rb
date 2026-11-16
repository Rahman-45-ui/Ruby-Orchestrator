require "json"
require "time"
require "sqlite3"
require_relative "../run"

module RubyOrchestrator
  module Memory
    class SQLiteStore
      def initialize(path:)
        @database = SQLite3::Database.new(path)
        @database.busy_timeout = 5_000
        create_schema
      end

      def save(run)
        raise ArgumentError, "run must be a RubyOrchestrator::Run" unless run.is_a?(Run)

        @database.execute(
          <<~SQL,
            INSERT OR REPLACE INTO runs (
              id, workflow, input_json, status, result_json,
              error_class, error_message, created_at, started_at, finished_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          [
            run.id,
            run.workflow,
            JSON.generate(run.input),
            run.status.to_s,
            JSON.generate(run.result),
            run.error&.class&.name,
            run.error&.message,
            run.created_at.iso8601(6),
            run.started_at&.iso8601(6),
            run.finished_at&.iso8601(6)
          ]
        )
        run
      end

      def find(id)
        row = @database.get_first_row(
          "SELECT id, workflow, input_json, status, result_json, error_class, error_message, created_at, started_at, finished_at FROM runs WHERE id = ?",
          id
        )
        return unless row

        {
          id: row[0],
          workflow: row[1],
          input: JSON.parse(row[2]),
          status: row[3].to_sym,
          result: JSON.parse(row[4]),
          error: row[5] && { class: row[5], message: row[6] },
          created_at: Time.iso8601(row[7]),
          started_at: row[8] && Time.iso8601(row[8]),
          finished_at: row[9] && Time.iso8601(row[9])
        }
      end

      def close
        @database.close
      end

      private

      def create_schema
        @database.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS runs (
            id TEXT PRIMARY KEY NOT NULL,
            workflow TEXT NOT NULL,
            input_json TEXT NOT NULL,
            status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'succeeded', 'failed')),
            result_json TEXT NOT NULL,
            error_class TEXT,
            error_message TEXT,
            created_at TEXT NOT NULL,
            started_at TEXT,
            finished_at TEXT
          );
        SQL
      end
    end
  end
end
