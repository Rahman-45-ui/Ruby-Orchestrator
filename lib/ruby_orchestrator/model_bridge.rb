require_relative "models/providers"

module RubyOrchestrator
  class ModelBridge
    PROVIDER_ALIASES = {
      "gemini" => "gemini",
      "gamini" => "gemini",
      "google" => "gemini",
      "google gemini" => "gemini",
      "claude" => "claude",
      "cloude" => "claude",
      "anthropic" => "claude",
      "anthropic claude" => "claude",
      "chatgpt" => "chatgpt",
      "openai" => "chatgpt",
      "grok" => "grok",
      "xai" => "grok",
      "meta_muse" => "meta_muse",
      "meta-muse" => "meta_muse",
      "meta muse" => "meta_muse"
    }.freeze

    attr_reader :supported_providers

    def initialize(transport: Models::NetHTTPTransport.new)
      @providers = {
        "gemini" => Models::GeminiProvider.new(transport: transport),
        "claude" => Models::AnthropicProvider.new(transport: transport),
        "chatgpt" => Models::OpenAIProvider.new(transport: transport),
        "grok" => Models::XAIProvider.new(transport: transport),
        "meta_muse" => Models::MetaMuseProvider.new(transport: transport)
      }
      @supported_providers = @providers.keys.freeze
    end

    def generate(provider:, model:, messages:, system: nil, max_tokens: 1024, temperature: nil)
      provider_name = PROVIDER_ALIASES[provider.to_s.downcase]
      unless provider_name
        raise ArgumentError,
              "unsupported provider #{provider.inspect}; supported providers: #{@supported_providers.join(', ')}"
      end
      unless model.is_a?(String) && !model.strip.empty?
        raise ArgumentError, "model must be a non-empty String"
      end
      unless max_tokens.is_a?(Integer) && max_tokens.positive?
        raise ArgumentError, "max_tokens must be a positive Integer"
      end
      unless temperature.nil? || (temperature.is_a?(Numeric) && temperature.between?(0, 1))
        raise ArgumentError, "temperature must be between 0 and 1"
      end
      unless system.nil? || system.is_a?(String)
        raise ArgumentError, "system must be a String"
      end

      normalized_messages = normalize_messages(messages)
      @providers.fetch(provider_name).generate(
        model: model,
        messages: normalized_messages,
        system: system,
        max_tokens: max_tokens,
        temperature: temperature
      )
    end

    private

    def normalize_messages(messages)
      unless messages.is_a?(Array) && !messages.empty?
        raise ArgumentError, "messages must be a non-empty Array"
      end

      messages.map.with_index do |message, index|
        unless message.is_a?(Hash)
          raise ArgumentError, "message at index #{index} must be a Hash"
        end

        role = message["role"] || message[:role]
        content = message["content"] || message[:content]
        unless %w[user assistant].include?(role)
          raise ArgumentError, "message role at index #{index} must be user or assistant"
        end
        unless content.is_a?(String) && !content.empty?
          raise ArgumentError, "message content at index #{index} must be a non-empty String"
        end

        { "role" => role, "content" => content }
      end
    end
  end
end
