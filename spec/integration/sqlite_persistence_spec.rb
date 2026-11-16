require "minitest/autorun"
require_relative "../../lib/ruby_orchestrator"

class SQLitePersistenceSpec < Minitest::Test
  def test_orchestrator_persists_successful_run
    store = RubyOrchestrator::Memory::SQLiteStore.new(path: ":memory:")
    orchestrator = RubyOrchestrator::Orchestrator.new(
      workflow_runner: ->(_run) { { "ok" => true } },
      run_store: store
    )

    run = orchestrator.execute(workflow: "sample")

    assert_equal :succeeded, store.find(run.id)[:status]
    assert_equal({ "ok" => true }, store.find(run.id)[:result])
  ensure
    store&.close
  end

  def test_orchestrator_persists_failure_before_reraising
    store = RubyOrchestrator::Memory::SQLiteStore.new(path: ":memory:")
    error = RuntimeError.new("workflow failed")
    run_id = nil
    orchestrator = RubyOrchestrator::Orchestrator.new(
      workflow_runner: lambda { |run|
        run_id = run.id
        raise error
      },
      run_store: store
    )

    assert_raises(RuntimeError) { orchestrator.execute(workflow: "sample") }

    record = store.find(run_id)
    assert_equal :failed, record[:status]
    assert_equal "workflow failed", record[:error][:message]
  ensure
    store&.close
  end
end
