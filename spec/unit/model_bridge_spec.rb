require "minitest/autorun"
require_relative "../../lib/ruby_orchestrator/model_bridge"

class ModelBridgeSpec < Minitest::Test
  class FakeTransport
    attr_reader :request

    def initialize(response)
      @response = response
    end

    def post(uri, headers, body)
      @request = { uri: uri, headers: headers, body: JSON.parse(body) }
      @response
    end
  end

  def test_sends_openai_responses_request
    transport = FakeTransport.new(
      [200, JSON.generate("output" => [{ "type" => "message", "content" => [{ "type" => "output_text", "text" => "hello" }] }])]
    )
    with_env("OPENAI_API_KEY" => "test-openai-key") do
      result = bridge(transport).generate(
        provider: "ChatGPT",
        model: "test-model",
        system: "Be concise",
        messages: [{ role: "user", content: "Hi" }]
      )

      assert_equal "hello", result
      assert_equal "https://api.openai.com/v1/responses", transport.request[:uri].to_s
      assert_equal "Bearer test-openai-key", transport.request[:headers]["Authorization"]
      assert_equal "Be concise", transport.request[:body]["instructions"]
      assert_equal 1024, transport.request[:body]["max_output_tokens"]
    end
  end

  def test_sends_claude_messages_request
    transport = FakeTransport.new(
      [200, JSON.generate("content" => [{ "type" => "text", "text" => "hello Claude" }])]
    )
    with_env("ANTHROPIC_API_KEY" => "test-claude-key") do
      result = bridge(transport).generate(
        provider: "cloude",
        model: "test-model",
        messages: [{ "role" => "user", "content" => "Hi" }]
      )

      assert_equal "hello Claude", result
      assert_equal "/v1/messages", transport.request[:uri].path
      assert_equal "test-claude-key", transport.request[:headers]["x-api-key"]
      assert_equal 1024, transport.request[:body]["max_tokens"]
    end

  end

  def test_accepts_common_misspellings_for_provider_aliases
    transport = FakeTransport.new(
      [200, JSON.generate("candidates" => [{ "content" => { "parts" => [{ "text" => "hello" }] } }])]
    )
    with_env("GEMINI_API_KEY" => "test-gemini-key") do
      assert_equal "hello", bridge(transport).generate(
        provider: "gamini",
        model: "test-model",
        messages: [{ role: "user", content: "Hi" }]
      )
    end
  end

  def test_sends_gemini_generate_content_request
    transport = FakeTransport.new(
      [200, JSON.generate("candidates" => [{ "content" => { "parts" => [{ "text" => "hello Gemini" }] } }])]
    )
    with_env("GEMINI_API_KEY" => "test-gemini-key") do
      result = bridge(transport).generate(
        provider: "gemini",
        model: "test-model",
        messages: [{ "role" => "user", "content" => "Hi" }]
      )

      assert_equal "hello Gemini", result
      assert_equal "https://generativelanguage.googleapis.com/v1beta/models/test-model:generateContent",
                   transport.request[:uri].to_s
      assert_equal "test-gemini-key", transport.request[:headers]["x-goog-api-key"]
    end
  end

  def test_sends_grok_to_xai_endpoint
    transport = FakeTransport.new(
      [200, JSON.generate("output" => [{ "type" => "message", "content" => [{ "type" => "output_text", "text" => "hello Grok" }] }])]
    )
    with_env("XAI_API_KEY" => "test-xai-key") do
      result = bridge(transport).generate(
        provider: "grok",
        model: "test-model",
        messages: [{ "role" => "user", "content" => "Hi" }]
      )

      assert_equal "hello Grok", result
      assert_equal "https://api.x.ai/v1/responses", transport.request[:uri].to_s
    end
  end

  def test_uses_configured_responses_compatible_endpoint_for_meta_muse
    transport = FakeTransport.new(
      [200, JSON.generate("output" => [{ "type" => "message", "content" => [{ "type" => "output_text", "text" => "hello Muse" }] }])]
    )
    with_env(
      "META_MUSE_API_KEY" => "test-meta-key",
      "META_MUSE_API_URL" => "https://models.example.test/v1/responses"
    ) do
      result = bridge(transport).generate(
        provider: "meta_muse",
        model: "test-model",
        messages: [{ "role" => "user", "content" => "Hi" }]
      )

      assert_equal "hello Muse", result
      assert_equal "https://models.example.test/v1/responses", transport.request[:uri].to_s
      assert_equal [{ "role" => "user", "content" => "Hi" }], transport.request[:body]["input"]
      assert_equal 1024, transport.request[:body]["max_output_tokens"]
    end
  end

  def test_does_not_send_requests_when_api_key_is_missing
    transport = FakeTransport.new([200, "{}"])

    error = with_env("OPENAI_API_KEY" => nil) do
      assert_raises(RubyOrchestrator::Models::ConfigurationError) do
        bridge(transport).generate(
          provider: "openai",
          model: "test-model",
          messages: [{ role: "user", content: "Hi" }]
        )
      end
    end

    assert_match(/OPENAI_API_KEY/, error.message)
    assert_nil transport.request
  end

  def test_rejects_non_https_meta_endpoint
    transport = FakeTransport.new([200, "{}"])

    with_env(
      "META_MUSE_API_KEY" => "test-meta-key",
      "META_MUSE_API_URL" => "http://localhost:3000/v1/chat/completions"
    ) do
      assert_raises(RubyOrchestrator::Models::ConfigurationError) do
        bridge(transport).generate(
          provider: "meta_muse",
          model: "test-model",
          messages: [{ role: "user", content: "Hi" }]
        )
      end
    end
  end

  def test_surfaces_http_failures_without_response_body
    transport = FakeTransport.new([401, '{"error":"invalid API key"}'])
    with_env("OPENAI_API_KEY" => "test-openai-key") do
      error = assert_raises(RubyOrchestrator::Models::ProviderError) do
        bridge(transport).generate(
          provider: "openai",
          model: "test-model",
          messages: [{ role: "user", content: "Hi" }]
        )
      end

      assert_equal "provider request failed with HTTP 401", error.message
      refute_includes error.message, "invalid API key"
    end
  end

  private

  def bridge(transport)
    RubyOrchestrator::ModelBridge.new(transport: transport)
  end

  def with_env(values)
    previous_values = values.each_with_object({}) { |(name, _), previous| previous[name] = ENV[name] }
    values.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    yield
  ensure
    previous_values.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end
end
