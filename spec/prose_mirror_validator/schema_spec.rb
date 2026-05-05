# frozen_string_literal: true

require 'json'
require 'prosemirror_validator'

RSpec.describe ProseMirrorValidator::Schema do
  let(:schema_spec) { fixture_json('realistic_article_schema') }
  let(:document) { fixture_json('realistic_article_document') }
  let(:steps) { fixture_json('realistic_article_steps') }
  let(:schema) { described_class.from_spec(schema_spec) }

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

  it 'validates a realistic article editor schema and document' do
    validated = schema.validate_document!(document).to_json_object

    expect(body_paragraph_content(validated)).to eq(
      [{ 'type' => 'text', 'text' => 'the body', 'marks' => [insertion_mark(25_710_790)] }]
    )
  end

  it 'applies realistic tracked insert update steps' do
    updated = ProseMirrorValidator::Updates.validate_steps!(
      document: document,
      schema: schema,
      steps: steps
    ).to_json_object

    expect(body_paragraph_content(updated)).to eq(
      [
        { 'type' => 'text', 'text' => 'the b', 'marks' => [insertion_mark(25_710_790)] },
        { 'type' => 'text', 'text' => 'X', 'marks' => [insertion_mark(25_716_230)] },
        { 'type' => 'text', 'text' => 'ody', 'marks' => [insertion_mark(25_710_790)] }
      ]
    )
  end

  it 'accepts richer article document shapes' do
    rich_document = deep_copy(document)
    body_node(rich_document)['content'] = rich_body_content

    validated = schema.validate_document!(rich_document).to_json_object

    expect(body_node(validated).fetch('content').map { |node| node.fetch('type') }).to eq(
      %w[heading paragraph ordered_list bullet_list figure table]
    )
  end

  it 'rejects real schema marks when required attributes are missing' do
    broken_document = deep_copy(document)
    body_paragraph_content(broken_document).first['marks'] << { 'type' => 'comment' }

    expect { schema.validate_document!(broken_document) }.to raise_error(
      ProseMirrorValidator::ValidationError,
      /No value supplied for attribute id/
    )
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
