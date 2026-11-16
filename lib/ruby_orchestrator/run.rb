require "securerandom"

module RubyOrchestrator
  class Run
    STATUSES = %i[pending running succeeded failed].freeze

    class InvalidTransitionError < StandardError; end

    attr_reader :id, :workflow, :input, :status, :result, :error,
                :created_at, :started_at, :finished_at

    def initialize(workflow:, input: {}, id: SecureRandom.uuid)
      raise ArgumentError, "workflow must be a non-empty String" unless workflow.is_a?(String) && !workflow.strip.empty?
      raise ArgumentError, "input must be a Hash" unless input.is_a?(Hash)
      raise ArgumentError, "id must be a non-empty String" unless id.is_a?(String) && !id.empty?

      @id = id
      @workflow = workflow
      @input = input.dup.freeze
      @status = :pending
      @created_at = Time.now.utc
    end

    def start!
      transition_from!(:pending)
      @status = :running
      @started_at = Time.now.utc
      self
    end

    def succeed!(result: nil)
      transition_from!(:running)
      @status = :succeeded
      @result = result
      @finished_at = Time.now.utc
      self
    end

    def fail!(error:)
      transition_from!(:running)
      raise ArgumentError, "error must be an Exception" unless error.is_a?(Exception)

      @status = :failed
      @error = error
      @finished_at = Time.now.utc
      self
    end

    private

    def transition_from!(expected_status)
      return if @status == expected_status

      raise InvalidTransitionError, "cannot transition from #{@status} (expected #{expected_status})"
    end
  end
end
