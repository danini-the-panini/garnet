module RubyRuby
  class Compiler
    def initialize(iseq)
      @iseq = iseq
    end

    def compile_nodes(nodes)
      nodes.each do |node|
        compile(node)
      end

      add_instruction(:leave) unless @iseq.instructions.last&.type == :leave

      puts "Iseq:#{@iseq.name}"
      puts "local table: #{@iseq.local_table}"
      @iseq.debug_dump_instructions
      puts
    end

    def compile_node(node)
      compile_nodes([node])
    end

    def compile(node)
      method_name = :"compile_#{node[0]}"
      raise "COMPILE_ERROR: Unknown Node Type #{node[0]} (#{node.file}:#{node.line})" unless respond_to?(method_name)

      __send__(method_name, node)
    end

    def compile_lit(node)
      case node[1]
      when Integer
        add_instruction(:put_object, RPrimitive.new(Core.cInteger, 0, node[1]))
      when Float
        add_instruction(:put_object, RPrimitive.new(Core.cFloat, 0, node[1]))
      when Symbol
        add_instruction(:put_object, RSymbol.new(Core.cSymbol, 0, node[1]))
      when Range
        # TODO
      when Regexp
        # TODO
      else
        raise "UNKNOWN_LITERAL: #{node[1].inspect} (#{node.file}:#{node.line})"
      end
    end

    def compile_block(node)
      node[1..-2].each do |n|
        compile(n)
        add_instruction(:pop)
      end
      compile(node[-1])
    end

    def compile_true(node)
      add_instruction(:put_object, Q_TRUE)
    end

    def compile_false(node)
      add_instruction(:put_object, Q_FALSE)
    end

    def compile_nil(node)
      add_instruction(:put_nil)
    end

    def compile_self(node)
      add_instruction(:put_self)
    end

    def compile_str(node)
      add_instruction(:put_string, node[1])
    end

    def compile_dstr(node)
      node[1..-1].each do |n|
        case n
        when String
          add_instruction(:put_string, n)
        else
          compile(n)
        end
      end
      add_instruction(:concat_strings, node.length - 1)
    end

    def compile_evstr(node)
      compile(node[1])
      add_instruction(:send, :to_s, 0)
    end

    def compile_array(node)
      if node.length == 1
        add_instruction(:new_array, 0)
        return
      end
      chunks = node[1..-1].chunk { |n| n[0] == :splat }.to_a
      if chunks[0][0]
        compile(chunks[0][1][0][1])
        add_instruction(:splat_array, true)
        chunks.slice!(0)
      else
        nodes = chunks.slice!(0)[1]
        array_from_nodes(nodes)
      end
      chunks.each do |splat, n|
        if splat
          compile(n[0][1])
        else
          array_from_nodes(n)
        end
        add_instruction(:concat_array)
      end
    end

    def compile_svalue(node)
      compile(node[1][1])
      add_instruction(:splat_array, true)
    end

    def array_from_nodes(nodes)
      nodes.each do |n|
        compile(n)
      end
      add_instruction(:new_array, nodes.count)
    end

    def compile_hash(node)
      node[1..-1].each do |n|
        compile(n)
      end
      add_instruction(:new_hash, node.length - 1)
    end

    def compile_or(node)
      compile(node[1])
      add_instruction(:dup)
      branch_insn = add_instruction(:branch_if, nil)
      add_instruction(:pop)
      compile(node[2])
      branch_insn.arguments[0] = @iseq.instructions.length
    end

    def compile_if(node)
      cond, if_branch, else_branch = node[1..3]
      compile(cond)
      branch_insn = add_instruction(:branch_unless, nil)
      compile(if_branch || [:nil])
      jump_insn = add_instruction(:jump, nil)
      branch_insn.arguments[0] = @iseq.instructions.length
      compile(else_branch || [:nil])
      jump_insn.arguments[0] = @iseq.instructions.length if jump_insn
    end

    def compile_lvar(node)
      add_instruction(:get_local, node[1], @iseq.local_level)
    end

    def compile_lasgn(node)
      compile(node[2])
      add_instruction(:set_local, node[1], @iseq.local_level)
    end

    def compile_cdecl(node)
      compile(node[2])
      add_instruction(:set_constant, node[1])
    end

    def compile_const(node)
      add_instruction(:get_constant, node[1])
    end

    def compile_gasgn(node)
      compile(node[2])
      add_instruction(:set_global, node[1])
    end

    def compile_gvar(node)
      add_instruction(:get_global, node[1])
    end

    def compile_defn(node)
      mid = node[1]
      args = node[2]
      nodes = node[3..-1]

      local_table = args[1..-1].map { |a| [a, :arg] }.to_h
      method_iseq = Iseq.new(mid.to_s, :method, @iseq, local_table)
      compiler = Compiler.new(method_iseq)
      compiler.compile_nodes(nodes)

      add_instruction(:put_object, RSymbol.new(Core.cSymbol, 0, mid))
      add_instruction(:put_iseq, method_iseq)
      add_instruction(:define_method)
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

    def compile_attrasgn(node)
      add_instruction(:put_nil)
      compile(node[1])
      argc = compile_args(node)
      add_instruction(:setn, argc + 1)
      add_instruction(:send, node[2], argc)
    end

    def compile_op_asgn_or(node)
      compile_op_asgn_or_and(node, :branch_if)
    end

    def compile_op_asgn_and(node)
      compile_op_asgn_or_and(node, :branch_unless)
    end

    def compile_op_asgn_or_and(node, branch_type)
      compile(node[1])
      add_instruction(:dup)
      branch_insn = add_instruction(branch_type, nil)
      add_instruction(:pop)
      compile(node[2][2])
      add_instruction(:dup)
      add_instruction(:set_local, node[2][1], @iseq.local_level)
      branch_insn.arguments[0] = @iseq.instructions.length
    end

    def compile_op_asgn1(node)
      add_instruction(:put_nil)
      compile(node[1])
      argc = compile_argslist(node[2])
      add_instruction(:dupn, argc + 1)
      add_instruction(:send, :[], argc)
      case node[3]
      when :'||', :'&&'
        add_instruction(:dup)
        branch_insn = add_instruction(node[3] == :'&&' ? :branch_unless : :branch_if, nil)
        add_instruction(:pop)
        compile(node[4])
        add_instruction(:send, :[]=, argc + 1)
        add_instruction(:pop)
        jump_insn = add_instruction(:jump, nil)
        branch_insn.arguments[0] = @iseq.instructions.length
        add_instruction(:setn, argc + 2)
        add_instruction(:adjust_stack, argc + 2)
        jump_insn.arguments[0] = @iseq.instructions.length
      else
        compile(node[4])
        add_instruction(:send, node[3], 1)
        add_instruction(:setn, argc + 2)
        add_instruction(:send, :[]=, argc + 1)
        add_instruction(:pop)
      end
    end

    def compile_args(node)
      argc = node.length - 3
      node[3..-1].each do |n|
        compile(n)
      end
      argc
    end

    def compile_argslist(node)
      argc = node.length - 1
      node[1..-1].each do |n|
        compile(n)
      end
      argc
    end

    def add_instruction(type, *args)
      @iseq.add_instruction(type, *args)
    end
  end
end
