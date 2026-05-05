# frozen_string_literal: true

require 'json'
require_relative '../test_helper'

class ProseMirrorValidatorSchemaTest < Minitest::Test
  def test_validates_a_realistic_article_editor_schema_and_document
    validated = schema.validate_document!(document).to_json_object

    assert_equal(
      [{ 'type' => 'text', 'text' => 'the body', 'marks' => [insertion_mark(25_710_790)] }],
      body_paragraph_content(validated)
    )
  end

  def test_applies_realistic_tracked_insert_update_steps
    updated = ProseMirrorValidator::Updates.validate_steps!(
      document: document,
      schema: schema,
      steps: steps
    ).to_json_object

    assert_equal(
      [
        { 'type' => 'text', 'text' => 'the b', 'marks' => [insertion_mark(25_710_790)] },
        { 'type' => 'text', 'text' => 'X', 'marks' => [insertion_mark(25_716_230)] },
        { 'type' => 'text', 'text' => 'ody', 'marks' => [insertion_mark(25_710_790)] }
      ],
      body_paragraph_content(updated)
    )
  end

  def test_accepts_richer_article_document_shapes
    rich_document = deep_copy(document)
    body_node(rich_document)['content'] = rich_body_content

    validated = schema.validate_document!(rich_document).to_json_object

    assert_equal(
      %w[heading paragraph ordered_list bullet_list figure table],
      body_node(validated).fetch('content').map { |node| node.fetch('type') }
    )
  end

  def test_rejects_real_schema_marks_when_required_attributes_are_missing
    broken_document = deep_copy(document)
    body_paragraph_content(broken_document).first['marks'] << { 'type' => 'comment' }

    assert_raises_with_message(
      ProseMirrorValidator::ValidationError,
      /No value supplied for attribute id/
    ) { schema.validate_document!(broken_document) }
  end

  private

  def schema_spec
    @schema_spec ||= fixture_json('realistic_article_schema')
  end

  def document
    @document ||= fixture_json('realistic_article_document')
  end

  def steps
    @steps ||= fixture_json('realistic_article_steps')
  end

  def schema
    @schema ||= ProseMirrorValidator::Schema.from_spec(schema_spec)
  end

  def fixture_json(name)
    JSON.parse(File.read(File.expand_path("../fixtures/#{name}.json", __dir__)))
  end

  def deep_copy(value)
    JSON.parse(JSON.generate(value))
  end

  def body_node(payload)
    payload.fetch('content').first.fetch('content')[5]
  end

  def body_paragraph_content(payload)
    body_node(payload).fetch('content').first.fetch('content')
  end

  def insertion_mark(date)
    {
      'type' => 'insertion',
      'attrs' => { 'user' => 1, 'username' => 'johanneswilm', 'date' => date, 'approved' => true }
    }
  end

  def rich_body_content
    [
      { 'type' => 'heading', 'attrs' => { 'level' => 2 }, 'content' => [{ 'type' => 'text', 'text' => 'Methods' }] },
      { 'type' => 'paragraph', 'content' => rich_inline_content },
      { 'type' => 'ordered_list', 'content' => [list_item('Numbered item')] },
      { 'type' => 'bullet_list', 'content' => [list_item('Bullet item')] },
      { 'type' => 'figure', 'attrs' => { 'caption' => 'Figure 1', 'image' => true } },
      table_node
    ]
  end

  def rich_inline_content
    [
      { 'type' => 'text', 'text' => 'A cited claim ' },
      { 'type' => 'citation', 'attrs' => { 'references' => [{ 'id' => 'doe-2024' }] } },
      { 'type' => 'text', 'text' => ' with a formula ' },
      { 'type' => 'equation', 'attrs' => { 'equation' => 'x^2' } },
      { 'type' => 'text', 'text' => ' and a footnote' },
      { 'type' => 'footnote', 'attrs' => { 'footnote' => [paragraph_node('Footnote text')] } }
    ]
  end

  def list_item(text)
    { 'type' => 'list_item', 'content' => [paragraph_node(text)] }
  end

  def table_node
    {
      'type' => 'table',
      'content' => [
        { 'type' => 'table_row', 'content' => [table_cell('table_header', 'Head'), table_cell('table_cell', 'Cell')] }
      ]
    }
  end

  def table_cell(type, text)
    { 'type' => type, 'content' => [paragraph_node(text)] }
  end

  def paragraph_node(text)
    { 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => text }] }
  end
end
