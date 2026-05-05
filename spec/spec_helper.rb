# frozen_string_literal: true

RSpec.configure do |configuration|
  configuration.disable_monkey_patching!
  configuration.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end
