# frozen_string_literal: true

require_relative 'errors'
require_relative 'utils'

module ProseMirrorValidator
  class Mark
    NONE = [].freeze

    attr_reader :type, :attrs

    def initialize(type, attrs)
      @type = type
      @attrs = attrs.freeze
    end

    def add_to_set(set)
      copy = nil
      placed = false

      set.each_with_index do |other, index|
        return set if eq?(other)

        if type.excludes?(other.type)
          copy ||= set.slice(0, index)
        elsif other.type.excludes?(type)
          return set
        else
          if !placed && other.type.rank > type.rank
            copy ||= set.slice(0, index)
            copy.push(self)
            placed = true
          end
          copy&.push(other)
        end
      end

      copy ||= set.dup
      copy.push(self) unless placed
      copy.freeze
    end

    def eq?(other)
      equal?(other) || (type.equal?(other.type) && Utils.deep_equal?(attrs, other.attrs))
    end

    def to_json_object
      object = { 'type' => type.name }
      object['attrs'] = attrs unless attrs.empty?
      object
    end

    def self.from_json(schema, json)
      raise ValidationError, 'Invalid input for Mark.fromJSON' if json.nil?

      type_name = Utils.fetch_value(json, 'type')
      type = schema.marks[type_name]
      raise ValidationError, "There is no mark type #{type_name} in this schema" unless type

      type.check_supported_attrs!(Utils.fetch_value(json, 'attrs'))
      mark = type.create(Utils.fetch_value(json, 'attrs'))
      type.check_attrs!(mark.attrs)
      mark
    end

    def self.same_set?(left, right)
      return true if left.equal?(right)
      return false unless left.length == right.length

      left.zip(right).all? { |a, b| a.eq?(b) }
    end

    def self.normalize_set(marks)
      return NONE if marks.nil? || (marks.is_a?(Array) && marks.empty?)
      return [marks].freeze if marks.is_a?(Mark)

      marks.sort_by { |mark| mark.type.rank }.freeze
    end
  end
end
