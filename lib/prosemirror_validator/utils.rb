# frozen_string_literal: true

module ProseMirrorValidator
  module Utils
    module_function

    def fetch_value(hash, key, default = nil)
      return default unless hash.respond_to?(:key?)

      string_key = key.to_s
      symbol_key = key.to_sym
      return hash[string_key] if hash.key?(string_key)
      return hash[symbol_key] if hash.key?(symbol_key)

      default
    end

    def key?(hash, key)
      return false unless hash.respond_to?(:key?)

      hash.key?(key.to_s) || hash.key?(key.to_sym)
    end

    def normalize_hash(hash)
      return {} if hash.nil?

      hash.to_h.transform_keys(&:to_s)
    end

    def ordered_pairs(value)
      if value.respond_to?(:key?) && key?(value, 'content') && fetch_value(value, 'content').is_a?(Array)
        fetch_value(value, 'content').each_slice(2).map { |name, spec| [name.to_s, spec || {}] }
      else
        value.to_h.map { |name, spec| [name.to_s, spec || {}] }
      end
    end

    def deep_equal?(left, right)
      case [left, right]
      in [Hash, Hash]
        return false unless left.size == right.size

        left.all? { |key, value| right.key?(key) && deep_equal?(value, right[key]) }
      in [Array, Array]
        left.size == right.size && left.zip(right).all? { |a, b| deep_equal?(a, b) }
      else
        left == right
      end
    end
  end
end
