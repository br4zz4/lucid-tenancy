require_relative "lib/lucid/tenancy/version"

Gem::Specification.new do |spec|
  spec.name = "lucid-tenancy"
  spec.version = Lucid::Tenancy::VERSION
  spec.authors = ["Brazza Labs"]
  spec.summary = "Multi-tenancy for Rails on PostgreSQL, one schema per tenant"
  spec.description = "Lucid::Tenancy isolates each tenant in its own PostgreSQL schema and switches between them " \
                     "in requests, jobs, the console and migrations."
  spec.homepage = "https://github.com/br4zz4/lucid-tenancy"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "docs/**/*.md", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.2", "< 9.0"
  spec.add_dependency "activesupport", ">= 7.2", "< 9.0"
  spec.add_dependency "railties", ">= 7.2", "< 9.0"
end
