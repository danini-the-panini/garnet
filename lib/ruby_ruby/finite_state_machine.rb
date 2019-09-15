# frozen_string_literal: true

module RubyRuby
  class FiniteStateMachine < Struct.new(:states, :initial_state, :accepting_states)
    attr_reader :next_state_function

    def initialize(*args, &block)
      super(*args)
      @next_state_function = block
    end

    def run(input)
      current_state = initial_state
      result = ''
      last_known_good_result = nil

      input.each_char do |character|
        next_state = next_state_function.(current_state, character)
        break if next_state.nil?

        result += character

        last_known_good_result = result if accepting_states.include?(next_state)

        current_state = next_state
      end

      last_known_good_result
    end
  end
end