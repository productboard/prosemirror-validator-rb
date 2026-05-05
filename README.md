# prosemirror-validator

`prosemirror-validator` is a Ruby 3.3+ gem for validating ProseMirror document data.

The gem scope is validation only. It is not intended to transform documents, render content, sanitize HTML, or provide an editor runtime.

## What It Validates

The implementation mirrors the validation-oriented parts of `prosemirror-model`:

- schema construction from ProseMirror schema specs, including OrderedMap-shaped JSON from `schema.spec`
- content expressions with names, groups, sequences, choices, `*`, `+`, `?`, and `{min,max}` ranges
- document JSON loading through `Schema#node_from_json`
- full recursive validation through `Node#check!` and `Schema#validate_document!`
- node and mark attributes, required/default attrs, and primitive `validate` strings
- mark ordering and `excludes` rules
- parent content rules for allowed marks

Transforms, steps, DOM parsing, serialization to HTML, editor state, and rendering are intentionally out of scope.

## Usage

```ruby
require "prosemirror_validator"

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
    { type: "paragraph", content: [{ type: "text", text: "hello", marks: [{ type: "em" }] }] }
  ]
}

ProseMirrorValidator::Validator.validate!(document, schema_spec)
ProseMirrorValidator::Validator.valid?(document, schema_spec)
```

`validate!` returns the checked `ProseMirrorValidator::Node` and raises a `ProseMirrorValidator::Error` subclass when validation fails. `valid?` returns a boolean.

For lower-level access:

```ruby
schema = ProseMirrorValidator::Schema.from_spec(schema_spec)
node = schema.node_from_json(document)
node.check!
```

`node_from_json` follows ProseMirror's construction behavior and does not recursively validate child content by itself. Call `check!`, `validate_document!`, or `Validator.validate!` when you need full payload validation.

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

## References

- ProseMirror reference manual: https://prosemirror.net/docs/ref/
- Fidus Writer Python wrapper: https://github.com/fiduswriter/prosemirror-python
- ProseMirror model source: https://github.com/ProseMirror/prosemirror-model

## License

The gem is available as open source under the terms of the MIT License.
