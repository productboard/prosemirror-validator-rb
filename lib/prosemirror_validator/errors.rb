# frozen_string_literal: true

module ProseMirrorValidator
  class Error < StandardError; end
  class SchemaError < Error; end
  class ContentExpressionError < SchemaError; end
  class ValidationError < Error; end
end
