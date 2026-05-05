# frozen_string_literal: true

require_relative 'test_helper'

class ProseMirrorValidatorTest < Minitest::Test
  def test_validator_validates_document_payload_against_schema
    document = {
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: [
            { type: 'text', text: 'hello', marks: [{ type: 'em' }] },
            { type: 'image', attrs: { src: 'avatar.png' } }
          ]
        }
      ]
    }

    assert_kind_of(ProseMirrorValidator::Node, ProseMirrorValidator::Validator.validate!(document, schema_spec))
    assert(ProseMirrorValidator::Validator.valid?(document, schema_spec))
  end

  def test_validator_returns_false_for_invalid_documents
    document = { type: 'doc', content: [{ type: 'image', attrs: { src: 'avatar.png' } }] }

    refute(ProseMirrorValidator::Validator.valid?(document, schema_spec))
  end

  def test_schema_accepts_ordered_map_shaped_specs_exported_from_prosemirror_json
    ordered_spec = {
      'nodes' => {
        'content' => [
          'doc', { 'content' => 'paragraph+' },
          'paragraph', { 'content' => 'text*' },
          'text', {}
        ]
      },
      'marks' => { 'content' => ['em', {}] }
    }

    document = {
      'type' => 'doc',
      'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'ok' }] }]
    }

    assert_kind_of(
      ProseMirrorValidator::Node,
      ProseMirrorValidator::Schema.from_spec(ordered_spec).validate_document!(document)
    )
  end

  def test_schema_builds_nodes_from_json_without_recursively_checking_full_content
    document = { type: 'doc', content: [{ type: 'image', attrs: { src: 'avatar.png' } }] }

    node = schema.node_from_json(document)

    assert_kind_of(ProseMirrorValidator::Node, node)
    assert_raises_with_message(
      ProseMirrorValidator::ValidationError,
      /Invalid content for node doc/
    ) { node.check! }
  end

  def test_schema_rejects_schemas_without_a_text_type
    assert_raises_with_message(
      ProseMirrorValidator::SchemaError,
      /Every schema needs a 'text' type/
    ) { ProseMirrorValidator::Schema.from_spec(nodes: { doc: {} }) }
  end

  def test_content_match_matches_groups_choices_sequences_and_repeats
    assert(content_expression_matches?('inline*', 'image text hard_break'))
    assert(content_expression_matches?('(paragraph | heading) paragraph*', 'heading paragraph paragraph'))
    refute(content_expression_matches?('heading paragraph+', 'heading'))
  end

  def test_content_match_matches_exact_bounded_and_open_ranges
    assert(content_expression_matches?('hard_break{2}', 'hard_break hard_break'))
    assert(content_expression_matches?('hard_break{2,4}', 'hard_break hard_break hard_break'))
    assert(content_expression_matches?('hard_break{2,}', 'hard_break hard_break hard_break hard_break'))
    refute(content_expression_matches?('hard_break{2,4}', 'hard_break'))
  end

  def test_content_match_rejects_mixed_inline_and_block_content_expressions
    assert_raises_with_message(
      ProseMirrorValidator::ContentExpressionError,
      /Mixing inline and block content/
    ) { ProseMirrorValidator::ContentMatch.parse('paragraph text', schema.nodes) }
  end

  def test_attribute_validation_applies_default_attributes_and_validates_primitive_types
    image = schema.node_from_json(type: 'image', attrs: { src: 'avatar.png' })

    assert_equal({ 'src' => 'avatar.png', 'alt' => nil }, image.attrs)
    assert_raises_with_message(
      ProseMirrorValidator::ValidationError,
      /Expected value of type string/
    ) { schema.node_from_json(type: 'image', attrs: { src: true }) }
  end

  def test_attribute_validation_requires_missing_required_attributes
    assert_raises_with_message(
      ProseMirrorValidator::ValidationError,
      /No value supplied for attribute src/
    ) { schema.node_from_json(type: 'image') }
  end

  def test_attribute_validation_rejects_unsupported_node_and_mark_attributes
    assert_raises_with_message(
      ProseMirrorValidator::ValidationError,
      /Unsupported attribute href/
    ) { schema.node_from_json(type: 'image', attrs: { src: 'avatar.png', href: 'wrong' }) }

    assert_raises_with_message(
      ProseMirrorValidator::ValidationError,
      /Unsupported attribute href/
    ) { schema.mark_from_json(type: 'em', attrs: { href: 'wrong' }) }
  end

  def test_mark_validation_rejects_mark_sets_that_violate_exclusions
    document = {
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: [
            { type: 'text', text: 'hello', marks: [{ type: 'em' }, { type: 'code' }] }
          ]
        }
      ]
    }

    assert_raises_with_message(
      ProseMirrorValidator::ValidationError,
      /Invalid collection of marks/
    ) { schema.validate_document!(document) }
  end

  def test_mark_validation_rejects_marks_that_are_not_allowed_by_parent_content
    no_marks_schema = ProseMirrorValidator::Schema.from_spec(
      nodes: {
        doc: { content: 'paragraph+' },
        paragraph: { content: 'text*', marks: '' },
        text: {}
      },
      marks: { em: {} }
    )

    document = {
      type: 'doc',
      content: [{ type: 'paragraph', content: [{ type: 'text', text: 'hello', marks: [{ type: 'em' }] }] }]
    }

    assert_raises_with_message(
      ProseMirrorValidator::ValidationError,
      /Invalid content for node paragraph/
    ) { no_marks_schema.validate_document!(document) }
  end

  private

  def schema_spec
    @schema_spec ||= {
      nodes: {
        doc: { content: 'block+' },
        paragraph: { content: 'inline*', group: 'block' },
        heading: { content: 'inline*', group: 'block' },
        image: {
          inline: true,
          group: 'inline',
          attrs: {
            src: { validate: 'string' },
            alt: { default: nil, validate: 'string|null' }
          }
        },
        hard_break: { inline: true, group: 'inline' },
        text: { group: 'inline' }
      },
      marks: {
        em: {},
        strong: {},
        link: { attrs: { href: { validate: 'string' }, title: { default: nil, validate: 'string|null' } } },
        code: { excludes: '_' }
      }
    }
  end

  def schema
    @schema ||= ProseMirrorValidator::Schema.from_spec(schema_spec)
  end

  def content_expression_matches?(expression, types)
    match = ProseMirrorValidator::ContentMatch.parse(expression, schema.nodes)
    types.split.each do |type|
      match = match&.match_type(schema.nodes.fetch(type))
    end

    match&.valid_end?
  end
end
