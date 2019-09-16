# frozen_string_literal: true

require 'ruby_ruby/finite_state_machine'

module RubyRuby
  class Lexer
    class Error < RubyRuby::Error; end

    def initialize(input, filename)
      @pointer = Pointer.new(input, 0, 1, 1, filename)
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
      comma
      semicolon
      newline
      comment
      global_variable
      instance_variable
      class_variable

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
      regexp_start
      regexp_end
      subshell_start
      subshell_end
      words_start
      word_boundary
      words_end
      symbols_start
      symbols_end
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

    class Pointer < Struct.new(:input, :position, :line, :column, :filename)
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
        when ','
          recognise_comma
        when ';'
          recognise_semicolon
        when '$'
          recognise_global_variable
        when '@'
          recognise_instance_or_class_variable
        when /[_a-zA-Z]/
          recognise_identifier
        when /[0-9]/
          recognise_number
        when '%'
          recognise_sigil
        when '/'
          recognise_regexp
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
        when '`'
          recognise_subshell_string
        else
          raise Error.new("Unrecognised character #{character.inspect} at #{@pointer.filename}:#{@pointer.line}:#{@pointer.column}")
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

        result = @pointer.remaining_input.partition(/(\n|\r\n)/).first

        @pointer.move_position(result.length)

        @tokens << Token.new(:comment, result, line, column)
      end

      def recognise_comma
        character = @pointer.character
        line = @pointer.line
        column = @pointer.column

        @pointer.next_position

        @tokens << Token.new(:comma, character, line, column)
      end

      def recognise_semicolon
        character = @pointer.character
        line = @pointer.line
        column = @pointer.column

        @pointer.next_position

        @tokens << Token.new(:semicolon, character, line, column)
      end

      def recognise_global_variable
        line = @pointer.line
        column = @pointer.column

        if @pointer.remaining_input =~ /\$([a-zA-Z_][a-zA-Z0-9_]*|[0-9:\*\$\/\\\?_&])/
          identifier = $&
          @pointer.move_position(identifier.length)
          @tokens << Token.new(:global_variable, identifier, line, column)
        end
      end

      def recognise_instance_or_class_variable
        line = @pointer.line
        column = @pointer.column

        lookahead = @pointer.lookahead(1)

        if lookahead == '@'
          @pointer.remaining_input =~ /@@[a-zA-Z_][a-zA-Z0-9_]*/
          identifier = $&
          @pointer.move_position(identifier.length)
          @tokens << Token.new(:class_variable, identifier, line, column)
        else
          @pointer.remaining_input =~ /@[a-zA-Z_][a-zA-Z0-9_]*/
          identifier = $&
          @pointer.move_position(identifier.length)
          @tokens << Token.new(:instance_variable, identifier, line, column)
        end
      end

      def recognise_sigil
        line = @pointer.line
        column = @pointer.column

        lookahead1 = @pointer.lookahead(1)
        lookahead2 = @pointer.lookahead(2)

        case lookahead1
        when '='
          recognise_operator
          return
        when /[^a-zA-Z0-9\s]/
          boundry = sigil_boundry(lookahead1)
          lex_string(:string, "%#{lookahead1}", boundry, true, false)
          return
        when /q/i
          if lookahead2 =~ /[^a-zA-Z0-9\s]/
            boundry = sigil_boundry(lookahead2)
            lex_string(:string, "%#{lookahead1}#{lookahead2}", boundry, lookahead1 == 'Q', false)
            return
          end
        when /w/i
          if lookahead2 =~ /[^a-zA-Z0-9\s]/
            boundry = sigil_boundry(lookahead2)
            lex_string(:words, "%#{lookahead1}#{lookahead2}", boundry, lookahead1 == 'W', true)
            return
          end
        when /i/i
          if lookahead2 =~ /[^a-zA-Z0-9\s]/
            boundry = sigil_boundry(lookahead2)
            lex_string(:symbols, "%#{lookahead1}#{lookahead2}", boundry, lookahead1 == 'I', true)
            return
          end
        when 'r'
          if lookahead2 =~ /[^a-zA-Z0-9\s]/
            boundry = sigil_boundry(lookahead2)
            lex_string(:regexp, "%#{lookahead1}#{lookahead2}", boundry, true, false, /#{boundry}[a-zA-Z]*/)
            return
          end
        when 'x'
          if lookahead2 =~ /[^a-zA-Z0-9\s]/
            boundry = sigil_boundry(lookahead2)
            lex_string(:subshell, "%#{lookahead1}#{lookahead2}", boundry, true, false)
            return
          end
        end

        recognise_operator
      end

      def sigil_boundry(sigil_start)
        case sigil_start
        when '{' then '}'
        when '(' then ')'
        when '[' then ']'
        when '<' then '>'
        else sigin_start
        end
      end

      def recognise_identifier
        line = @pointer.line
        column = @pointer.column

        if @pointer.remaining_input =~ /[a-zA-Z_][a-zA-Z0-9_]*/
          identifier = $&
          @pointer.move_position(identifier.length)
          @tokens << Token.new(:identifier, identifier, line, column)
        end
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

      def recognise_operator
        character = @pointer.character

        line = @pointer.line
        column = @pointer.column

        lookahead1 = @pointer.lookahead(1)
        lookahead2 = @pointer.lookahead(2)

        @pointer.next_position

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
        lex_string(:string, character, character, false, false)
      end

      def recognise_template_string
        character = @pointer.character
        lex_string(:template_string, character, character, true, false)
      end

      def recognise_regexp
        character = @pointer.character
        lookahead = @pointer.lookahead(1)

        if lookahead =~ /\s/
          recognise_operator
          return
        end

        if @tokens[-1]&.type == :space && @tokens[-2]&.type == :number
          recognise_operator
          return
        end

        lex_string(:regexp, character, character, true, false, /#{character}[a-zA-Z]*/)
      end

      def recognise_subshell_string
        character = @pointer.character
        lex_string(:subshell, character, character, true, false)
      end

      def lex_string(name, start_seq, end_seq, template, words, boundry_matcher = /#{end_seq}/)
        line = @pointer.line
        column = @pointer.column
        @pointer.move_position(start_seq.length)
        @tokens << Token.new(:"#{name}_start", start_seq, line, column)
        StringLexer.new(@pointer, @tokens, end_seq, template, words, name, boundry_matcher).lex
      end
    end

    class StringLexer
      def initialize(pointer, tokens, boundry, template, words, name, boundry_matcher)
        @pointer = pointer
        @tokens = tokens
        @finished = false
        @boundry = boundry
        @template = template
        @words = words
        @name = name
        @boundry_matcher = boundry_matcher
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
        when /\s/
          @words ? recognise_word_boundary : recognise_contents
        else
          recognise_contents
        end
      end

      def recognise_string_boundry
        line = @pointer.line
        column = @pointer.column

        if @pointer.remaining_input =~ @boundry_matcher
          result = $&
          @pointer.move_position(result.length)
          @tokens << Token.new(:"#{@name}_end", result, line, column)
          @finished = true
        end
      end

      def recognise_contents
        line = @pointer.line
        column = @pointer.column

        fsm = build_string_recogniser
        fsm_input = @pointer.remaining_input

        result = fsm.run(fsm_input)
        if result
          result = result[0...-1]
          @pointer.move_position(result.length)
          @tokens << Token.new(:string_contents, result, line, column)
        end
      end

      def recognise_word_boundary
        line = @pointer.line
        column = @pointer.column

        if @pointer.remaining_input =~ /\s+/
          result = $&
          @pointer.move_position(result.length)
          @tokens << Token.new(:word_boundary, result, line, column)
        end
      end

      def recognise_interpolation
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
          start_interpolation
          interpolation
          boundry
        ]

        fsm = FiniteStateMachine.new(states, :initial, %i[string boundry start_interpolation]) do |current_state, character|
          case current_state
          when :string, :initial
            case character
            when @boundry
              :boundry
            when '\\'
              :begin_escape
            when '#'
              @template ? :start_interpolation : :string
            when /\s/
              @words ? :boundry : :string
            else
              :string
            end
          when :begin_escape
            :string
          when :start_interpolation
            case character
            when @boundry
              :boundry
            when '{'
              nil
            when '\\'
              :begin_escape
            when '#'
              @template ? :start_interpolation : :string
            when /\s/
              @words ? nil : :string
            else
              :string
            end
          end
        end
      end
    end
  end
end
