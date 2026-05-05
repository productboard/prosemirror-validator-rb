# frozen_string_literal: true

require_relative 'errors'
require_relative 'fragment'
require_relative 'mark'
require_relative 'slice'
require_relative 'utils'

module ProseMirrorValidator
  class StepResult
    attr_reader :doc, :failed

    def initialize(doc, failed)
      @doc = doc
      @failed = failed
    end

    def self.ok(doc)
      new(doc, nil)
    end

    def self.fail(message)
      new(nil, message)
    end

    def self.from_replace(doc, from, to, slice)
      ok(doc.replace(from, to, slice))
    rescue ReplaceError => e
      fail(e.message)
    end
  end

  class Step
    STEP_TYPES = {}.freeze

    def self.from_json(schema, json)
      raise TransformError, 'Invalid input for Step.fromJSON' if json.nil? || !Utils.key?(json, 'stepType')

      step_class = registered_step_types[Utils.fetch_value(json, 'stepType')]
      raise TransformError, "No step type #{Utils.fetch_value(json, 'stepType')} defined" unless step_class

      step_class.from_json(schema, json)
    end

    def self.register_json_id(id, step_class)
      registered_step_types[id] = step_class
    end

    def self.registered_step_types
      @registered_step_types ||= {}
    end
  end

  class ReplaceStep < Step
    attr_reader :from, :to, :slice, :structure

    def initialize(from, to, slice, structure: false)
      super()
      @from = from
      @to = to
      @slice = slice
      @structure = structure
    end

    def apply(doc)
      return StepResult.fail('Structure replace would overwrite content') if structure && content_between?(doc, from,
                                                                                                           to)

      StepResult.from_replace(doc, from, to, slice)
    end

    def self.from_json(schema, json)
      from = Utils.fetch_value(json, 'from')
      to = Utils.fetch_value(json, 'to')
      raise TransformError, 'Invalid input for ReplaceStep.fromJSON' unless from.is_a?(Numeric) && to.is_a?(Numeric)

      slice = Slice.from_json(schema, Utils.fetch_value(json, 'slice'))
      new(from, to, slice, structure: !!Utils.fetch_value(json, 'structure'))
    end

    private

    def content_between?(doc, from, to)
      resolved_from = doc.resolve(from)
      distance = to - from
      depth = resolved_from.depth

      while distance.positive? && depth.positive? &&
            resolved_from.index_after(depth) == resolved_from.node(depth).child_count
        depth -= 1
        distance -= 1
      end

      return false unless distance.positive?

      child = resolved_from.node(depth).maybe_child(resolved_from.index_after(depth))
      while distance.positive?
        return true if child.nil? || child.leaf?

        child = child.first_child
        distance -= 1
      end

      false
    end
  end

  class ReplaceAroundStep < Step
    attr_reader :from, :to, :gap_from, :gap_to, :slice, :insert, :structure

    def initialize(from, to, gap_from, gap_to, slice, insert, structure: false)
      super()
      @from = from
      @to = to
      @gap_from = gap_from
      @gap_to = gap_to
      @slice = slice
      @insert = insert
      @structure = structure
    end

    def apply(doc)
      if structure && (content_between?(doc, from, gap_from) || content_between?(doc, gap_to, to))
        return StepResult.fail('Structure gap-replace would overwrite content')
      end

      gap = doc.slice(gap_from, gap_to)
      return StepResult.fail('Gap is not a flat range') if gap.open_start.positive? || gap.open_end.positive?

      inserted = slice.insert_at(insert, gap.content)
      return StepResult.fail('Content does not fit in gap') unless inserted

      StepResult.from_replace(doc, from, to, inserted)
    end

    def self.from_json(schema, json)
      values = %w[from to gapFrom gapTo insert].map { |key| Utils.fetch_value(json, key) }
      raise TransformError, 'Invalid input for ReplaceAroundStep.fromJSON' unless values.all?(Numeric)

      new(
        values[0],
        values[1],
        values[2],
        values[3],
        Slice.from_json(schema, Utils.fetch_value(json, 'slice')),
        values[4],
        structure: !!Utils.fetch_value(json, 'structure')
      )
    end

    private

    def content_between?(doc, from, to)
      ReplaceStep.new(from, to, Slice.empty, structure: true).send(:content_between?, doc, from, to)
    end
  end

  class AddMarkStep < Step
    attr_reader :from, :to, :mark

    def initialize(from, to, mark)
      super()
      @from = from
      @to = to
      @mark = mark
    end

    def apply(doc)
      old_slice = doc.slice(from, to)
      resolved_from = doc.resolve(from)
      parent = resolved_from.node(resolved_from.shared_depth(to))
      slice = Slice.new(map_fragment(old_slice.content, parent), old_slice.open_start, old_slice.open_end)

      StepResult.from_replace(doc, from, to, slice)
    end

    def self.from_json(schema, json)
      from = Utils.fetch_value(json, 'from')
      to = Utils.fetch_value(json, 'to')
      raise TransformError, 'Invalid input for AddMarkStep.fromJSON' unless from.is_a?(Numeric) && to.is_a?(Numeric)

      new(from, to, schema.mark_from_json(Utils.fetch_value(json, 'mark')))
    end

    private

    def map_fragment(fragment, parent)
      Fragment.from_array(
        fragment.content.map.with_index do |child, _index|
          mapped_child = child.content.size.positive? ? child.copy(map_fragment(child.content, child)) : child
          if mapped_child.inline? && mapped_child.atom? && parent.type.allows_mark_type?(mark.type)
            mapped_child.mark(mark.add_to_set(mapped_child.marks))
          else
            mapped_child
          end
        end
      )
    end
  end

  class RemoveMarkStep < Step
    attr_reader :from, :to, :mark

    def initialize(from, to, mark)
      super()
      @from = from
      @to = to
      @mark = mark
    end

    def apply(doc)
      old_slice = doc.slice(from, to)
      slice = Slice.new(map_fragment(old_slice.content), old_slice.open_start, old_slice.open_end)
      StepResult.from_replace(doc, from, to, slice)
    end

    def self.from_json(schema, json)
      from = Utils.fetch_value(json, 'from')
      to = Utils.fetch_value(json, 'to')
      raise TransformError, 'Invalid input for RemoveMarkStep.fromJSON' unless from.is_a?(Numeric) && to.is_a?(Numeric)

      new(from, to, schema.mark_from_json(Utils.fetch_value(json, 'mark')))
    end

    private

    def map_fragment(fragment)
      Fragment.from_array(
        fragment.content.map do |child|
          mapped_child = child.content.size.positive? ? child.copy(map_fragment(child.content)) : child
          mapped_child.inline? ? mapped_child.mark(mark.remove_from_set(mapped_child.marks)) : mapped_child
        end
      )
    end
  end

  class AddNodeMarkStep < Step
    attr_reader :pos, :mark

    def initialize(pos, mark)
      super()
      @pos = pos
      @mark = mark
    end

    def apply(doc)
      node = doc.node_at(pos)
      return StepResult.fail("No node at mark step's position") unless node

      updated = node.type.create(node.attrs, nil, mark.add_to_set(node.marks))
      StepResult.from_replace(doc, pos, pos + 1, Slice.new(Fragment.from(updated), 0, node.leaf? ? 0 : 1))
    end

    def self.from_json(schema, json)
      pos = Utils.fetch_value(json, 'pos')
      raise TransformError, 'Invalid input for AddNodeMarkStep.fromJSON' unless pos.is_a?(Numeric)

      new(pos, schema.mark_from_json(Utils.fetch_value(json, 'mark')))
    end
  end

  class RemoveNodeMarkStep < Step
    attr_reader :pos, :mark

    def initialize(pos, mark)
      super()
      @pos = pos
      @mark = mark
    end

    def apply(doc)
      node = doc.node_at(pos)
      return StepResult.fail("No node at mark step's position") unless node

      updated = node.type.create(node.attrs, nil, mark.remove_from_set(node.marks))
      StepResult.from_replace(doc, pos, pos + 1, Slice.new(Fragment.from(updated), 0, node.leaf? ? 0 : 1))
    end

    def self.from_json(schema, json)
      pos = Utils.fetch_value(json, 'pos')
      raise TransformError, 'Invalid input for RemoveNodeMarkStep.fromJSON' unless pos.is_a?(Numeric)

      new(pos, schema.mark_from_json(Utils.fetch_value(json, 'mark')))
    end
  end

  class AttrStep < Step
    attr_reader :pos, :attr, :value

    def initialize(pos, attr, value)
      super()
      @pos = pos
      @attr = attr
      @value = value
    end

    def apply(doc)
      node = doc.node_at(pos)
      return StepResult.fail("No node at attribute step's position") unless node

      attrs = node.attrs.merge(attr => value)
      updated = node.type.create(attrs, nil, node.marks)
      StepResult.from_replace(doc, pos, pos + 1, Slice.new(Fragment.from(updated), 0, node.leaf? ? 0 : 1))
    end

    def self.from_json(_schema, json)
      pos = Utils.fetch_value(json, 'pos')
      attr = Utils.fetch_value(json, 'attr')
      raise TransformError, 'Invalid input for AttrStep.fromJSON' unless pos.is_a?(Numeric) && attr.is_a?(String)

      new(pos, attr, Utils.fetch_value(json, 'value'))
    end
  end

  class DocAttrStep < Step
    attr_reader :attr, :value

    def initialize(attr, value)
      super()
      @attr = attr
      @value = value
    end

    def apply(doc)
      StepResult.ok(doc.type.create(doc.attrs.merge(attr => value), doc.content, doc.marks))
    end

    def self.from_json(_schema, json)
      attr = Utils.fetch_value(json, 'attr')
      raise TransformError, 'Invalid input for DocAttrStep.fromJSON' unless attr.is_a?(String)

      new(attr, Utils.fetch_value(json, 'value'))
    end
  end

  Step.register_json_id('replace', ReplaceStep)
  Step.register_json_id('replaceAround', ReplaceAroundStep)
  Step.register_json_id('addMark', AddMarkStep)
  Step.register_json_id('removeMark', RemoveMarkStep)
  Step.register_json_id('addNodeMark', AddNodeMarkStep)
  Step.register_json_id('removeNodeMark', RemoveNodeMarkStep)
  Step.register_json_id('attr', AttrStep)
  Step.register_json_id('docAttr', DocAttrStep)
end
