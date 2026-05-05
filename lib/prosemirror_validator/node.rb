# frozen_string_literal: true

require_relative 'fragment'
require_relative 'mark'
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

    def same_markup?(other)
      type.equal?(other.type) && Utils.deep_equal?(attrs, other.attrs) && Mark.same_set?(marks, other.marks)
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
