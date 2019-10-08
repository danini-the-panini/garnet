module RubyRuby
  class Parser
    def initialize(tokens)
      @tokens = tokens
    end

    def parse
      @tree = []
      @pointer = 0
      while @pointer < @tokens.length
        token = @tokens[@pointer]
        puts token
        case token.type
        when :number
          @tree << construct_number_node(token)
          @pointer += 1
        when :string_start
          @tree << construct_string
          @pointer += 1
        when :identifier
          @tree << construct_identifier_token
          @pointer += 1
        else
          @pointer += 1
        end
        p @tree.map{|x|x.class.name}
      end
      @tree
    end

    private
    
    def construct_number_node(token)
      value = token.value.gsub(/_/, '')
      if value.match?(/[\.e]/i)
        NumberLiteral.new(:float, value.to_f)
      else
        NumberLiteral.new(:integer, value.to_i)
      end
    end

    def construct_string
      @pointer += 1
      string = ""
      while token = @tokens[@pointer]
        break if token.type == :string_end
        string += construct_string_value(token.value)
        @pointer += 1
      end
      StringLiteral.new(string)
    end

    def construct_string_value(string_value)
      # TODO: process escape chars
      string_value
    end

    class Node < Struct.new(:children)
    end

    class Expression < Node; end

    class NumberLiteral < Expression
      def initialize(type, value)
        super([])
        @type = type # float, integer
        @value = value
      end
    end

    class RangeLiteral < Expression
      def initialize(a, b, inclusive)
        super([a, b])
        @inclusive = inclusive
      end
    end

    class StringLiteral < Expression
      def initialize(value)
        super([])
        @value
      end
    end

    class StringTemplate < Expression
      class StringPart < Node
      end

      class ExpressionPart < Node
      end
    end

    class BinaryOp < Node
      def initialize(left, right, op)
        super([left, right])
        @op = op
      end
    end

    class UnaryOp < Node
      def initialize(node, op)
        super([node])
        @op = op
      end
    end

    class MethodCall < Expression
      def intialize(method_name, callee, *args)
        super(callee, *args)
        @method_name = method_name
      end
    end

    class LocalVariableOrMethod < Expression
      def initialize(name)
        super([])
        @name = name
      end
    end
  end
end

=begin

# GRAMMAR

method_call ::= expression [space] dot [space] expression
expression ::= method_call | equation | literal
equation ::= term | term eq_op | term
term ::= expression | expression term_op expression
literal ::= float_literal | integer_literal | string_literal

=end