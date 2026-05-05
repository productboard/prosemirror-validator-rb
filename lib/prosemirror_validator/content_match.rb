# frozen_string_literal: true

require_relative 'errors'

module ProseMirrorValidator
  class ContentMatch
    Edge = Struct.new(:type, :next, keyword_init: true)

    attr_reader :next_edges

    def initialize(valid_end)
      @valid_end = valid_end
      @next_edges = []
    end

    def valid_end?
      @valid_end
    end

    def match_type(type)
      next_edges.each do |edge|
        return edge.next if edge.type.equal?(type)
      end

      nil
    end

    def match_fragment(fragment, start_index = 0, end_index = fragment.child_count)
      current = self
      index = start_index

      while current && index < end_index
        current = current.match_type(fragment.child(index).type)
        index += 1
      end

      current
    end

    def inline_content?
      !next_edges.empty? && next_edges.first.type.inline?
    end

    def compatible?(other)
      next_edges.any? do |edge|
        other.next_edges.any? { |other_edge| edge.type.equal?(other_edge.type) }
      end
    end

    def to_s
      seen = []
      scan = lambda do |match|
        seen << match
        match.next_edges.each { |edge| scan.call(edge.next) unless seen.include?(edge.next) }
      end
      scan.call(self)

      seen.each_with_index.map do |match, index|
        edges = match.next_edges.map { |edge| "#{edge.type.name}->#{seen.index(edge.next)}" }.join(', ')
        "#{index}#{match.valid_end? ? '*' : ' '} #{edges}"
      end.join("\n")
    end

    def self.parse(expression, node_types)
      stream = TokenStream.new(expression.to_s, node_types)
      return empty if stream.next_token.nil?

      parsed_expression = Parser.parse_expression(stream)
      stream.error!('Unexpected trailing text') if stream.next_token

      match = DeterministicFiniteAutomaton.compile(NondeterministicFiniteAutomaton.compile(parsed_expression))
      DeadEndChecker.check!(match, stream)
      match
    end

    def self.empty
      @empty ||= new(true).freeze
    end

    class TokenStream
      attr_accessor :position, :inline
      attr_reader :expression, :node_types, :tokens

      def initialize(expression, node_types)
        @expression = expression
        @node_types = node_types
        @position = 0
        @inline = nil
        @tokens = expression.scan(/\w+|\S/)
      end

      def next_token
        tokens[position]
      end

      def consume_token?(token)
        return false unless next_token == token

        self.position += 1
        true
      end

      def error!(message)
        raise ContentExpressionError, "#{message} (in content expression '#{expression}')"
      end
    end

    class Parser
      def self.parse_expression(stream)
        expressions = []

        loop do
          expressions << parse_sequence(stream)
          break unless stream.consume_token?('|')
        end

        expressions.one? ? expressions.first : { type: :choice, expressions: expressions }
      end

      def self.parse_sequence(stream)
        expressions = []

        while stream.next_token && stream.next_token != ')' && stream.next_token != '|'
          expressions << parse_subscript(stream)
        end

        expressions.one? ? expressions.first : { type: :sequence, expressions: expressions }
      end

      def self.parse_subscript(stream)
        expression = parse_atom(stream)

        loop do
          expression = { type: :plus, expression: expression } if stream.consume_token?('+')
          expression = { type: :star, expression: expression } if stream.consume_token?('*')
          expression = { type: :optional, expression: expression } if stream.consume_token?('?')
          expression = parse_range(stream, expression) if stream.consume_token?('{')
          break unless ['+', '*', '?', '{'].include?(stream.next_token)
        end

        expression
      end

      def self.parse_range(stream, expression)
        minimum = parse_number(stream)
        maximum = minimum

        if stream.consume_token?(',')
          maximum = stream.next_token == '}' ? -1 : parse_number(stream)
        end
        stream.error!('Unclosed braced range') unless stream.consume_token?('}')

        { type: :range, minimum: minimum, maximum: maximum, expression: expression }
      end

      def self.parse_number(stream)
        token = stream.next_token
        stream.error!("Expected number, got '#{token}'") unless token&.match?(/\A\d+\z/)

        stream.position += 1
        token.to_i
      end

      def self.parse_atom(stream)
        if stream.consume_token?('(')
          expression = parse_expression(stream)
          stream.error!('Missing closing paren') unless stream.consume_token?(')')
          return expression
        end

        token = stream.next_token
        stream.error!("Unexpected token '#{token}'") unless token&.match?(/\A\w+\z/)

        expressions = resolve_name(stream, token).map do |type|
          if stream.inline.nil?
            stream.inline = type.inline?
          elsif stream.inline != type.inline?
            stream.error!('Mixing inline and block content')
          end

          { type: :name, value: type }
        end

        stream.position += 1
        expressions.one? ? expressions.first : { type: :choice, expressions: expressions }
      end

      def self.resolve_name(stream, name)
        direct_type = stream.node_types[name]
        return [direct_type] if direct_type

        result = stream.node_types.values.select { |node_type| node_type.in_group?(name) }
        stream.error!("No node type or group '#{name}' found") if result.empty?
        result
      end
    end

    class NondeterministicFiniteAutomaton
      AutomatonEdge = Struct.new(:term, :to, keyword_init: true)

      def self.compile(expression)
        new.compile(expression)
      end

      def initialize
        @states = [[]]
      end

      def compile(expression)
        connect(compile_expression(expression, 0), create_state)
        @states
      end

      private

      def create_state
        @states.push([])
        @states.length - 1
      end

      def add_edge(from, to = nil, term = nil)
        edge = AutomatonEdge.new(term: term, to: to)
        @states[from].push(edge)
        edge
      end

      def connect(edges, to)
        edges.each { |edge| edge.to = to }
      end

      def compile_expression(expression, from)
        case expression.fetch(:type)
        when :choice
          expression.fetch(:expressions).flat_map { |child| compile_expression(child, from) }
        when :sequence
          compile_sequence(expression.fetch(:expressions), from)
        when :star
          compile_star(expression.fetch(:expression), from)
        when :plus
          compile_plus(expression.fetch(:expression), from)
        when :optional
          [add_edge(from)] + compile_expression(expression.fetch(:expression), from)
        when :range
          compile_range(expression, from)
        when :name
          [add_edge(from, nil, expression.fetch(:value))]
        else
          raise Error, 'Unknown content expression type'
        end
      end

      def compile_sequence(expressions, from)
        expressions.each_with_index do |expression, index|
          edges = compile_expression(expression, from)
          return edges if index == expressions.length - 1

          from = create_state.tap { |state| connect(edges, state) }
        end
      end

      def compile_star(expression, from)
        loop_state = create_state
        add_edge(from, loop_state)
        connect(compile_expression(expression, loop_state), loop_state)
        [add_edge(loop_state)]
      end

      def compile_plus(expression, from)
        loop_state = create_state
        connect(compile_expression(expression, from), loop_state)
        connect(compile_expression(expression, loop_state), loop_state)
        [add_edge(loop_state)]
      end

      def compile_range(expression, from)
        current = from
        expression.fetch(:minimum).times do
          next_state = create_state
          connect(compile_expression(expression.fetch(:expression), current), next_state)
          current = next_state
        end

        if expression.fetch(:maximum) == -1
          connect(compile_expression(expression.fetch(:expression), current), current)
        else
          (expression.fetch(:maximum) - expression.fetch(:minimum)).times do
            next_state = create_state
            add_edge(current, next_state)
            connect(compile_expression(expression.fetch(:expression), current), next_state)
            current = next_state
          end
        end

        [add_edge(current)]
      end
    end

    class DeterministicFiniteAutomaton
      def self.compile(nfa)
        new(nfa).compile
      end

      def initialize(nfa)
        @nfa = nfa
        @labeled = {}
      end

      def compile
        explore(null_from(0))
      end

      private

      attr_reader :nfa, :labeled

      def explore(states)
        output = []

        states.each do |state|
          nfa[state].each do |edge|
            next unless edge.term

            target = output.find { |term, _nodes| term.equal?(edge.term) }
            null_from(edge.to).each do |node|
              unless target
                target = [edge.term, []]
                output << target
              end
              target.last << node unless target.last.include?(node)
            end
          end
        end

        state = labeled[states.join(',')] = ContentMatch.new(states.include?(nfa.length - 1))
        output.each do |term, next_states|
          sorted_states = sort_states(next_states)
          state.next_edges << Edge.new(
            type: term,
            next: labeled[sorted_states.join(',')] || explore(sorted_states)
          )
        end
        state
      end

      def null_from(state)
        result = []
        scan_null_edges(state, result)
        sort_states(result)
      end

      def scan_null_edges(state, result)
        edges = nfa[state]
        return scan_null_edges(edges.first.to, result) if edges.length == 1 && !edges.first.term

        result << state
        edges.each do |edge|
          next if edge.term || result.include?(edge.to)

          scan_null_edges(edge.to, result)
        end
      end

      def sort_states(states)
        states.sort.reverse
      end
    end

    class DeadEndChecker
      def self.check!(match, stream)
        work = [match]
        index = 0

        while index < work.length
          state = work[index]
          dead = !state.valid_end?
          nodes = []

          state.next_edges.each do |edge|
            nodes << edge.type.name
            dead = false if dead && !edge.type.text? && !edge.type.required_attrs?
            work << edge.next unless work.include?(edge.next)
          end

          if dead
            stream.error!(
              "Only non-generatable nodes (#{nodes.join(', ')}) in a required position " \
              '(see https://prosemirror.net/docs/guide/#generatable)'
            )
          end

          index += 1
        end
      end
    end
  end
end
