require_relative "workflow_loader"

module RubyOrchestrator
  class WorkflowRunner
    class WorkflowExecutionError < StandardError; end
    class ApprovalRequiredError < WorkflowExecutionError; end
    class ApprovalDeniedError < WorkflowExecutionError; end

    Handler = Struct.new(:callable, :risk, keyword_init: true)

    def self.handler(callable:, risk:)
      Handler.new(callable: callable, risk: risk)
    end

    def initialize(loader: WorkflowLoader.new, handlers: {}, approval_gate: nil, model_bridge: nil)
      raise ArgumentError, "loader must respond to load" unless loader.respond_to?(:load)
      raise ArgumentError, "handlers must be a Hash" unless handlers.is_a?(Hash)
      if approval_gate && !approval_gate.respond_to?(:call)
        raise ArgumentError, "approval_gate must respond to call"
      end
      if model_bridge && !model_bridge.respond_to?(:generate)
        raise ArgumentError, "model_bridge must respond to generate"
      end

      @loader = loader
      @handlers = { "core.echo" => Handler.new(callable: method(:echo), risk: :low) }
      if model_bridge
        @model_bridge = model_bridge
        @handlers["ai.generate"] = Handler.new(
          callable: method(:generate_with_model_bridge),
          risk: :medium
        )
      end
      handlers.each do |name, handler|
        unless name.is_a?(String) && !name.strip.empty?
          raise ArgumentError, "handler names must be non-empty Strings"
        end
        unless handler.is_a?(Handler) && handler.callable.respond_to?(:call)
          raise ArgumentError, "handler #{name.inspect} must be registered with WorkflowRunner.handler"
        end
        unless %i[low medium high].include?(handler.risk)
          raise ArgumentError, "handler #{name.inspect} risk must be :low, :medium, or :high"
        end
        if @handlers.key?(name)
          raise ArgumentError, "handler #{name.inspect} is reserved by the orchestrator"
        end

        @handlers[name] = handler
      end
      @approval_gate = approval_gate
    end

    def call(run)
      handler_risks = @handlers.each_with_object({}) do |(name, handler), risks|
        risks[name] = handler.risk.to_s
      end
      definition = @loader.load(run.workflow, handler_risks: handler_risks)
      outputs = {}

      definition["steps"].each do |step|
        handler = @handlers.fetch(step["uses"])
        approve!(run, step, handler) if step.fetch("approval_required")
        outputs[step["id"]] = handler.callable.call(
          step: step,
          input: run.input,
          outputs: outputs.dup
        )
      end

      { "workflow" => definition["name"], "steps" => outputs }
    rescue WorkflowLoader::WorkflowError => error
      raise WorkflowExecutionError, error.message
    end

    private

    def approve!(run, step, handler)
      unless @approval_gate
        raise ApprovalRequiredError,
              "step #{step['id'].inspect} requires approval for risk #{handler.risk}"
      end

      approved = @approval_gate.call(
        workflow: run.workflow,
        step: step,
        risk: handler.risk
      )
      return if approved == true

      raise ApprovalDeniedError, "approval denied for step #{step['id'].inspect}"
    end

    def echo(step:, input:, outputs:)
      step.fetch("with", {}).fetch("message", input)
    end

    def generate_with_model_bridge(step:, input:, outputs:)
      options = step.fetch("with", {})
      messages = options["messages"] || [{ "role" => "user", "content" => options.fetch("prompt") }]
      @model_bridge.generate(
        provider: options.fetch("provider"),
        model: options.fetch("model"),
        messages: messages,
        system: options["system"],
        max_tokens: options.fetch("max_tokens", 1024),
        temperature: options["temperature"]
      )
    rescue KeyError => error
      raise WorkflowExecutionError, "ai.generate requires #{error.key.inspect}"
    end
  end
end
