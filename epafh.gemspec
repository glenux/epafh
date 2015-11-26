# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'epafh/constants'

Gem::Specification.new do |spec|
  spec.name          = "epafh"
  spec.version       = Epafh::VERSION
  spec.authors       = ["Glenn Y. Rolland"]
  spec.email         = ["glenux@glenux.net"]

  spec.summary       = %q{A handy tool to extract emails and URLs from an IMAP account.}
  spec.description   = %q{A handy tool to extract emails and URLs from an IMAP account.}
  spec.homepage      = "https://github.com/glenux/epafh"
  spec.license       = "LGPL-3"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_runtime_dependency "mail", "~> 2.6.3"
  spec.add_runtime_dependency "json"
  spec.add_runtime_dependency "thor"
  spec.add_runtime_dependency "mechanize"
  spec.add_runtime_dependency "colorize"
  spec.add_runtime_dependency "hash_validator"
  spec.add_runtime_dependency "pry"
  spec.add_runtime_dependency "pry-rescue"
  spec.add_runtime_dependency "highline"
end

