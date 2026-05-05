# frozen_string_literal: true

require_relative 'attribute'
require_relative 'content_match'
require_relative 'errors'
require_relative 'fragment'
require_relative 'mark'
require_relative 'utils'

module ProseMirrorValidator
  class NodeType
    attr_reader :name, :schema, :spec, :groups, :attrs
    attr_accessor :content_match, :inline_content, :mark_set

    def initialize(name, schema, spec)
      @name = name
      @schema = schema
      @spec = Utils.normalize_hash(spec)
      @groups = @spec.fetch('group', '').split
      @attrs = build_attrs
      @content_match = nil
      @inline_content = nil
      @mark_set = nil
      @block = !(@spec['inline'] || name == 'text')
      @text = name == 'text'
      @default_attrs = build_default_attrs
    end

    def block?
      @block
    end

    def inline?
      !block?
    end

    def text?
      @text
    end

    def textblock?
      block? && inline_content?
    end

    def inline_content?
      !!inline_content
    end

    def leaf?
      content_match.equal?(ContentMatch.empty)
    end

    def atom?
      leaf? || !!spec['atom']
    end

    def in_group?(group)
      groups.include?(group)
    end

    def required_attrs?
      attrs.any? { |_name, attr| attr.required? }
    end

    def compatible_content?(other)
      equal?(other) || content_match.compatible?(other.content_match)
    end

    def create(attrs = nil, content = nil, marks = nil)
      raise Error, "NodeType.create can't construct text nodes" if text?

      Node.new(self, compute_attrs(attrs), Fragment.from(content), Mark.normalize_set(marks))
    end

    def create_checked(attrs = nil, content = nil, marks = nil)
      fragment = Fragment.from(content)
      check_content!(fragment)
      Node.new(self, compute_attrs(attrs), fragment, Mark.normalize_set(marks))
    end

    def valid_content?(content)
      result = content_match.match_fragment(content)
      return false unless result&.valid_end?

      content.each.all? { |child| allows_marks?(child.marks) }
    end

    def check_content!(content)
      return if valid_content?(content)

      raise ValidationError, "Invalid content for node #{name}: #{content.to_s.slice(0, 50)}"
    end

    def check_attrs!(values)
      normalized_values = Utils.normalize_hash(values)

      check_supported_attrs!(normalized_values)

      attrs.each do |attr_name, attr|
        attr.validate!(normalized_values[attr_name])
      end
    end

    def check_supported_attrs!(values)
      normalized_values = Utils.normalize_hash(values)

      normalized_values.each_key do |attr_name|
        next if attrs.key?(attr_name)

        raise ValidationError, "Unsupported attribute #{attr_name} for node of type #{name}"
      end
    end

    def allows_mark_type?(mark_type)
      mark_set.nil? || mark_set.include?(mark_type)
    end

    def allows_marks?(marks)
      mark_set.nil? || marks.all? { |mark| allows_mark_type?(mark.type) }
    end

    def compute_attrs(values)
      return @default_attrs if values.nil? && @default_attrs

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

    private

    def build_attrs
      Utils.normalize_hash(spec['attrs']).each_with_object({}) do |(attr_name, attr_spec), result|
        result[attr_name] = Attribute.new(name, attr_name, attr_spec)
      end
    end

    def build_default_attrs
      attrs.each_with_object({}) do |(attr_name, attr), result|
        return nil if attr.required?

        result[attr_name] = attr.default
      end.freeze
    end
  end
end
