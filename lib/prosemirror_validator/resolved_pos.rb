# frozen_string_literal: true

require_relative 'errors'

module ProseMirrorValidator
  class ResolvedPos
    attr_reader :pos, :path, :parent_offset, :depth

    def initialize(pos, path, parent_offset)
      @pos = pos
      @path = path
      @parent_offset = parent_offset
      @depth = (path.length / 3) - 1
    end

    def parent
      node(depth)
    end

    def doc
      node(0)
    end

    def node(depth = nil)
      path[resolve_depth(depth) * 3]
    end

    def index(depth = nil)
      path[(resolve_depth(depth) * 3) + 1]
    end

    def index_after(depth = nil)
      resolved_depth = resolve_depth(depth)
      index(resolved_depth) + (resolved_depth == self.depth && text_offset.zero? ? 0 : 1)
    end

    def start(depth = nil)
      resolved_depth = resolve_depth(depth)
      resolved_depth.zero? ? 0 : path[(resolved_depth * 3) - 1] + 1
    end

    def end_position(depth = nil)
      resolved_depth = resolve_depth(depth)
      start(resolved_depth) + node(resolved_depth).content.size
    end

    def before(depth = nil)
      resolved_depth = resolve_depth(depth)
      raise ValidationError, 'There is no position before the top-level node' if resolved_depth.zero?

      resolved_depth == self.depth + 1 ? pos : path[(resolved_depth * 3) - 1]
    end

    def after(depth = nil)
      resolved_depth = resolve_depth(depth)
      raise ValidationError, 'There is no position after the top-level node' if resolved_depth.zero?

      resolved_depth == self.depth + 1 ? pos : path[(resolved_depth * 3) - 1] + path[resolved_depth * 3].node_size
    end

    def text_offset
      pos - path.last
    end

    def node_after
      current_parent = parent
      current_index = index(depth)
      return nil if current_index == current_parent.child_count

      offset = pos - path.last
      child = current_parent.child(current_index)
      offset.positive? ? child.cut(offset) : child
    end

    def node_before
      current_index = index(depth)
      offset = pos - path.last
      return parent.child(current_index).cut(0, offset) if offset.positive?

      current_index.zero? ? nil : parent.child(current_index - 1)
    end

    def pos_at_index(index, depth = nil)
      resolved_depth = resolve_depth(depth)
      current_node = node(resolved_depth)
      position = resolved_depth.zero? ? 0 : path[(resolved_depth * 3) - 1] + 1

      index.times { |child_index| position += current_node.child(child_index).node_size }
      position
    end

    def shared_depth(position)
      depth.downto(1) do |current_depth|
        return current_depth if position.between?(start(current_depth), end_position(current_depth))
      end

      0
    end

    def self.resolve(doc, position)
      raise ValidationError, "Position #{position} out of range" unless position.between?(0, doc.content.size)

      path = []
      start = 0
      parent_offset = position
      node = doc

      loop do
        found = node.content.find_index(parent_offset)
        remainder = parent_offset - found.fetch(:offset)
        path.push(node, found.fetch(:index), start + found.fetch(:offset))
        break if remainder.zero?

        node = node.child(found.fetch(:index))
        break if node.text?

        parent_offset = remainder - 1
        start += found.fetch(:offset) + 1
      end

      new(position, path, parent_offset)
    end

    private

    def resolve_depth(value)
      return depth if value.nil?
      return depth + value if value.negative?

      value
    end
  end
end
