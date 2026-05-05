# prosemirror-validator

`prosemirror-validator` is a Ruby 3.3+ gem for validating ProseMirror schema specs, document JSON, and transform step JSON on the server.

It mirrors the validation-oriented behavior of `prosemirror-model` and `prosemirror-transform`. It does not provide an editor runtime.

## Scope

Supported:

- schema construction from ProseMirror schema specs
- OrderedMap-shaped JSON from `schema.spec`, using `{ "content" => ["name", spec, ...] }`
- content expressions with node names, groups, sequences, choices, `*`, `+`, `?`, `{n}`, `{n,m}`, and `{n,}`
- node and mark attrs, including required attrs, default attrs, unsupported attrs, and primitive `validate` strings
- mark ordering and `excludes` rules
- full recursive document validation with `Node#check!`
- ProseMirror step JSON validation and application for built-in transform step types

Out of scope:

- DOM parsing
- HTML serialization
- editor state
- commands and keymaps
- collaborative rebasing or mapping
- custom transform step classes
- sanitization of user HTML

## Installation

Add the gem to your Gemfile:

```ruby
gem "prosemirror-validator"
```

Then install:

```sh
bundle install
```

Require it:

```ruby
require "prosemirror_validator"
```

## Quick Start

```ruby
schema_spec = {
  nodes: {
    doc: { content: "paragraph+" },
    paragraph: { content: "text*" },
    text: {}
  },
  marks: {
    em: {}
  }
}

document = {
  type: "doc",
  content: [
    {
      type: "paragraph",
      content: [
        { type: "text", text: "hello", marks: [{ type: "em" }] }
      ]
    }
  ]
}

node = ProseMirrorValidator::Validator.validate!(document, schema_spec)
node.to_json_object
```

Use the boolean variant when you only need an answer:

```ruby
ProseMirrorValidator::Validator.valid?(document, schema_spec)
```

## API Overview

### `ProseMirrorValidator::Validator`

Convenience module for the common cases.

```ruby
ProseMirrorValidator::Validator.validate!(document, schema_spec)
ProseMirrorValidator::Validator.valid?(document, schema_spec)
ProseMirrorValidator::Validator.validate_steps!(document:, steps:, schema_spec:)
ProseMirrorValidator::Validator.valid_steps?(document:, steps:, schema_spec:)
```

`validate!` returns a checked `ProseMirrorValidator::Node`. It raises a `ProseMirrorValidator::Error` subclass when validation fails.

`valid?` returns `true` or `false`.

`validate_steps!` validates the starting document, applies every step in order, validates the document after each step, and returns the final checked `Node`.

`valid_steps?` returns `true` or `false`.

### `ProseMirrorValidator::Schema`

Use `Schema` when you want to reuse a parsed schema across many validations.

```ruby
schema = ProseMirrorValidator::Schema.from_spec(schema_spec)

node = schema.node_from_json(document)
checked_node = schema.validate_document!(document)

schema.valid_document?(document)
schema.mark_from_json(type: "em")
schema.node("paragraph", nil, [schema.text("hello")])
```

Important distinction:

`Schema#node_from_json` follows ProseMirror's construction behavior. It validates JSON shape, known node/mark names, attributes, and text node shape, but it does not recursively validate the full document content by itself.

Call one of these for full payload validation:

```ruby
node.check!
schema.validate_document!(document)
ProseMirrorValidator::Validator.validate!(document, schema_spec)
```

### `ProseMirrorValidator::Updates`

Use `Updates` when validating ProseMirror transform step JSON.

```ruby
schema = ProseMirrorValidator::Schema.from_spec(schema_spec)

updated_node = ProseMirrorValidator::Updates.validate_steps!(
  document: document,
  schema: schema,
  steps: [
    {
      stepType: "replace",
      from: 6,
      to: 6,
      slice: {
        content: [{ type: "text", text: "!" }]
      }
    }
  ]
)
```

You can pass either `schema:` or `schema_spec:`:

```ruby
ProseMirrorValidator::Updates.validate_steps!(
  document: document,
  schema_spec: schema_spec,
  steps: steps
)
```

The `document:` argument may be a ProseMirror JSON hash or an already built `ProseMirrorValidator::Node`.

The method validates the input document before applying steps. After each step, the resulting document is checked again. If any step fails, it raises.

Use `valid_steps?` for a boolean:

```ruby
ProseMirrorValidator::Updates.valid_steps?(
  document: document,
  schema_spec: schema_spec,
  steps: steps
)
```

## Schema Specs

Schema specs follow ProseMirror's schema shape.

```ruby
schema_spec = {
  nodes: {
    doc: { content: "block+" },
    paragraph: { content: "inline*", group: "block" },
    image: {
      inline: true,
      group: "inline",
      attrs: {
        src: { validate: "string" },
        alt: { default: nil, validate: "string|null" }
      }
    },
    text: { group: "inline" }
  },
  marks: {
    em: {},
    link: {
      attrs: {
        href: { validate: "string" }
      }
    }
  }
}
```

Rules enforced during schema construction:

- the schema must define the top node, `doc` by default
- the schema must define `text`
- `text` must not have attrs
- a name cannot be both a node and a mark
- content expressions must reference known node names or node groups
- content expressions cannot mix inline and block content
- required content positions must be generatable
- mark expressions must reference known mark names or mark groups

Supported attr validators are ProseMirror primitive strings:

```ruby
{ validate: "string" }
{ validate: "string|null" }
{ validate: "number|boolean|null" }
```

The primitive names are `string`, `number`, `boolean`, `null`, and `undefined`.

Ruby callable validators are also accepted in in-memory schema specs:

```ruby
attrs: {
  id: {
    validate: ->(value) { raise "invalid id" unless value.to_s.match?(/\A[a-z0-9-]+\z/) }
  }
}
```

Callable validators are useful in Ruby code, but they cannot come from JSON exported by ProseMirror.

## OrderedMap Schema JSON

ProseMirror's `schema.spec` may serialize ordered maps as alternating name/spec arrays under `content`. This shape is accepted.

```ruby
schema_spec = {
  "nodes" => {
    "content" => [
      "doc", { "content" => "paragraph+" },
      "paragraph", { "content" => "text*" },
      "text", {}
    ]
  },
  "marks" => {
    "content" => [
      "em", {}
    ]
  }
}
```

## Document Validation

Document JSON is the same shape produced by ProseMirror's `Node#toJSON`.

```ruby
document = {
  type: "doc",
  content: [
    {
      type: "paragraph",
      content: [
        { type: "text", text: "hello" }
      ]
    }
  ]
}
```

Full validation checks:

- known node types
- known mark types
- text nodes have string text
- text nodes are not empty
- required attrs are present
- defaults are applied
- unsupported attrs are rejected
- attr validators pass
- child content matches the parent content expression
- marks are allowed by the parent node
- mark sets are ordered and compatible with `excludes`

Example:

```ruby
schema = ProseMirrorValidator::Schema.from_spec(schema_spec)
checked_node = schema.validate_document!(document)
checked_node.to_json_object
```

## Update Validation

Update validation applies ProseMirror step JSON in order.

```ruby
steps = [
  {
    stepType: "replace",
    from: 6,
    to: 6,
    slice: {
      content: [{ type: "text", text: "!" }]
    }
  },
  {
    stepType: "addMark",
    from: 1,
    to: 6,
    mark: { type: "em" }
  }
]

updated_node = ProseMirrorValidator::Updates.validate_steps!(
  document: document,
  schema_spec: schema_spec,
  steps: steps
)
```

Every step receives the document produced by the previous step. The returned node is the final validated document.

## Supported Step JSON

### `replace`

Replaces the document range from `from` to `to` with a slice.

```ruby
{
  stepType: "replace",
  from: 1,
  to: 6,
  slice: {
    content: [{ type: "text", text: "new text" }],
    openStart: 0,
    openEnd: 0
  }
}
```

`slice` may be omitted or `nil` to delete the range.

### `replaceAround`

Replaces a range while preserving a gap and inserting it into the provided slice.

```ruby
{
  stepType: "replaceAround",
  from: 0,
  to: 7,
  gapFrom: 0,
  gapTo: 7,
  insert: 1,
  slice: {
    content: [{ type: "blockquote" }]
  }
}
```

### `addMark`

Adds a mark to inline content in a range.

```ruby
{
  stepType: "addMark",
  from: 1,
  to: 6,
  mark: { type: "em" }
}
```

### `removeMark`

Removes a mark from inline content in a range.

```ruby
{
  stepType: "removeMark",
  from: 1,
  to: 6,
  mark: { type: "em" }
}
```

### `addNodeMark`

Adds a mark to the node at `pos`.

```ruby
{
  stepType: "addNodeMark",
  pos: 1,
  mark: {
    type: "link",
    attrs: { href: "https://example.test" }
  }
}
```

### `removeNodeMark`

Removes a mark from the node at `pos`.

```ruby
{
  stepType: "removeNodeMark",
  pos: 1,
  mark: {
    type: "link",
    attrs: { href: "https://example.test" }
  }
}
```

### `attr`

Updates an attribute on the node at `pos`.

```ruby
{
  stepType: "attr",
  pos: 1,
  attr: "src",
  value: "new.png"
}
```

### `docAttr`

Updates an attribute on the top document node.

```ruby
{
  stepType: "docAttr",
  attr: "version",
  value: 2
}
```

## Return Values

Bang methods return domain objects and raise on failure.

```ruby
node = ProseMirrorValidator::Validator.validate!(document, schema_spec)
updated_node = ProseMirrorValidator::Updates.validate_steps!(
  document: document,
  schema_spec: schema_spec,
  steps: steps
)
```

Boolean methods return only `true` or `false`.

```ruby
ProseMirrorValidator::Validator.valid?(document, schema_spec)
ProseMirrorValidator::Updates.valid_steps?(document: document, schema_spec: schema_spec, steps: steps)
```

Convert a validated node back to ProseMirror JSON:

```ruby
node.to_json_object
```

## Errors

All gem-specific errors inherit from `ProseMirrorValidator::Error`.

```ruby
ProseMirrorValidator::Error
ProseMirrorValidator::SchemaError
ProseMirrorValidator::ContentExpressionError
ProseMirrorValidator::ValidationError
ProseMirrorValidator::TransformError
ProseMirrorValidator::ReplaceError
```

Common failures:

- invalid schema specs raise `SchemaError` or `ContentExpressionError`
- invalid document payloads raise `ValidationError`
- unknown step types, malformed step JSON, failed replacements, and failed update sequences raise `TransformError`
- replacement fitting failures raise `ReplaceError`, a `TransformError` subclass

Example:

```ruby
begin
  ProseMirrorValidator::Validator.validate!(document, schema_spec)
rescue ProseMirrorValidator::Error => error
  warn error.message
end
```

## Notes And Limitations

`prosemirror-validator` is focused on server-side validation. It can check and apply transform steps, but it is not a replacement for `prosemirror-transform` in an editor.

Not implemented:

- transform mapping/rebasing APIs
- transaction metadata
- custom step registration
- `Transform` command helpers such as `replaceRange`, `replaceRangeWith`, or command-level mark helpers
- DOM parser or serializer behavior

## Development

Install dependencies:

```sh
bundle install
```

Run checks:

```sh
bundle exec rake
```

Run only specs:

```sh
bundle exec rspec
```

Run only RuboCop:

```sh
bundle exec rubocop
```

Build the gem:

```sh
gem build prosemirror-validator.gemspec
```

## References

- ProseMirror reference manual: https://prosemirror.net/docs/ref/
- ProseMirror model source: https://github.com/ProseMirror/prosemirror-model
- ProseMirror transform source: https://github.com/ProseMirror/prosemirror-transform
- Fidus Writer Python wrapper: https://github.com/fiduswriter/prosemirror-python

## License

The gem is available as open source under the terms of the MIT License.
