require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../../lib/ruby_orchestrator/workflow_loader"

class WorkflowLoaderSpec < Minitest::Test
  def setup
    @directory = Dir.mktmpdir
    @loader = RubyOrchestrator::WorkflowLoader.new(directory: @directory)
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_loads_valid_workflow
    write_workflow("sample.yml", <<~YAML)
      name: sample
      version: 1
      steps:
        - id: greet
          uses: core.echo
          with:
            message: hello
    YAML

    workflow = @loader.load("sample")

    assert_equal "sample", workflow["name"]
    assert_equal "hello", workflow["steps"].first["with"]["message"]
  end

  def test_rejects_invalid_workflow
    write_workflow("invalid.yml", "name: invalid\nversion: 1\nsteps: []\n")

    error = assert_raises(RubyOrchestrator::WorkflowLoader::WorkflowError) do
      @loader.load("invalid")
    end

    assert_match(/non-empty Array/, error.message)
  end

  def test_rejects_yaml_object_tags
    write_workflow("unsafe.yml", <<~YAML)
      --- !ruby/object:Object {}
    YAML

    assert_raises(RubyOrchestrator::WorkflowLoader::WorkflowError) do
      @loader.load("unsafe")
    end
  end

  def test_rejects_paths_outside_workflow_directory
    assert_raises(RubyOrchestrator::WorkflowLoader::WorkflowError) do
      @loader.load("../outside")
    end
  end

  def test_rejects_unallowlisted_handler
    write_workflow("custom.yml", <<~YAML)
      name: custom
      version: 1
      steps:
        - id: call
          uses: shell.exec
    YAML

    error = assert_raises(RubyOrchestrator::WorkflowLoader::WorkflowError) do
      @loader.load("custom", handler_risks: { "core.echo" => "low" })
    end

    assert_match(/not allowlisted/, error.message)
  end

  private

  def write_workflow(filename, content)
    File.write(File.join(@directory, filename), content)
  end
end
