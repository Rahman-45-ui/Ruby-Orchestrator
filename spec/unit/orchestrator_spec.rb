require "minitest/autorun"
require_relative "../../lib/ruby_orchestrator/orchestrator"

class OrchestratorSpec < Minitest::Test
  def test_executes_workflow_and_returns_completed_run
    runner = ->(run) { { "workflow" => run.workflow, "input" => run.input } }
    orchestrator = RubyOrchestrator::Orchestrator.new(workflow_runner: runner)

    run = orchestrator.execute(workflow: "sample", input: { "name" => "Ruby" })

    assert_equal :succeeded, run.status
    assert_equal({ "workflow" => "sample", "input" => { "name" => "Ruby" } }, run.result)
  end

  def test_reraises_runner_error
    error = RuntimeError.new("workflow failed")
    orchestrator = RubyOrchestrator::Orchestrator.new(workflow_runner: ->(_run) { raise error })

    raised_error = assert_raises(RuntimeError) { orchestrator.execute(workflow: "sample") }

    assert_same error, raised_error
  end

  def test_persists_each_run_lifecycle_state
    store = Class.new do
      attr_reader :statuses

      def initialize
        @statuses = []
      end

      def save(run)
        @statuses << run.status
      end
    end.new
    orchestrator = RubyOrchestrator::Orchestrator.new(
      workflow_runner: ->(_run) { "done" },
      run_store: store
    )

    orchestrator.execute(workflow: "sample")

    assert_equal %i[pending running succeeded], store.statuses
  end
end
