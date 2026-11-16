require "minitest/autorun"
require_relative "../../lib/ruby_orchestrator/run"

class RunSpec < Minitest::Test
  def test_tracks_successful_lifecycle
    run = RubyOrchestrator::Run.new(workflow: "sample", input: { "name" => "Ruby" })

    run.start!.succeed!(result: "done")

    assert_equal :succeeded, run.status
    assert_equal "done", run.result
    assert run.started_at
    assert run.finished_at
  end

  def test_rejects_invalid_state_transition
    run = RubyOrchestrator::Run.new(workflow: "sample")

    assert_raises(RubyOrchestrator::Run::InvalidTransitionError) { run.succeed! }
  end

  def test_tracks_failure
    error = RuntimeError.new("workflow failed")
    run = RubyOrchestrator::Run.new(workflow: "sample")

    run.start!.fail!(error: error)

    assert_equal :failed, run.status
    assert_same error, run.error
    assert run.finished_at
  end
end
