# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "larian_pak"
  spec.version       = "0.1.0"
  spec.authors       = ["James Cook"]
  spec.email         = ["jcook.rubyist@gmail.com"]

  spec.summary       = "Parse and create Larian Studios PAK files"
  spec.description   = "A pure Ruby library for reading and writing PAK archive files " \
                       "used by Larian Studios games (Divinity: Original Sin 1/2, Baldur's Gate 3)"
  spec.homepage      = "https://github.com/jamescook/larian-pak"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files         = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "extlz4", "~> 0.3"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
