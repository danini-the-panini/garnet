lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "ruby_ruby/version"

Gem::Specification.new do |spec|
  spec.name          = "ruby_ruby"
  spec.version       = RubyRuby::VERSION
  spec.authors       = ["Daniel Smith"]
  spec.email         = ["jellymann@gmail.com"]

  spec.summary       = %q{Ruby written in Ruby}
  spec.description   = %q{The Ruby programming language, written in the Ruby programming language.}
  spec.homepage      = "https://www.github.com/jellmann/ruby_ruby"
  spec.license       = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://www.github.com/jellmann/ruby_ruby"
  spec.metadata["changelog_uri"] = "https://www.github.com/jellmann/ruby_ruby"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ruby_parser", "~> 3.14"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
