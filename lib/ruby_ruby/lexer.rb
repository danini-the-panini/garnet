# frozen_string_literal: true

require 'ruby_ruby/finite_state_machine'

module RubyRuby
  class Lexer
    class Error < RubyRuby::Error; end

    def initialize(input)
      @pointer = Pointer.new(input, 0, 1, 1)
      @tokens = []
    end

    def tokens
      ProgramLexer.new(@pointer, @tokens).lex
      @tokens
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

      string_contents
      string_start
      string_end
      template_string_start
      template_string_end
      interpolation_start
      interpolation_end

      end_of_input
    ].freeze

    class Token < Struct.new(:type, :value, :line, :column)
      def initialize(*args)
        super

        raise Error.new("Unknown token type `#{type}'") unless TOKEN_TYPES.include?(type)
      end

      def to_s
        "#{line}:#{column} #{type} #{value.inspect}"
      end
    end

    class Pointer < Struct.new(:input, :position, :line, :column)
      def character
        self[position]
      end

      def lookahead(n)
        self[position + n]
      end

      def [](pos)
        input[pos]
      end

      def next_position
        move_position(1)
      end

      def remaining_input
        input[position..-1]
      end

      def move_position(n)
        n.times do
          if character == "\n"
            self.line += 1
            self.column = 1
          else
            self.column += 1
          end
          self.position += 1
        end
      end
    end

    class ProgramLexer
      def initialize(pointer, tokens)
        @pointer = pointer
        @brace_depth = 0
        @finished = false
        @tokens = tokens
      end

      def lex
        process_next_token until @finished
      end

      private

      def process_next_token
        character = @pointer.character

        case character
        when nil
          @finished = true
          @tokens << Token.new(:end_of_input, nil, @pointer.line, @pointer.column)
        when '#'
          recognise_comment
        when /\s/
          recognise_whitespace
        when /[_a-zA-Z]/
          recognise_identifier
        when /[0-9]/
          recognise_number
        when %r{[#{OPERATORS.keys.map{|x|"\\#{x}"}.join}]}
          recognise_operator
        when /[()\[\]]/
          recognise_parenthesis
        when /[{}]/
          recognise_brace
        when "'"
          recognise_string
        when '"'
          recognise_template_string
        else
          raise Error.new("Unrecognised character #{character} at #{@line}:#{@column}")
        end
      end

      def recognise_whitespace
        line = @pointer.line
        column = @pointer.column

        case @pointer.character
        when "\n"
          @pointer.next_position
          @tokens << Token.new(:newline, "\n", line, column)
        when "\r"
          if @pointer.lookahead(1) == "\n"
            @pointer.move_position(2)
            @tokens << Token.new(:newline, "\r\n", line, column)
            return
          end
          @pointer.next_position
          @tokens << Token.new(:space, "\r", line, column)
        else
          result = @pointer.remaining_input.partition(/\n|\r\n|\S/).first
          @pointer.move_position(result.length)
          @tokens << Token.new(:space, result, line, column)
        end
      end

      def recognise_comment
        line = @pointer.line
        column = @pointer.column

        result = @pointer.remaining_input.partition(/(\n|\r\n)/)

        @pointer.move_position(result.length)

        @tokens << Token.new(:comment, result, line, column)
      end

      def recognise_identifier
        position = @pointer.position
        line = @pointer.line
        column = @pointer.column
        identifier = @pointer[position]

        position += 1
        while position < @pointer.input.length
          character = @pointer[position]

          break if character !~ /[a-zA-Z0-9_]/

          identifier += character
          position += 1
        end

        @pointer.move_position(identifier.length)

        @tokens << Token.new(:identifier, identifier, line, column)
      end

      def recognise_number
        line = @pointer.line
        column = @pointer.column

        fsm = build_number_recogniser
        fsm_input = @pointer.remaining_input.partition("\n").first

        number = fsm.run(fsm_input)

        if number
          @pointer.move_position(number.length)

          @tokens << Token.new(:number, number, line, column)
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

      def recognise_operator
        character = @pointer.character

        position = @pointer.position
        line = @pointer.line
        column = @pointer.column

        @pointer.next_position

        lookahead1 = @pointer.lookahead(1)
        lookahead2 = @pointer.lookahead(2)

        first_match = OPERATORS[character]
        value = character

        if lookahead1 && (second_match = first_match[lookahead1])
          @pointer.next_position
          value += lookahead1

          if second_match.is_a?(Hash)
            if lookahead2 && (third_match = second_match[lookahead2])
              @pointer.next_position
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

        @tokens << Token.new(:operator, value, line, column)
      end

      def find_operator_match(match, lookahead)
        match[lookahead] || match[nil]
      end

      def recognise_parenthesis
        character = @pointer.character
        line = @pointer.line
        column = @pointer.column

        @pointer.next_position

        type = case character
              when '(' then :left_parenthesis
              when ')' then :right_parenthesis
              when '[' then :left_bracket
              when ']' then :right_bracket
              end

        @tokens << Token.new(type, character, line, column)
      end

      def recognise_brace
        character = @pointer.character
        line = @pointer.line
        column = @pointer.column

        case character
        when '{'
          @brace_depth += 1
          @pointer.next_position
          @tokens << Token.new(:left_brace, '{', line, column)
        when '}'
          if @brace_depth == 0
            @finished = true
          else
            @brace_depth -= 1
            @pointer.next_position
            @tokens << Token.new(:right_brace, '{', line, column)
          end
        end
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
        character = @pointer.character
        line = @pointer.line
        column = @pointer.column

        @pointer.next_position

        @tokens << Token.new(:string_start, character, line, column)

        StringLexer.new(@pointer, @tokens, character, false).lex
      end

      def recognise_template_string
        character = @pointer.character
        line = @pointer.line
        column = @pointer.column

        @pointer.next_position

        @tokens << Token.new(:template_string_start, character, line, column)

        StringLexer.new(@pointer, @tokens, character, true).lex
      end
    end

    class StringLexer
      def initialize(pointer, tokens, boundry, template)
        @pointer = pointer
        @tokens = tokens
        @finished = false
        @boundry = boundry
        @template = template
      end

      def lex
        process_next_token until @finished
      end

      def process_next_token
        character = @pointer.character

        case character
        when nil
          @finished = true
          @tokens << Token.new(:end_of_input, nil, @pointer.line, @pointer.column)
        when @boundry
          recognise_string_boundry
        when /#/
          @template ? recognise_interpolation : recognise_contents
        else
          recognise_contents
        end
      end

      def recognise_string_boundry
        character = @pointer.character
        line = @pointer.line
        column = @pointer.column

        @pointer.next_position

        @finished = true
        @tokens << Token.new(@template ? :template_string_end : :string_end, @boundry, line, column)
      end

      def recognise_contents
        line = @pointer.line
        column = @pointer.column

        fsm = build_string_recogniser
        fsm_input = @pointer.remaining_input

        result = fsm.run(fsm_input)
        if result
          @pointer.move_position(result.length)
          @tokens << Token.new(:string_contents, result, line, column)
        end
      end

      def recognise_interpolation
        character = @pointer.character
        line = @pointer.line
        column = @pointer.column

        lookahead = @pointer.lookahead(1)

        if lookahead == '{'
          @pointer.move_position(2)
          @tokens << Token.new(:interpolation_start, '#{', line, column)
          ProgramLexer.new(@pointer, @tokens).lex
          recognise_interpolation_end
        else
          recognise_contents
        end
      end

      def recognise_interpolation_end
        character = @pointer.character
        line = @pointer.line
        column = @pointer.column

         if character == '}'
           @pointer.next_position
           @tokens << Token.new(:interpolation_end, '}', line, column)
         end
      end

      def build_string_recogniser
        states = %i[
          initial
          string
          begin_escape
        ]

        fsm = FiniteStateMachine.new(states, :initial, %i[string]) do |current_state, character|
          case current_state
          when :string, :initial
            case character
            when @boundry
              nil
            when '\\'
              :begin_escape
            when '#'
              @template ? nil : :string
            else
              :string
            end
          when :begin_escape
            :string
          end
        end
      end
    end
  end
end