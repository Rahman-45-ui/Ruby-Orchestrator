require "minitest/autorun"
require_relative "../../lib/ruby_orchestrator"

class WorkflowExecutionSpec < Minitest::Test
  def test_executes_yaml_workflow_and_persists_result
    store = RubyOrchestrator::Memory::SQLiteStore.new(path: ":memory:")
    orchestrator = RubyOrchestrator::Orchestrator.new(
      workflow_runner: RubyOrchestrator::WorkflowRunner.new,
      run_store: store
    )

    run = orchestrator.execute(
      workflow: "examples/hello",
      input: { "name" => "Ruby" }
    )

    assert_equal :succeeded, run.status
    assert_equal(
      {
        "workflow" => "hello",
        "steps" => { "greeting" => "Hello from a YAML workflow!" }
      },
      run.result
    )
    assert_equal :succeeded, store.find(run.id)[:status]
  ensure
    store&.close
  end
end
