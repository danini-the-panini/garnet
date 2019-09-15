# frozen_string_literal: true

require 'ruby_ruby/finite_state_machine'

module RubyRuby
  class Lexer
    class Error < RubyRuby::Error; end

    def initialize(input)
      @input = input
      @position = 0
      @line = 0
      @column = 0
    end

    def all_tokens
      token = next_token
      tokens = []

      while token.type != :end_of_input
        tokens << token
        token = next_token
      end

      tokens
    end

    def next_token
      if @position >= @input.length
        return Token.new(:end_of_input, '', @line, @column)
      end

      character = @input[@position]

      if character == '#'
        return recognise_comment
      end

      if character =~ /\s/
        return recognise_whitespace
      end

      if character =~ /[_a-zA-Z]/
        return recognize_identifier
      end

      if character =~ /[0-9]/
        return recognize_number
      end

      if OPERATORS.key?(character)
        return recognize_operator
      end

      if character =~ /[(){}\[\]]/
        return recognize_parenthesis
      end

      raise Error.new("Unrecognised character #{character} at #{@line}:#{@column}")
    end

    private

    def recognise_whitespace
      position = @position
      line = @line
      column = @column
      character = @input[position]

      if character == "\n"
        @line += 1
        @column = 0
        @position += 1
        return Token.new(:newline, "\n", line, column)
      elsif character == "\r"
        if @input[position+1] == "\n"
          @line += 1
          @column = 0
          @position += 2
          return Token.new(:newline, "\r\n", line, column)
        end
        return Token.new(:space, "\r", line, column)
      else
        result = ''
        while character =~ /\s/ && character !~ /[\r\n]/
          result += character
          position += 1
          character = @input[position]
        end
        @position += result.length
        @column += result.length
        return Token.new(:space, result, line, column)
      end
    end

    def recognise_comment
      position = @position
      line = @line
      column = @column

      result = @input[position..-1].partition(/(\n|\r\n)/)

      @position += result.length
      @column += result.length

      return Token.new(:comment, result, line, column)
    end

    def recognize_identifier
      position = @position
      line = @line
      column = @column
      identifier = @input[position]

      position += 1
      while position < @input.length
        character = @input[position]

        break if character !~ /[a-zA-Z0-9_]/

        identifier += character
        position += 1
      end

      @position += identifier.length
      @column += identifier.length

      Token.new(:identifier, identifier, line, column)
    end

    def recognize_number
      line = @line
      column = @column

      fsm = build_number_recogniser
      fsm_input = @input[@position..].partition("\n").first

      number = fsm.run(fsm_input)

      if number
        @position += number.length
        @column += number.length

        return Token.new(:number, number, line, column)
      end
    end

    def build_number_recogniser
      states = %i[
        initial
        integer
        begin_number_with_fractional_part
        number_with_fractional_part
        begin_number_with_exponent
        begin_number_signed_exponent
        number_with_exponent
      ]

      fsm = FiniteStateMachine.new(states, :initial, %i[integer number_with_fractional_part number_with_exponent]) do |current_state, character|
        case current_state
        when :initial
          case character
          when /[0-9]/
            :integer
          end
        when :integer
          case character
          when /[0-9]/
            :integer
          when '.'
            :begin_number_with_fractional_part
          when /e/i
            :begin_number_with_exponent
          end
        when :begin_number_with_fractional_part
          case character
          when /[0-9]/
            :number_with_fractional_part
          end
        when :number_with_fractional_part
          case character
          when /[0-9]/
            :number_with_fractional_part
          when /e/i
            :begin_number_with_exponent
          end
        when :begin_number_with_exponent
          case character
          when /[+-]/
            :begin_number_signed_exponent
          when /[0-9]/
            :number_with_exponent
          end
        when :begin_number_signed_exponent
          case character
          when /[0-9]/
            :number_with_exponent
          end
        when :number_with_exponent
          case character
          when /[0-9]/
            :number_with_exponent
          end
        end
      end
    end

    def recognize_operator
      character = @input[@position]

      position = @position
      line = @line
      column = @column
      character = @input[position]

      @position += 1
      @column += 1

      lookahead1 = @input[position + 1]
      lookahead2 = @input[position + 2]

      first_match = OPERATORS[character]
      value = character

      if lookahead1 && (second_match = first_match[lookahead1])
        @position += 1
        @column += 1
        value += lookahead1

        if second_match.is_a?(Hash)
          if lookahead2 && (third_match = second_match[lookahead2])
            @position += 1
            @column += 1
            value += lookahead2

            third_match
          else
            second_match[nil]
          end
        else
          second_match
        end
      else
        first_match[nil]
      end

      Token.new(:operator, value, line, column)
    end

    def find_operator_match(match, lookahead)
      match[lookahead] || match[nil]
    end

    def recognize_parenthesis
      position = @position
      line = @line
      column = @column
      character = @input[position]

      @position += 1
      @column += 1

      type = case character
             when '(' then :left_parenthesis
             when ')' then :right_parenthesis
             when '{' then :left_brace
             when '}' then :right_brace
             when '[' then :left_bracket
             when ']' then :right_bracket
             end

      Token.new(type, character, line, column)
    end

    OPERATORS = {
      '!' => { '=' => true, '~' => true, nil => true }.freeze,
      '~' => { nil => true }.freeze,
      '>' => {
        '=' => true,
        '>' => { '=' => true, nil => true }.freeze,
        nil => true
      }.freeze,
      '<' => {
        '=' => { '>' => true, nil => true }.freeze,
        '<' => { '=' => true, nil => true }.freeze,
        nil => true
      }.freeze,
      '=' => {
        '=' => { '=' => true, nil => true }.freeze,
        '~' => true,
        nil => true
      }.freeze,
      '+' => { '=' => true, nil => true }.freeze,
      '-' => { '=' => true, nil => true }.freeze,
      '*' => {
        '*' => { '=' => true, nil => true }.freeze,
        '=' => true,
        nil => true
      }.freeze,
      '/' => { '=' => true, nil => true }.freeze,
      '%' => { '=' => true, nil => true }.freeze,
      '&' => {
        '&' => { '=' => true, nil => true }.freeze,
        '.' => true,
        '=' => true,
        nil => true
      }.freeze,
      '|' => {
        '|' => { '=' => true, nil => true }.freeze,
        '=' => true,
        nil => true
      }.freeze,
      '^' => { '=' => true, nil => true }.freeze,
      ':' => { ':' => true, nil => true }.freeze,
      '?' => { nil => true }.freeze,
      '.' => { nil => true }.freeze
    }.freeze

    def recognise_string
      line = @line
      column = @column

      fsm = build_number_recogniser
      fsm_input = @input[@position..].partition("\n").first

      number = fsm.run(fsm_input)

      if number
        @position += number.length
        @column += number.length

        return Token.new(:number, number, line, column)
      end
    end

    TOKEN_TYPES = %i[
      keyword
      identifier
      number
      operator
      space
      newline
      comment

      left_parenthesis
      right_parenthesis

      left_bracket
      right_bracket

      left_brace
      right_brace

      end_of_input
    ].freeze

    class Token < Struct.new(:type, :value, :line, :column)
      def to_s
        "#{type} `#{value}'"
      end
    end
  end
end