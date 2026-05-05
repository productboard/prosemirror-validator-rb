# frozen_string_literal: true

require_relative 'errors'

module ProseMirrorValidator
  class Fragment
    attr_reader :content, :size

    def initialize(content, size = nil)
      @content = content.freeze
      @size = size || content.sum(&:node_size)
    end

    def child_count
      content.length
    end

    def child(index)
      found = content[index]
      raise ValidationError, "Index #{index} out of range for #{self}" unless found

      found
    end

    def each(&)
      content.each(&)
    end

    def append(other)
      return self if other.empty?
      return other if size.zero?

      Fragment.new(content + other.content)
    end

    def to_json_object
      content.empty? ? nil : content.map(&:to_json_object)
    end

    def to_s
      "<#{content.join(', ')}>"
    end

    def self.from_json(schema, value)
      return empty if value.nil? || value == false
      raise ValidationError, 'Invalid input for Fragment.fromJSON' unless value.is_a?(Array)

      from_array(value.map { |json| schema.node_from_json(json) })
    end

    def self.from(value)
      return empty if value.nil?
      return value if value.is_a?(Fragment)
      return from_array(value) if value.is_a?(Array)
      return new([value], value.node_size) if value.respond_to?(:node_size)

      raise ValidationError, "Can not convert #{value} to a Fragment"
    end

    def self.from_array(nodes)
      return empty if nodes.empty?

      joined = nil
      size = 0

      nodes.each_with_index do |node, index|
        size += node.node_size
        if index.positive? && node.text? && nodes[index - 1].same_markup?(node)
          joined ||= nodes.slice(0, index)
          joined[-1] = joined[-1].with_text(joined[-1].text + node.text)
        elsif joined
          joined << node
        end
      end

      new(joined || nodes, size)
    end

    def self.empty
      @empty ||= new([], 0)
    end
  end
end
