# frozen_string_literal: true

require_relative 'schema'

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
  end
end
