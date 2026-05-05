# frozen_string_literal: true

require_relative 'errors'
require_relative 'fragment'
require_relative 'slice'

module ProseMirrorValidator
  module Replacement
    module_function

    def replace(resolved_from, resolved_to, slice)
      raise ReplaceError, 'Inserted content deeper than insertion position' if slice.open_start > resolved_from.depth

      if resolved_from.depth - slice.open_start != resolved_to.depth - slice.open_end
        raise ReplaceError, 'Inconsistent open depths'
      end

      replace_outer(resolved_from, resolved_to, slice, 0)
    end

    def replace_outer(resolved_from, resolved_to, slice, depth)
      index = resolved_from.index(depth)
      node = resolved_from.node(depth)

      if index == resolved_to.index(depth) && depth < resolved_from.depth - slice.open_start
        inner = replace_outer(resolved_from, resolved_to, slice, depth + 1)
        node.copy(node.content.replace_child(index, inner))
      elsif slice.content.empty?
        close(node, replace_two_way(resolved_from, resolved_to, depth))
      elsif slice.open_start.zero? && slice.open_end.zero? && resolved_from.depth == depth && resolved_to.depth == depth
        parent = resolved_from.parent
        content = parent.content
        before = content.cut(0, resolved_from.parent_offset)
        after = content.cut(resolved_to.parent_offset)
        close(parent, before.append(slice.content).append(after))
      else
        prepared = prepare_slice_for_replace(slice, resolved_from)
        close(node, replace_three_way(resolved_from, prepared.fetch(:start), prepared.fetch(:end), resolved_to, depth))
      end
    end

    def replace_three_way(resolved_from, start, ending, resolved_to, depth)
      open_start = resolved_from.depth > depth && joinable(resolved_from, start, depth + 1)
      open_end = resolved_to.depth > depth && joinable(ending, resolved_to, depth + 1)
      content = []

      add_range(nil, resolved_from, depth, content)
      if open_start && open_end && start.index(depth) == ending.index(depth)
        check_join(open_start, open_end)
        add_node(close(open_start, replace_three_way(resolved_from, start, ending, resolved_to, depth + 1)), content)
      else
        add_node(close(open_start, replace_two_way(resolved_from, start, depth + 1)), content) if open_start
        add_range(start, ending, depth, content)
        add_node(close(open_end, replace_two_way(ending, resolved_to, depth + 1)), content) if open_end
      end
      add_range(resolved_to, nil, depth, content)
      Fragment.new(content)
    end

    def replace_two_way(resolved_from, resolved_to, depth)
      content = []
      add_range(nil, resolved_from, depth, content)
      if resolved_from.depth > depth
        type = joinable(resolved_from, resolved_to, depth + 1)
        add_node(close(type, replace_two_way(resolved_from, resolved_to, depth + 1)), content)
      end
      add_range(resolved_to, nil, depth, content)
      Fragment.new(content)
    end

    def prepare_slice_for_replace(slice, along)
      extra = along.depth - slice.open_start
      parent = along.node(extra)
      node = parent.copy(slice.content)
      (extra - 1).downto(0) do |index|
        node = along.node(index).copy(Fragment.from(node))
      end

      {
        start: node.resolve_no_cache(slice.open_start + extra),
        end: node.resolve_no_cache(node.content.size - slice.open_end - extra)
      }
    end

    def check_join(main, sub)
      return if sub.type.compatible_content?(main.type)

      raise ReplaceError,
            "Cannot join #{sub.type.name} onto #{main.type.name}"
    end

    def joinable(before, after, depth)
      node = before.node(depth)
      check_join(node, after.node(depth))
      node
    end

    def add_node(child, target)
      last_index = target.length - 1
      if last_index >= 0 && child.text? && child.same_markup?(target[last_index])
        target[last_index] = child.with_text(target[last_index].text + child.text)
      else
        target << child
      end
    end

    def add_range(start, ending, depth, target)
      node = (ending || start).node(depth)
      start_index = 0
      end_index = ending ? ending.index(depth) : node.child_count

      if start
        start_index = start.index(depth)
        if start.depth > depth
          start_index += 1
        elsif start.text_offset.positive?
          add_node(start.node_after, target)
          start_index += 1
        end
      end

      (start_index...end_index).each { |index| add_node(node.child(index), target) }
      add_node(ending.node_before, target) if ending && ending.depth == depth && ending.text_offset.positive?
    end

    def close(node, content)
      node.type.check_content!(content)
      node.copy(content)
    rescue ValidationError => e
      raise ReplaceError, e.message
    end
  end
end
