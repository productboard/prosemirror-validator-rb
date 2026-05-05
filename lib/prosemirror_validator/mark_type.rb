# frozen_string_literal: true

require_relative 'attribute'
require_relative 'mark'
require_relative 'utils'

module ProseMirrorValidator
  class MarkType
    attr_reader :name, :rank, :schema, :spec, :attrs
    attr_accessor :excluded

    def initialize(name, rank, schema, spec)
      @name = name
      @rank = rank
      @schema = schema
      @spec = Utils.normalize_hash(spec)
      @attrs = build_attrs
      @excluded = nil
      @instance = default_attrs ? Mark.new(self, default_attrs) : nil
    end

    def create(attrs = nil)
      return @instance if attrs.nil? && @instance

      Mark.new(self, compute_attrs(attrs))
    end

    def check_attrs!(values)
      attrs.each_key do |name|
        attrs[name].validate!(values[name])
      end

      check_supported_attrs!(values)
    end

    def check_supported_attrs!(values)
      Utils.normalize_hash(values).each_key do |name|
        next if attrs.key?(name)

        raise ValidationError, "Unsupported attribute #{name} for mark of type #{self.name}"
      end
    end

    def excludes?(other)
      excluded.include?(other)
    end

    private

    def build_attrs
      Utils.normalize_hash(spec['attrs']).each_with_object({}) do |(attr_name, attr_spec), result|
        result[attr_name] = Attribute.new(name, attr_name, attr_spec)
      end
    end

    def default_attrs
      return @default_attrs if defined?(@default_attrs)

      @default_attrs = {}
      attrs.each do |attr_name, attr|
        return @default_attrs = nil if attr.required?

        @default_attrs[attr_name] = attr.default
      end
      @default_attrs.freeze
    end

    def compute_attrs(values)
      normalized_values = Utils.normalize_hash(values)
      built = {}

      attrs.each do |attr_name, attr|
        given = normalized_values.key?(attr_name) ? normalized_values[attr_name] : Attribute::UNDEFINED
        if given.equal?(Attribute::UNDEFINED)
          raise ValidationError, "No value supplied for attribute #{attr_name}" unless attr.default?

          given = attr.default
        end
        built[attr_name] = given
      end

      built.freeze
    end
  end
end
