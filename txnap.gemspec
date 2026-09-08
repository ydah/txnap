# frozen_string_literal: true

require_relative "lib/txnap/version"

Gem::Specification.new do |spec|
  spec.name = "txnap"
  spec.version = Txnap::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Detect non-database idle gaps inside Active Record transactions"
  spec.description = "Measures time spent away from the database while a real Active Record transaction is open."
  spec.homepage = "https://github.com/ydah/txnap"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ site/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.2", "< 8.1"

  spec.add_development_dependency "appraisal", "~> 2.5"
  spec.add_development_dependency "benchmark-ips", "~> 2.14"
  spec.add_development_dependency "irb"
  spec.add_development_dependency "pg", "~> 1.5"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "sqlite3", ">= 2.1"
  spec.add_development_dependency "standard", "~> 1.0"
end
