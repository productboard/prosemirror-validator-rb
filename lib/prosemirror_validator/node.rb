# frozen_string_literal: true

require_relative 'fragment'
require_relative 'mark'
require_relative 'replacement'
require_relative 'resolved_pos'
require_relative 'slice'
require_relative 'utils'

module ProseMirrorValidator
  class Node
    attr_reader :type, :attrs, :content, :marks

    def initialize(type, attrs, content = nil, marks = Mark::NONE)
      @type = type
      @attrs = attrs.freeze
      @content = content || Fragment.empty
      @marks = marks.freeze
    end

    def text
      nil
    end

    def node_size
      leaf? ? 1 : 2 + content.size
    end

    def child_count
      content.child_count
    end

    def child(index)
      content.child(index)
    end

    def maybe_child(index)
      content.maybe_child(index)
    end

    def first_child
      content.first_child
    end

    def last_child
      content.last_child
    end

    def block?
      type.block?
    end

    def inline?
      type.inline?
    end

    def text?
      type.text?
    end

    def leaf?
      type.leaf?
    end

    def atom?
      type.atom?
    end

    def same_markup?(other)
      type.equal?(other.type) && Utils.deep_equal?(attrs, other.attrs) && Mark.same_set?(marks, other.marks)
    end

    def copy(content = nil)
      return self if content.equal?(self.content)

      Node.new(type, attrs, content || self.content, marks)
    end

    def mark(marks)
      return self if marks.equal?(self.marks)

      Node.new(type, attrs, content, marks)
    end

    def cut(from, to = content.size)
      return self if from.zero? && to == content.size

      copy(content.cut(from, to))
    end

    def slice(from, to = content.size, include_parents: false)
      return Slice.empty if from == to

      resolved_from = resolve(from)
      resolved_to = resolve(to)
      depth = include_parents ? 0 : resolved_from.shared_depth(to)
      start = resolved_from.start(depth)
      node = resolved_from.node(depth)
      Slice.new(
        node.content.cut(resolved_from.pos - start, resolved_to.pos - start),
        resolved_from.depth - depth,
        resolved_to.depth - depth
      )
    end

    def replace(from, to, slice)
      Replacement.replace(resolve(from), resolve(to), slice)
    end

    def resolve(position)
      ResolvedPos.resolve(self, position)
    end

    def resolve_no_cache(position)
      ResolvedPos.resolve(self, position)
    end

    def node_at(position)
      node = self
      loop do
        found = node.content.find_index(position)
        node = node.maybe_child(found.fetch(:index))
        return nil unless node
        return node if found.fetch(:offset) == position || node.text?

        position -= found.fetch(:offset) + 1
      end
    end

    def content_match_at(index)
      match = type.content_match.match_fragment(content, 0, index)
      raise Error, 'Called content_match_at on a node with invalid content' unless match

      match
    end

    def can_replace?(from, to, replacement = Fragment.empty, start_index = 0, end_index = replacement.child_count)
      one = content_match_at(from).match_fragment(replacement, start_index, end_index)
      two = one&.match_fragment(content, to)
      return false unless two&.valid_end?

      (start_index...end_index).all? { |index| type.allows_marks?(replacement.child(index).marks) }
    end

    def check!
      type.check_content!(content)
      type.check_attrs!(attrs)

      copy = Mark::NONE
      marks.each do |mark|
        mark.type.check_attrs!(mark.attrs)
        copy = mark.add_to_set(copy)
      end

      unless Mark.same_set?(copy, marks)
        raise ValidationError, "Invalid collection of marks for node #{type.name}: #{marks.map do |mark|
          mark.type.name
        end}"
      end

      content.each(&:check!)
      self
    end

    def valid?
      check!
      true
    rescue ValidationError
      false
    end

    def to_json_object
      object = { 'type' => type.name }
      object['attrs'] = attrs unless attrs.empty?
      object['content'] = content.to_json_object if content.size.positive?
      object['marks'] = marks.map(&:to_json_object) unless marks.empty?
      object
    end

    def to_s
      name = type.name
      name += "(#{content.content.join(', ')})" if content.size.positive?
      name
    end

    def self.from_json(schema, json)
      raise ValidationError, 'Invalid input for Node.fromJSON' if json.nil?

      marks = if Utils.key?(json, 'marks')
                mark_data = Utils.fetch_value(json, 'marks')
                raise ValidationError, 'Invalid mark data for Node.fromJSON' unless mark_data.is_a?(Array)

                mark_data.map { |mark_json| schema.mark_from_json(mark_json) }
              end

      type_name = Utils.fetch_value(json, 'type')
      if type_name == 'text'
        text = Utils.fetch_value(json, 'text')
        raise ValidationError, 'Invalid text node in JSON' unless text.is_a?(String)

        return schema.text(text, marks)
      end

      node_type = schema.node_type(type_name)
      node_type.check_supported_attrs!(Utils.fetch_value(json, 'attrs'))
      content = Fragment.from_json(schema, Utils.fetch_value(json, 'content'))
      node = node_type.create(Utils.fetch_value(json, 'attrs'), content, marks)
      node.type.check_attrs!(node.attrs)
      node
    end
  end

  class TextNode < Node
    attr_reader :text

    def initialize(type, attrs, text, marks = Mark::NONE)
      raise ValidationError, 'Empty text nodes are not allowed' if text.empty?

      super(type, attrs, nil, marks)
      @text = text
    end

    def node_size
      text.length
    end

    def with_text(text)
      return self if text == self.text

      TextNode.new(type, attrs, text, marks)
    end

    def cut(from, to = text.length)
      return self if from.zero? && to == text.length

      with_text(text.slice(from...to))
    end

    def mark(marks)
      return self if marks.equal?(self.marks)

      TextNode.new(type, attrs, text, marks)
    end

    def to_json_object
      object = { 'type' => type.name, 'text' => text }
      object['marks'] = marks.map(&:to_json_object) unless marks.empty?
      object
    end

    def to_s
      text.inspect
    end
  end
end
