require "fileutils"
require "rake"
require "rbconfig"

ROOT = __dir__
RUST_MANIFEST = File.join(ROOT, "rust", "workflow_safety", "Cargo.toml")
RUST_TARGET = File.join(ROOT, "rust", "workflow_safety", "target", "release")
RUST_LIBRARY = case RbConfig::CONFIG["host_os"]
               when /darwin/
                 File.join(RUST_TARGET, "libworkflow_safety.dylib")
               when /mswin|mingw/
                 File.join(RUST_TARGET, "workflow_safety.dll")
               else
                 File.join(RUST_TARGET, "libworkflow_safety.so")
               end
EXTENSION = File.join(ROOT, "lib", "workflow_safety.#{RbConfig::CONFIG["DLEXT"]}")

desc "Build the Rust workflow safety extension"
task :compile do
  sh "cargo", "build", "--release", "--manifest-path", RUST_MANIFEST
  FileUtils.cp(RUST_LIBRARY, EXTENSION)
end

desc "Run the test suite (compiles the Rust extension first)"
task test: :compile do
  Dir[File.join(ROOT, "spec", "**", "*_spec.rb")].sort.each do |file|
    ruby "-I#{File.join(ROOT, "lib")}", file
  end
end

task default: :test
