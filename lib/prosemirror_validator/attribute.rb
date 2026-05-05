# frozen_string_literal: true

require_relative 'errors'
require_relative 'utils'

module ProseMirrorValidator
  class Attribute
    UNDEFINED = Object.new.freeze

    attr_reader :default

    def initialize(type_name, name, spec)
      @type_name = type_name
      @name = name
      @spec = Utils.normalize_hash(spec)
      @has_default = @spec.key?('default')
      @default = @spec['default']
      @validator = build_validator(@spec['validate'])
    end

    def default?
      @has_default
    end

    def required?
      !default?
    end

    def validate!(value)
      @validator&.call(value)
    end

    private

    def build_validator(validator)
      return validator if validator.respond_to?(:call)
      return unless validator.is_a?(String)

      expected_types = validator.split('|')
      lambda do |value|
        actual_type = primitive_type(value)
        next if expected_types.include?(actual_type)

        raise ValidationError,
              "Expected value of type #{expected_types.join(',')} for attribute #{@name} on type #{@type_name}, " \
              "got #{actual_type}"
      end
    end

    def primitive_type(value)
      case value
      when nil
        'null'
      when true, false
        'boolean'
      when Numeric
        'number'
      when String
        'string'
      when UNDEFINED
        'undefined'
      else
        value.class.name
      end
    end
  end
end
