# frozen_string_literal: true

Gem::Specification.new do |specification|
  specification.name = 'prosemirror-validator'
  specification.version = '0.1.0'
  specification.authors = ['Productboard']
  specification.email = ['opensource@productboard.com']

  specification.summary = 'Validation-only Ruby helpers for ProseMirror documents.'
  specification.description = 'A Ruby gem for validating ProseMirror document payloads against schema specs.'
  specification.homepage = 'https://github.com/productboard/prosemirror-validator'
  specification.license = 'MIT'
  specification.required_ruby_version = '>= 3.3'

  specification.metadata['allowed_push_host'] = 'https://rubygems.org'
  specification.metadata['changelog_uri'] = "#{specification.homepage}/blob/main/CHANGELOG.md"
  specification.metadata['homepage_uri'] = specification.homepage
  specification.metadata['rubygems_mfa_required'] = 'true'
  specification.metadata['source_code_uri'] = "#{specification.homepage}/tree/main"

  specification.files = Dir.glob(
    %w[
      CHANGELOG.md
      LICENSE.txt
      README.md
      lib/**/*.rb
    ]
  )
  specification.bindir = 'exe'
  specification.executables = []
  specification.require_paths = ['lib']
end
