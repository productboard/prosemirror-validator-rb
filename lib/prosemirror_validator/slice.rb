# frozen_string_literal: true

require_relative 'fragment'
require_relative 'utils'

module ProseMirrorValidator
  class Slice
    attr_reader :content, :open_start, :open_end

    def initialize(content, open_start, open_end)
      @content = content
      @open_start = open_start
      @open_end = open_end
    end

    def size
      content.size - open_start - open_end
    end

    def insert_at(position, fragment)
      inserted = insert_into(content, position + open_start, fragment)
      inserted && Slice.new(inserted, open_start, open_end)
    end

    def remove_between(from, to)
      Slice.new(remove_range(content, from + open_start, to + open_start), open_start, open_end)
    end

    def to_json_object
      return nil unless content.size.positive?

      object = { 'content' => content.to_json_object }
      object['openStart'] = open_start if open_start.positive?
      object['openEnd'] = open_end if open_end.positive?
      object
    end

    def self.from_json(schema, json)
      return empty if json.nil? || json == false

      open_start = Utils.fetch_value(json, 'openStart') || 0
      open_end = Utils.fetch_value(json, 'openEnd') || 0
      unless open_start.is_a?(Numeric) && open_end.is_a?(Numeric)
        raise ValidationError, 'Invalid input for Slice.fromJSON'
      end

      new(Fragment.from_json(schema, Utils.fetch_value(json, 'content')), open_start, open_end)
    end

    def self.empty
      @empty ||= new(Fragment.empty, 0, 0)
    end

    private

    def remove_range(content, from, to)
      found = content.find_index(from)
      child = content.maybe_child(found.fetch(:index))
      to_found = content.find_index(to)

      if found.fetch(:offset) == from || child.text?
        if to_found.fetch(:offset) != to && !content.child(to_found.fetch(:index)).text?
          raise ValidationError, 'Removing non-flat range'
        end

        return content.cut(0, from).append(content.cut(to))
      end

      raise ValidationError, 'Removing non-flat range' if found.fetch(:index) != to_found.fetch(:index)

      content.replace_child(
        found.fetch(:index),
        child.copy(remove_range(child.content, from - found.fetch(:offset) - 1, to - found.fetch(:offset) - 1))
      )
    end

    def insert_into(content, distance, insert, parent = nil)
      found = content.find_index(distance)
      child = content.maybe_child(found.fetch(:index))

      if found.fetch(:offset) == distance || child.text?
        return nil if parent && !parent.can_replace?(found.fetch(:index), found.fetch(:index), insert)

        return content.cut(0, distance).append(insert).append(content.cut(distance))
      end

      inner = insert_into(child.content, distance - found.fetch(:offset) - 1, insert, child)
      inner && content.replace_child(found.fetch(:index), child.copy(inner))
    end
  end
end
