# frozen_string_literal: true

require 'prosemirror_validator'

RSpec.describe ProseMirrorValidator::Updates do
  let(:schema_spec) do
    {
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

  let(:document) do
    {
      type: 'doc',
      content: [{ type: 'paragraph', content: [{ type: 'text', text: 'hello' }] }]
    }
  end

  let(:wrapping_schema) do
    schema_spec.merge(
      nodes: schema_spec.fetch(:nodes).merge(
        doc: { content: 'block+' },
        blockquote: { content: 'block+', group: 'block' }
      )
    )
  end

  let(:wrap_paragraph_step) do
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

  it 'applies and validates replace steps' do
    result = described_class.validate_steps!(
      document: document,
      schema_spec: schema_spec,
      steps: [{ stepType: 'replace', from: 6, to: 6, slice: { content: [{ type: 'text', text: '!' }] } }]
    )

    expect(result.to_json_object).to eq(
      'type' => 'doc',
      'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'hello!' }] }]
    )
  end

  it 'rejects replacement steps that produce invalid content' do
    expect do
      described_class.validate_steps!(
        document: document,
        schema_spec: schema_spec,
        steps: [{ stepType: 'replace', from: 1, to: 1, slice: { content: [{ type: 'paragraph' }] } }]
      )
    end.to raise_error(ProseMirrorValidator::TransformError, /Invalid content|Cannot join|Inconsistent open depths/)
  end

  it 'applies replaceAround steps' do
    result = described_class.validate_steps!(
      document: document,
      schema_spec: wrapping_schema,
      steps: [wrap_paragraph_step]
    )

    expect(result.to_json_object).to eq(
      'type' => 'doc',
      'content' => [{ 'type' => 'blockquote',
                      'content' => [{ 'type' => 'paragraph',
                                      'content' => [{ 'type' => 'text', 'text' => 'hello' }] }] }]
    )
  end

  it 'applies addMark and removeMark steps' do
    added = described_class.validate_steps!(
      document: document,
      schema_spec: schema_spec,
      steps: [{ stepType: 'addMark', from: 1, to: 6, mark: { type: 'em' } }]
    )

    removed = described_class.validate_steps!(
      document: added.to_json_object,
      schema_spec: schema_spec,
      steps: [{ stepType: 'removeMark', from: 2, to: 5, mark: { type: 'em' } }]
    )

    expect(added.to_json_object['content'].first['content']).to eq(
      [{ 'type' => 'text', 'text' => 'hello', 'marks' => [{ 'type' => 'em' }] }]
    )
    expect(removed.to_json_object['content'].first['content']).to eq(
      [
        { 'type' => 'text', 'text' => 'h', 'marks' => [{ 'type' => 'em' }] },
        { 'type' => 'text', 'text' => 'ell' },
        { 'type' => 'text', 'text' => 'o', 'marks' => [{ 'type' => 'em' }] }
      ]
    )
  end

  it 'applies node mark and node attribute steps' do
    image_document = {
      type: 'doc',
      content: [{ type: 'paragraph', content: [{ type: 'image', attrs: { src: 'old.png' } }] }]
    }

    result = described_class.validate_steps!(
      document: image_document,
      schema_spec: schema_spec,
      steps: [
        { stepType: 'addNodeMark', pos: 1, mark: { type: 'link', attrs: { href: 'https://example.test' } } },
        { stepType: 'attr', pos: 1, attr: 'src', value: 'new.png' },
        { stepType: 'removeNodeMark', pos: 1, mark: { type: 'link', attrs: { href: 'https://example.test' } } }
      ]
    )

    expect(result.to_json_object).to eq(
      'type' => 'doc',
      'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'image',
                                                             'attrs' => { 'src' => 'new.png', 'alt' => nil } }] }]
    )
  end

  it 'applies document attribute steps' do
    schema_with_doc_attr = schema_spec.merge(
      nodes: schema_spec.fetch(:nodes).merge(doc: { content: 'block+', attrs: { version: { default: 1 } } })
    )

    result = described_class.validate_steps!(
      document: document,
      schema_spec: schema_with_doc_attr,
      steps: [{ stepType: 'docAttr', attr: 'version', value: 2 }]
    )

    expect(result.to_json_object['attrs']).to eq('version' => 2)
  end

  it 'returns false for invalid step sequences' do
    expect(
      described_class.valid_steps?(
        document: document,
        schema_spec: schema_spec,
        steps: [{ stepType: 'replace', from: 100, to: 100 }]
      )
    ).to be(false)
  end
end
