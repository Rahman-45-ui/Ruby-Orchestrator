require "minitest/autorun"
require "tmpdir"
require_relative "../../lib/ruby_orchestrator/memory/sqlite_store"

class SQLiteStoreSpec < Minitest::Test
  def setup
    @store = RubyOrchestrator::Memory::SQLiteStore.new(path: ":memory:")
  end

  def teardown
    @store.close
  end

  def test_saves_and_finds_a_completed_run
    run = RubyOrchestrator::Run.new(workflow: "sample", input: { "name" => "Ruby" })
    run.start!.succeed!(result: { "message" => "done" })
    @store.save(run)

    record = @store.find(run.id)

    assert_equal run.id, record[:id]
    assert_equal "sample", record[:workflow]
    assert_equal({ "name" => "Ruby" }, record[:input])
    assert_equal :succeeded, record[:status]
    assert_equal({ "message" => "done" }, record[:result])
    assert_equal run.created_at.to_i, record[:created_at].to_i
  end

  def test_saves_failure_details
    run = RubyOrchestrator::Run.new(workflow: "sample")
    run.start!.fail!(error: RuntimeError.new("workflow failed"))
    @store.save(run)

    record = @store.find(run.id)

    assert_equal :failed, record[:status]
    assert_equal({ class: "RuntimeError", message: "workflow failed" }, record[:error])
  end

  def test_returns_nil_when_run_does_not_exist
    assert_nil @store.find("missing")
  end

  def test_persists_run_after_reopening_database
    Dir.mktmpdir do |directory|
      path = File.join(directory, "runs.sqlite3")
      run = RubyOrchestrator::Run.new(workflow: "sample")
      run.start!.succeed!(result: "done")

      first_store = RubyOrchestrator::Memory::SQLiteStore.new(path: path)
      first_store.save(run)
      first_store.close
      reopened_store = RubyOrchestrator::Memory::SQLiteStore.new(path: path)

      assert_equal :succeeded, reopened_store.find(run.id)[:status]

      reopened_store.close
    end
  end
end
