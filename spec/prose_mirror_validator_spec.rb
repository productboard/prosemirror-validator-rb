# frozen_string_literal: true

require 'prosemirror_validator'

RSpec.describe ProseMirrorValidator do
  let(:schema_spec) do
    {
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

  let(:schema) { ProseMirrorValidator::Schema.from_spec(schema_spec) }

  describe ProseMirrorValidator::Validator do
    it 'validates a document payload against a schema' do
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

      expect(described_class.validate!(document, schema_spec)).to be_a(ProseMirrorValidator::Node)
      expect(described_class.valid?(document, schema_spec)).to be(true)
    end

    it 'returns false for invalid documents' do
      document = { type: 'doc', content: [{ type: 'image', attrs: { src: 'avatar.png' } }] }

      expect(described_class.valid?(document, schema_spec)).to be(false)
    end
  end

  describe ProseMirrorValidator::Schema do
    it 'accepts OrderedMap-shaped specs exported from ProseMirror JSON' do
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

      document = { 'type' => 'doc',
                   'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'ok' }] }] }

      expect(described_class.from_spec(ordered_spec).validate_document!(document)).to be_a(ProseMirrorValidator::Node)
    end

    it 'builds nodes from JSON without recursively checking full content' do
      document = { type: 'doc', content: [{ type: 'image', attrs: { src: 'avatar.png' } }] }

      node = schema.node_from_json(document)

      expect(node).to be_a(ProseMirrorValidator::Node)
      expect { node.check! }.to raise_error(ProseMirrorValidator::ValidationError, /Invalid content for node doc/)
    end

    it 'rejects schemas without a text type' do
      expect do
        described_class.from_spec(nodes: { doc: {} })
      end.to raise_error(ProseMirrorValidator::SchemaError, /Every schema needs a 'text' type/)
    end
  end

  describe ProseMirrorValidator::ContentMatch do
    def match?(expression, types)
      match = described_class.parse(expression, schema.nodes)
      types.split.each do |type|
        match = match&.match_type(schema.nodes.fetch(type))
      end
      match&.valid_end?
    end

    it 'matches groups, choices, sequences, and repeats' do
      expect(match?('inline*', 'image text hard_break')).to be(true)
      expect(match?('(paragraph | heading) paragraph*', 'heading paragraph paragraph')).to be(true)
      expect(match?('heading paragraph+', 'heading')).to be(false)
    end

    it 'matches exact, bounded, and open ranges' do
      expect(match?('hard_break{2}', 'hard_break hard_break')).to be(true)
      expect(match?('hard_break{2,4}', 'hard_break hard_break hard_break')).to be(true)
      expect(match?('hard_break{2,}', 'hard_break hard_break hard_break hard_break')).to be(true)
      expect(match?('hard_break{2,4}', 'hard_break')).to be(false)
    end

    it 'rejects mixed inline and block content expressions' do
      expect do
        described_class.parse('paragraph text', schema.nodes)
      end.to raise_error(ProseMirrorValidator::ContentExpressionError, /Mixing inline and block content/)
    end
  end

  describe 'attribute validation' do
    it 'applies default attributes and validates primitive types' do
      image = schema.node_from_json(type: 'image', attrs: { src: 'avatar.png' })

      expect(image.attrs).to eq('src' => 'avatar.png', 'alt' => nil)
      expect do
        schema.node_from_json(type: 'image', attrs: { src: true })
      end.to raise_error(ProseMirrorValidator::ValidationError, /Expected value of type string/)
    end

    it 'requires missing required attributes' do
      expect do
        schema.node_from_json(type: 'image')
      end.to raise_error(ProseMirrorValidator::ValidationError, /No value supplied for attribute src/)
    end

    it 'rejects unsupported node and mark attributes' do
      expect do
        schema.node_from_json(type: 'image', attrs: { src: 'avatar.png', href: 'wrong' })
      end.to raise_error(ProseMirrorValidator::ValidationError, /Unsupported attribute href/)

      expect do
        schema.mark_from_json(type: 'em', attrs: { href: 'wrong' })
      end.to raise_error(ProseMirrorValidator::ValidationError, /Unsupported attribute href/)
    end
  end

  describe 'mark validation' do
    it 'rejects mark sets that violate exclusions' do
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

      expect do
        schema.validate_document!(document)
      end.to raise_error(ProseMirrorValidator::ValidationError, /Invalid collection of marks/)
    end

    it 'rejects marks that are not allowed by parent content' do
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

      expect do
        no_marks_schema.validate_document!(document)
      end.to raise_error(ProseMirrorValidator::ValidationError, /Invalid content for node paragraph/)
    end
  end
end
