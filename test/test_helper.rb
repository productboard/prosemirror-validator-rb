# frozen_string_literal: true

require 'minitest/autorun'
require 'prosemirror_validator'

module Minitest
  class Test
    def assert_raises_with_message(exception_class, message_pattern, &)
      error = assert_raises(exception_class, &)

      assert_match(message_pattern, error.message)
    end
  end
end
