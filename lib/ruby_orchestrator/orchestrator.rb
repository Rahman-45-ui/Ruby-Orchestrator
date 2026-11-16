require_relative "run"

module RubyOrchestrator
  class Orchestrator
    def initialize(workflow_runner:, run_store: nil)
      raise ArgumentError, "workflow_runner must respond to call" unless workflow_runner.respond_to?(:call)
      if run_store && !run_store.respond_to?(:save)
        raise ArgumentError, "run_store must respond to save"
      end

      @workflow_runner = workflow_runner
      @run_store = run_store
    end

    def execute(workflow:, input: {})
      run = Run.new(workflow: workflow, input: input)
      @run_store&.save(run)
      run.start!
      @run_store&.save(run)

      begin
        result = @workflow_runner.call(run)
        run.succeed!(result: result)
        @run_store&.save(run)
        run
      rescue StandardError => error
        if run.status == :running
          run.fail!(error: error)
          @run_store&.save(run)
        end
        raise
      end
    end
  end
end
