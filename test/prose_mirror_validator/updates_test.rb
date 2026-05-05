# frozen_string_literal: true

require_relative '../test_helper'

class ProseMirrorValidatorUpdatesTest < Minitest::Test
  def test_applies_and_validates_replace_steps
    result = ProseMirrorValidator::Updates.validate_steps!(
      document: document,
      schema_spec: schema_spec,
      steps: [{ stepType: 'replace', from: 6, to: 6, slice: { content: [{ type: 'text', text: '!' }] } }]
    )

    assert_equal(
      {
        'type' => 'doc',
        'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'hello!' }] }]
      },
      result.to_json_object
    )
  end

  def test_rejects_replacement_steps_that_produce_invalid_content
    assert_raises_with_message(
      ProseMirrorValidator::TransformError,
      /Invalid content|Cannot join|Inconsistent open depths/
    ) do
      ProseMirrorValidator::Updates.validate_steps!(
        document: document,
        schema_spec: schema_spec,
        steps: [{ stepType: 'replace', from: 1, to: 1, slice: { content: [{ type: 'paragraph' }] } }]
      )
    end
  end

  def test_applies_replace_around_steps
    result = ProseMirrorValidator::Updates.validate_steps!(
      document: document,
      schema_spec: wrapping_schema,
      steps: [wrap_paragraph_step]
    )

    assert_equal(
      {
        'type' => 'doc',
        'content' => [{ 'type' => 'blockquote',
                        'content' => [{ 'type' => 'paragraph',
                                        'content' => [{ 'type' => 'text', 'text' => 'hello' }] }] }]
      },
      result.to_json_object
    )
  end

  def test_applies_add_mark_and_remove_mark_steps
    added = ProseMirrorValidator::Updates.validate_steps!(
      document: document,
      schema_spec: schema_spec,
      steps: [{ stepType: 'addMark', from: 1, to: 6, mark: { type: 'em' } }]
    )

    removed = ProseMirrorValidator::Updates.validate_steps!(
      document: added.to_json_object,
      schema_spec: schema_spec,
      steps: [{ stepType: 'removeMark', from: 2, to: 5, mark: { type: 'em' } }]
    )

    assert_equal(
      [{ 'type' => 'text', 'text' => 'hello', 'marks' => [{ 'type' => 'em' }] }],
      added.to_json_object['content'].first['content']
    )
    assert_equal(
      [
        { 'type' => 'text', 'text' => 'h', 'marks' => [{ 'type' => 'em' }] },
        { 'type' => 'text', 'text' => 'ell' },
        { 'type' => 'text', 'text' => 'o', 'marks' => [{ 'type' => 'em' }] }
      ],
      removed.to_json_object['content'].first['content']
    )
  end

  def test_applies_node_mark_and_node_attribute_steps
    image_document = {
      type: 'doc',
      content: [{ type: 'paragraph', content: [{ type: 'image', attrs: { src: 'old.png' } }] }]
    }

    result = ProseMirrorValidator::Updates.validate_steps!(
      document: image_document,
      schema_spec: schema_spec,
      steps: [
        { stepType: 'addNodeMark', pos: 1, mark: { type: 'link', attrs: { href: 'https://example.test' } } },
        { stepType: 'attr', pos: 1, attr: 'src', value: 'new.png' },
        { stepType: 'removeNodeMark', pos: 1, mark: { type: 'link', attrs: { href: 'https://example.test' } } }
      ]
    )

    assert_equal(
      {
        'type' => 'doc',
        'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'image',
                                                               'attrs' => { 'src' => 'new.png', 'alt' => nil } }] }]
      },
      result.to_json_object
    )
  end

  def test_applies_document_attribute_steps
    schema_with_doc_attr = schema_spec.merge(
      nodes: schema_spec.fetch(:nodes).merge(doc: { content: 'block+', attrs: { version: { default: 1 } } })
    )

    result = ProseMirrorValidator::Updates.validate_steps!(
      document: document,
      schema_spec: schema_with_doc_attr,
      steps: [{ stepType: 'docAttr', attr: 'version', value: 2 }]
    )

    assert_equal({ 'version' => 2 }, result.to_json_object['attrs'])
  end

  def test_returns_false_for_invalid_step_sequences
    refute(
      ProseMirrorValidator::Updates.valid_steps?(
        document: document,
        schema_spec: schema_spec,
        steps: [{ stepType: 'replace', from: 100, to: 100 }]
      )
    )
  end

  private

  def schema_spec
    @schema_spec ||= {
      nodes: {
        doc: { content: 'block+' },
        paragraph: { content: 'inline*', group: 'block' },
        image: {
          inline: true,
          group: 'inline',
          attrs: {
            src: { validate: 'string' },
            alt: { default: nil, validate: 'string|null' }
          }
        },
        text: { group: 'inline' }
      },
      marks: {
        em: {},
        strong: {},
        link: { attrs: { href: { validate: 'string' } } }
      }
    }
  end

  def document
    {
      type: 'doc',
      content: [{ type: 'paragraph', content: [{ type: 'text', text: 'hello' }] }]
    }
  end

  def wrapping_schema
    schema_spec.merge(
      nodes: schema_spec.fetch(:nodes).merge(
        doc: { content: 'block+' },
        blockquote: { content: 'block+', group: 'block' }
      )
    )
  end

  def wrap_paragraph_step
    {
      stepType: 'replaceAround',
      from: 0,
      to: 7,
      gapFrom: 0,
      gapTo: 7,
      insert: 1,
      slice: { content: [{ type: 'blockquote' }] }
    }
  end
end
