require "json"

begin
  require "workflow_safety"
rescue LoadError => error
  raise LoadError,
        "Rust workflow safety extension is not built; run `rake compile` (#{error.message})"
end

module RubyOrchestrator
  class WorkflowLoader
    class WorkflowError < StandardError; end
    class WorkflowNotFoundError < WorkflowError; end

    def initialize(directory: File.expand_path("../../workflows", __dir__))
      @directory = File.expand_path(directory)
    end

    def load(name, handler_risks: { "core.echo" => "low" })
      unless handler_risks.is_a?(Hash) &&
             handler_risks.all? { |handler, risk| handler.is_a?(String) && risk.is_a?(String) }
        raise ArgumentError, "handler_risks must map String handler names to String risk levels"
      end

      response = JSON.parse(
        WorkflowSafety.validate_file(@directory, name, JSON.generate(handler_risks))
      )
      return response.fetch("workflow") if response.fetch("ok")

      message = response.fetch("error")
      if message.start_with?("workflow not found:")
        raise WorkflowNotFoundError, message
      end

      raise WorkflowError, message
    rescue JSON::ParserError, KeyError => error
      raise WorkflowError, "Rust workflow validator returned an invalid response: #{error.message}"
    end
  end
end
