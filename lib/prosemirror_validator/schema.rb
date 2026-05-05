# frozen_string_literal: true

require_relative 'content_match'
require_relative 'errors'
require_relative 'mark'
require_relative 'mark_type'
require_relative 'node'
require_relative 'node_type'
require_relative 'utils'

module ProseMirrorValidator
  class Schema
    attr_reader :spec, :nodes, :marks, :top_node_type

    def initialize(spec)
      @spec = Utils.normalize_hash(spec)
      @nodes = compile_nodes(Utils.fetch_value(@spec, 'nodes'))
      @marks = compile_marks(Utils.fetch_value(@spec, 'marks') || {})

      initialize_content_matches
      initialize_mark_exclusions
      @top_node_type = nodes[Utils.fetch_value(@spec, 'topNode') || 'doc']
    end

    def self.from_spec(spec)
      new(spec)
    end

    def node(type, attrs = nil, content = nil, marks = nil)
      node_type(type).create_checked(attrs, content, marks)
    end

    def text(text, marks = nil)
      type = nodes['text']
      TextNode.new(type, type.compute_attrs(nil), text, Mark.normalize_set(marks))
    end

    def mark(type, attrs = nil)
      mark_type = type.is_a?(MarkType) ? type : marks[type.to_s]
      raise ValidationError, "There is no mark type #{type} in this schema" unless mark_type

      mark_type.create(attrs)
    end

    def node_from_json(json)
      Node.from_json(self, json)
    end

    def mark_from_json(json)
      Mark.from_json(self, json)
    end

    def validate_document!(json)
      node_from_json(json).check!
    end

    def valid_document?(json)
      validate_document!(json)
      true
    rescue Error
      false
    end

    def node_type(name)
      found = nodes[name.to_s]
      raise ValidationError, "Unknown node type: #{name}" unless found

      found
    end

    private

    def compile_nodes(raw_nodes)
      raise SchemaError, 'Schema is missing node specs' unless raw_nodes

      result = {}
      Utils.ordered_pairs(raw_nodes).each do |name, node_spec|
        result[name] = NodeType.new(name, self, node_spec)
      end

      top_type = Utils.fetch_value(spec, 'topNode') || 'doc'
      raise SchemaError, "Schema is missing its top node type ('#{top_type}')" unless result[top_type]
      raise SchemaError, "Every schema needs a 'text' type" unless result['text']
      raise SchemaError, 'The text node type should not have attributes' unless result['text'].attrs.empty?

      result
    end

    def compile_marks(raw_marks)
      result = {}
      Utils.ordered_pairs(raw_marks).each_with_index do |(name, mark_spec), rank|
        result[name] = MarkType.new(name, rank, self, mark_spec)
      end
      result
    end

    def initialize_content_matches
      content_expression_cache = {}

      nodes.each do |name, type|
        raise SchemaError, "#{name} can not be both a node and a mark" if marks.key?(name)

        content_expression = type.spec.fetch('content', '')
        type.content_match = content_expression_cache[content_expression] ||=
          ContentMatch.parse(content_expression, nodes)
        type.inline_content = type.content_match.inline_content?
        type.mark_set = resolve_node_mark_set(type)
      end
    end

    def resolve_node_mark_set(type)
      mark_expression = type.spec['marks']

      if mark_expression == '_'
        nil
      elsif mark_expression && mark_expression != ''
        gather_marks(mark_expression.split)
      elsif mark_expression == '' || !type.inline_content?
        []
      end
    end

    def initialize_mark_exclusions
      marks.each_value do |type|
        excludes = type.spec['excludes']
        type.excluded = if excludes.nil?
                          [type]
                        elsif excludes == ''
                          []
                        else
                          gather_marks(excludes.split)
                        end
      end
    end

    def gather_marks(mark_names)
      found = []

      mark_names.each do |mark_name|
        direct_mark = marks[mark_name]
        ok = direct_mark

        if direct_mark
          found << direct_mark
        else
          marks.each_value do |mark|
            next unless mark_name == '_' || mark.spec.fetch('group', '').split.include?(mark_name)

            found << mark
            ok = mark
          end
        end

        raise ContentExpressionError, "Unknown mark type: '#{mark_name}'" unless ok
      end

      found
    end
  end
end
