# frozen_string_literal: true

require_relative 'schema'
require_relative 'updates'

module ProseMirrorValidator
  module Validator
    module_function

    def validate!(document, schema_spec)
      Schema.from_spec(schema_spec).validate_document!(document)
    end

    def valid?(document, schema_spec)
      validate!(document, schema_spec)
      true
    rescue Error
      false
    end

    def validate_steps!(document:, steps:, schema_spec:)
      Updates.validate_steps!(document: document, steps: steps, schema_spec: schema_spec)
    end

    def valid_steps?(document:, steps:, schema_spec:)
      Updates.valid_steps?(document: document, steps: steps, schema_spec: schema_spec)
    end
  end
end
