# frozen_string_literal: true

# Local test runner — simulates Lambda invocation without AWS infrastructure.
$LOAD_PATH.unshift(__dir__)
require_relative 'lambda_function'

puts "Running lambda_handler with test payload..."
result = lambda_handler(event: { 'message' => 'hello from local test' }, context: nil)
puts "Result: #{result.inspect}"
puts "Done. Traces exported to Last9."
