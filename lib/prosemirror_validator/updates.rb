# frozen_string_literal: true

require_relative 'schema'
require_relative 'step'

module ProseMirrorValidator
  module Updates
    module_function

    def validate_steps!(document:, steps:, schema_spec: nil, schema: nil)
      schema ||= Schema.from_spec(schema_spec)
      current_doc = document.is_a?(Node) ? document : schema.node_from_json(document)
      current_doc.check!

      steps.each do |step_json|
        step = Step.from_json(schema, step_json)
        result = step.apply(current_doc)
        raise TransformError, result.failed if result.failed

        current_doc = result.doc.check!
      end

      current_doc
    end

    def valid_steps?(document:, steps:, schema_spec: nil, schema: nil)
      validate_steps!(document: document, steps: steps, schema_spec: schema_spec, schema: schema)
      true
    rescue Error
      false
    end
  end
end
