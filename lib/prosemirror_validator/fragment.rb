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

    def empty?
      size.zero?
    end

    def first_child
      content.first
    end

    def last_child
      content.last
    end

    def child(index)
      found = content[index]
      raise ValidationError, "Index #{index} out of range for #{self}" unless found

      found
    end

    def maybe_child(index)
      content[index]
    end

    def each(&)
      content.each(&)
    end

    def append(other)
      return self if other.empty?
      return other if size.zero?

      last = last_child
      first = other.first_child
      joined_content = content.dup
      index = 0

      if last.text? && last.same_markup?(first)
        joined_content[-1] = last.with_text(last.text + first.text)
        index = 1
      end

      Fragment.new(joined_content + other.content.slice(index, other.content.length), size + other.size)
    end

    def cut(from, to = size)
      return self if from.zero? && to == size

      result = []
      cut_size = 0
      position = 0

      content.each do |child|
        break if position >= to

        ending = position + child.node_size
        if ending > from
          cut_child = child
          if position < from || ending > to
            cut_child = if child.text?
                          child.cut([0, from - position].max, [child.text.length, to - position].min)
                        else
                          child.cut([0, from - position - 1].max, [child.content.size, to - position - 1].min)
                        end
          end
          result << cut_child
          cut_size += cut_child.node_size
        end
        position = ending
      end

      Fragment.new(result, cut_size)
    end

    def replace_child(index, node)
      current = content[index]
      return self if current.equal?(node)

      copy = content.dup
      copy[index] = node
      Fragment.new(copy, size + node.node_size - current.node_size)
    end

    def find_index(position)
      return { index: 0, offset: 0 } if position.zero?
      return { index: content.length, offset: position } if position == size

      if position.negative? || position > size
        raise ValidationError,
              "Position #{position} outside of fragment (#{self})"
      end

      current_position = 0
      content.each_with_index do |child, index|
        ending = current_position + child.node_size
        return { index: index + 1, offset: ending } if ending == position
        return { index: index, offset: current_position } if ending > position

        current_position = ending
      end
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
