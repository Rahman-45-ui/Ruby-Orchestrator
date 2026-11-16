require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../../lib/ruby_orchestrator/run"
require_relative "../../lib/ruby_orchestrator/workflow_runner"

class WorkflowRunnerSpec < Minitest::Test
  def setup
    @directory = Dir.mktmpdir
    File.write(
      File.join(@directory, "sample.yml"),
      <<~YAML
        name: sample
        version: 1
        steps:
          - id: greeting
            uses: core.echo
            with:
              message: hello
          - id: custom
            uses: test.uppercase
            with:
              value: ruby
      YAML
    )
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_runs_steps_in_order_and_collects_outputs
    loader = RubyOrchestrator::WorkflowLoader.new(directory: @directory)
    runner = RubyOrchestrator::WorkflowRunner.new(
      loader: loader,
      handlers: {
        "test.uppercase" => RubyOrchestrator::WorkflowRunner.handler(
          callable: ->(step:, input:, outputs:) { step["with"]["value"].upcase },
          risk: :low
        )
      }
    )
    run = RubyOrchestrator::Run.new(workflow: "sample", input: { "user" => "Ada" })

    result = runner.call(run)

    assert_equal "sample", result["workflow"]
    assert_equal({ "greeting" => "hello", "custom" => "RUBY" }, result["steps"])
  end

  def test_rejects_unregistered_handler
    loader = RubyOrchestrator::WorkflowLoader.new(directory: @directory)
    runner = RubyOrchestrator::WorkflowRunner.new(loader: loader)
    run = RubyOrchestrator::Run.new(workflow: "sample")

    error = assert_raises(RubyOrchestrator::WorkflowRunner::WorkflowExecutionError) do
      runner.call(run)
    end

    assert_match(/not allowlisted/, error.message)
  end

  def test_requires_and_checks_approval_for_risky_handler
    loader = RubyOrchestrator::WorkflowLoader.new(directory: @directory)
    called = false
    runner = RubyOrchestrator::WorkflowRunner.new(
      loader: loader,
      handlers: {
        "test.uppercase" => RubyOrchestrator::WorkflowRunner.handler(
          callable: ->(step:, input:, outputs:) { called = true },
          risk: :high
        )
      }
    )
    run = RubyOrchestrator::Run.new(workflow: "sample")

    error = assert_raises(RubyOrchestrator::WorkflowRunner::ApprovalRequiredError) do
      runner.call(run)
    end

    assert_match(/requires approval/, error.message)
    refute called
  end

  def test_executes_risky_handler_only_after_explicit_approval
    loader = RubyOrchestrator::WorkflowLoader.new(directory: @directory)
    approval_requests = []
    runner = RubyOrchestrator::WorkflowRunner.new(
      loader: loader,
      handlers: {
        "test.uppercase" => RubyOrchestrator::WorkflowRunner.handler(
          callable: ->(step:, input:, outputs:) { step["with"]["value"].upcase },
          risk: :high
        )
      },
      approval_gate: lambda { |**request|
        approval_requests << request
        true
      }
    )
    run = RubyOrchestrator::Run.new(workflow: "sample")

    result = runner.call(run)

    assert_equal "RUBY", result["steps"]["custom"]
    assert_equal :high, approval_requests.first[:risk]
    assert_equal "custom", approval_requests.first[:step]["id"]
  end

  def test_ai_generate_workflow_calls_model_bridge_after_approval
    File.write(
      File.join(@directory, "ai.yml"),
      <<~YAML
        name: ai
        version: 1
        steps:
          - id: answer
            uses: ai.generate
            with:
              provider: gemini
              model: test-model
              prompt: Say hello
      YAML
    )
    loader = RubyOrchestrator::WorkflowLoader.new(directory: @directory)
    model_bridge = Object.new
    model_bridge.define_singleton_method(:generate) do |**options|
      raise "wrong prompt" unless options[:messages].first["content"] == "Say hello"

      "Hello from AI"
    end
    approval_requests = []
    runner = RubyOrchestrator::WorkflowRunner.new(
      loader: loader,
      model_bridge: model_bridge,
      approval_gate: lambda { |**request|
        approval_requests << request
        true
      }
    )

    result = runner.call(RubyOrchestrator::Run.new(workflow: "ai"))

    assert_equal "Hello from AI", result["steps"]["answer"]
    assert_equal :medium, approval_requests.first[:risk]
  end
end
