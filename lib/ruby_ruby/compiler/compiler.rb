module RubyRuby
  class Compiler
    def initialize(iseq)
      @iseq = iseq
    end

    def compile(node)
      method_name = :"compile_#{node[0]}"
      raise "COMPILE_ERROR: Unknown Node Type #{node[0]}" unless respond_to?(method_name)

      __send__(method_name, node)
    end

    def compile_lit(node)
      case node[1]
      when Integer
        add_instruction(:put_object, node[1])
      when Float
        # TODO
      when Range
        # TODO
      when Regexp
        # TODO
      else
        raise "UNKNOWN_LITERAL: #{node[1].inspect}"
      end
    end

    def compile_true(node)
      add_instruction(:put_object, Q_TRUE)
    end

    def compile_false(node)
      add_instruction(:put_object, Q_FALSE)
    end

    def compile_nil(node)
      add_instruction(:put_object, Q_NIL)
    end

    def compile_call(node)
      if node[1]
        compile(node[1])
      else
        add_instruction(:put_self)
      end
      argc = compile_args(node)
      add_instruction(:send, node[2], argc)
    end

    def compile_args(node)
      argc = node.length - 3
      node[3..-1].each do |n|
        compile(n)
      end
      argc
    end

    def add_instruction(type, *args)
      @iseq.add_instruction(type, *args)
    end
  end
end
