require "json"
require "net/http"
require "openssl"
require "uri"

module RubyOrchestrator
  module Models
    class ProviderError < StandardError; end
    class ConfigurationError < StandardError; end

    class NetHTTPTransport
      def initialize(open_timeout: 10, read_timeout: 60)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def post(uri, headers, body)
        request = Net::HTTP::Post.new(uri.request_uri)
        headers.each { |name, value| request[name] = value }
        request.body = body
        response = Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: true,
          open_timeout: @open_timeout,
          read_timeout: @read_timeout,
          verify_mode: OpenSSL::SSL::VERIFY_PEER
        ) { |http| http.request(request) }
        [response.code.to_i, response.body]
      end
    end

    class BaseProvider
      def initialize(transport:, api_key_env:)
        @transport = transport
        @api_key_env = api_key_env
      end

      private

      def api_key
        value = ENV[@api_key_env]
        unless value.is_a?(String) && !value.strip.empty?
          raise ConfigurationError, "API key environment variable #{@api_key_env} is not set"
        end

        value
      end

      def post_json(endpoint, headers, payload)
        uri = URI.parse(endpoint)
        unless uri.is_a?(URI::HTTPS) && uri.host && uri.userinfo.nil? && uri.fragment.nil?
          raise ConfigurationError, "provider endpoint must be a valid HTTPS URL"
        end

        headers = headers.merge("Content-Type" => "application/json")
        status, response_body = @transport.post(uri, headers, JSON.generate(payload))
        unless status.between?(200, 299)
          raise ProviderError, "provider request failed with HTTP #{status}"
        end

        JSON.parse(response_body)
      rescue JSON::ParserError
        raise ProviderError, "provider returned invalid JSON"
      rescue URI::InvalidURIError
        raise ConfigurationError, "provider endpoint is invalid"
      end
    end

    class ResponsesProvider < BaseProvider
      def initialize(transport:, api_key_env:, endpoint:)
        super(transport: transport, api_key_env: api_key_env)
        @endpoint = endpoint
      end

      def generate(model:, messages:, system:, max_tokens:, temperature:)
        payload = {
          "model" => model,
          "input" => messages,
          "max_output_tokens" => max_tokens
        }
        payload["instructions"] = system if system
        payload["temperature"] = temperature unless temperature.nil?

        response = post_json(
          endpoint,
          { "Authorization" => "Bearer #{api_key}" },
          payload
        )
        output = response["output"]
        unless output.is_a?(Array)
          raise ProviderError, "provider response did not contain output messages"
        end

        text = output.flat_map do |item|
          next [] unless item.is_a?(Hash) && item["type"] == "message"

          content = item["content"]
          next [] unless content.is_a?(Array)

          content.select { |part| part.is_a?(Hash) && part["type"] == "output_text" }
                 .map { |part| part["text"] }.select { |part| part.is_a?(String) }
        end.join
        raise ProviderError, "provider returned no text output" if text.empty?

        text
      end

      private

      def endpoint
        @endpoint.respond_to?(:call) ? @endpoint.call : @endpoint
      end
    end

    class GeminiProvider < BaseProvider
      def initialize(transport:)
        super(transport: transport, api_key_env: "GEMINI_API_KEY")
      end

      def generate(model:, messages:, system:, max_tokens:, temperature:)
        contents = messages.map do |message|
          {
            "role" => message["role"] == "assistant" ? "model" : "user",
            "parts" => [{ "text" => message["content"] }]
          }
        end
        payload = { "contents" => contents }
        payload["systemInstruction"] = { "parts" => [{ "text" => system }] } if system
        generation_config = { "maxOutputTokens" => max_tokens }
        generation_config["temperature"] = temperature unless temperature.nil?
        payload["generationConfig"] = generation_config

        endpoint = "https://generativelanguage.googleapis.com/v1beta/models/#{URI.encode_www_form_component(model)}:generateContent"
        response = post_json(
          endpoint,
          { "x-goog-api-key" => api_key },
          payload
        )
        candidates = response["candidates"]
        candidate = candidates.first if candidates.is_a?(Array)
        parts = candidate.dig("content", "parts") if candidate.is_a?(Hash)
        text = parts.select { |part| part.is_a?(Hash) && part["text"].is_a?(String) }
                    .map { |part| part["text"] }.join if parts.is_a?(Array)
        return text unless text.nil? || text.empty?

        raise ProviderError, "provider returned no text (the response may have been safety-filtered)"
      end
    end

    class AnthropicProvider < BaseProvider
      def initialize(transport:)
        super(transport: transport, api_key_env: "ANTHROPIC_API_KEY")
      end

      def generate(model:, messages:, system:, max_tokens:, temperature:)
        payload = {
          "model" => model,
          "messages" => messages,
          "max_tokens" => max_tokens
        }
        payload["system"] = system if system
        payload["temperature"] = temperature unless temperature.nil?
        response = post_json(
          "https://api.anthropic.com/v1/messages",
          {
            "x-api-key" => api_key,
            "anthropic-version" => "2023-06-01"
          },
          payload
        )
        content = response["content"]
        unless content.is_a?(Array)
          raise ProviderError, "provider response did not contain message content"
        end

        text = content.select { |block| block.is_a?(Hash) && block["type"] == "text" }
                      .map { |block| block["text"] }.select { |part| part.is_a?(String) }.join
        raise ProviderError, "provider returned no text content" if text.empty?

        text
      end
    end

    class OpenAIProvider < ResponsesProvider
      def initialize(transport:)
        super(
          transport: transport,
          api_key_env: "OPENAI_API_KEY",
          endpoint: "https://api.openai.com/v1/responses"
        )
      end
    end

    class XAIProvider < ResponsesProvider
      def initialize(transport:)
        super(
          transport: transport,
          api_key_env: "XAI_API_KEY",
          endpoint: "https://api.x.ai/v1/responses"
        )
      end
    end

    class MetaMuseProvider < ResponsesProvider
      def initialize(transport:)
        super(
          transport: transport,
          api_key_env: "META_MUSE_API_KEY",
          endpoint: lambda {
            endpoint = ENV["META_MUSE_API_URL"]
            unless endpoint.is_a?(String) && !endpoint.strip.empty?
              raise ConfigurationError,
                    "META_MUSE_API_URL must point to a Responses-compatible HTTPS endpoint"
            end

            endpoint
          }
        )
      end
    end
  end
end
