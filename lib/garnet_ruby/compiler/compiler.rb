module GarnetRuby
  class Compiler
    class CompilationError < StandardError
      attr_reader :compilation_error, :node

      def initialize(message, node = nil)
        @compilation_error = message
        location = "(#{node.file}:#{node.line})" rescue "(?:?)"
        super("COMPILATION ERROR: #{message} #{location}")
      end

      def self.from(error, node)
        new(error.compilation_error, error.node || node)
      end
    end

    class NodelessCompilationError < StandardError
      attr_reader :compilation_error

      def node
        nil
      end

      def initialize(message)
        @compilation_error = message
        super("COMPILATION ERROR: #{message}")
      end
    end

    class CallInfo
      attr_reader :mid, :argc, :flags, :block_iseq

      def initialize(mid, argc, flags, block_iseq = nil)
        @mid = mid
        @argc = argc
        @flags = flags
        @block_iseq = block_iseq
      end

      def inspect
        things = [
          mid && "mid:#{mid}",
          "argc:#{argc}",
          flags.map { |f| f.to_s.upcase}.join('|'),
          block_iseq
        ].compact.join(', ')
        "<callinfo!#{things}>"
      end
      alias to_s inspect

      def splat?
        flags.include?(:splat)
      end
    end

    class Label
      attr_reader :line

      def initialize(iseq)
        @iseq = iseq
        @insns = []
        @line = nil
      end

      def add(line = @iseq.instructions.length)
        @line = line
        @insns.each do |insns|
          insns.arguments[0] = @line
        end
        @insns = nil
      end

      def ref(ins)
        if @line
          ins.arguments[0] = @line
        else
          @insns << ins
        end
      end
    end

    def initialize(iseq)
      @iseq = iseq
    end

    def debug_dump_iseq
      return unless __grb_debug__?

      puts "Iseq:#{@iseq.name}"
      unless @iseq.catch_table.empty?
        puts "== catch table"
        puts @iseq.catch_table.map { |cr| "| #{cr}" }.join("\n")
      end
      puts "local table: #{@iseq.local_table}"
      @iseq.debug_dump_instructions
      puts
    end

    def compile_nodes(nodes, debug=true)
      nodes.each do |node|
        compile(node)
      end

      unless @iseq.instructions.last&.type == :leave
        case @iseq.type
        when :main, :top, :method
          add_instruction(:leave, :return)
        when :class, :rescue, :eval
          add_instruction(:leave)
        else
          add_instruction(:leave, :next)
        end
      end

      return unless debug

      debug_dump_iseq if debug
    end

    def compile_node(node)
      compile_nodes([node])
    end

    def compile_block_node(node)
      @iseq.start_label = new_label
      @iseq.end_label = new_label
      add_label(@iseq.start_label)
      compile_nodes([node])
      add_label_at_line(@iseq.end_label, @iseq.instructions.length - 1)
    end

    def compile_resbodies(resbodies)
      resbodies.each do |resbody|
        compile_resbody(resbody)
      end

      add_get_local(:"\#$!")
      add_instruction(:throw, :continue)

      debug_dump_iseq
    end

    def compile_resbody(resbody)
      match, lvar = nil, nil?

      if resbody[1].length >= 2
        match = resbody[1][1]
      end
      if resbody[1].length == 3
        lvar = resbody[1][2][1]
      end

      end_label = new_label
      add_get_local(:"\#$!")
      if match
        compile(match)
      else
        add_instruction(:put_object, Core.eStandardError)
      end
      add_instruction(:check_match, :rescue, [])
      add_instruction_with_label(:branch_unless, end_label)

      if lvar
        add_get_local(:"\#$!")
        add_set_local(lvar)
        add_instruction(:pop)
      end

      nodes = resbody[2].nil? ? [[:nil]] : resbody[2..-1]
      compile_nodes(nodes, false)
      add_label(end_label)
    end

    def compile_ensure_body(ensure_body)
      compile(ensure_body)
      add_instruction(:pop)
      add_get_local(:"\#$!")
      add_instruction(:throw, :continue)

      debug_dump_iseq
    end

    def compile(node)
      raise NodelessCompilationError.new("NOT A NODE: #{node.inspect}") unless node.is_a?(Array)

      node = s(*node) unless node.is_a?(Sexp)
      @node = node

      method_name = :"compile_#{node[0]}"
      raise CompilationError.new("Unknown Node Type #{node[0]}", node) unless respond_to?(method_name)

      begin
        __send__(method_name, node)
      rescue CompilationError => e
        raise CompilationError.from(e, node)
      rescue => e
        raise CompilationError.new("Error compiling #{node[0]}: #{e.class}", node)
      end

      @node = node
    end

    def node_position(node)
      "#{node.file}:#{node.line}"
    end

    def compile_lit(node)
      case node[1]
      when Integer, Float
        add_instruction(:put_object, RPrimitive.from(node[1]))
      when Symbol
        add_instruction(:put_object, RSymbol.from(node[1]))
      when Range
        add_instruction(:put_object, RRange.from(node[1]))
      when Regexp
        add_instruction(:put_object, RRegexp.from(node[1]))
      else
        raise "UNKNOWN_LITERAL: #{node[1].inspect} (#{node.file}:#{node.line})"
      end
    end

    def compile_block(node)
      node[1..-2].each do |n|
        compile(n)
        @node = n
        add_instruction(:pop)
      end
      compile(node[-1])
    end

    def compile_begin(node)
      compile(node[1])
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

    def compile_dstr_nodes(nodes)
      nodes.each do |n|
        case n
        when String
          add_instruction(:put_string, n)
        else
          compile(n)
        end
      end
    end

    def compile_dstr(node)
      compile_dstr_nodes(node[1..-1])
      add_instruction(:concat_strings, node.length - 1)
    end

    def compile_dsym(node)
      compile_dstr(node)
      add_instruction(:intern)
    end

    def compile_xstr(node)
      add_instruction(:put_self)
      add_instruction(:put_string, node[1])
      add_instruction(:send_without_block, CallInfo.new(:`, 1, [:simple]))
    end

    def compile_dxstr(node)
      add_instruction(:put_self)
      compile_dstr(node)
      add_instruction(:send_without_block, CallInfo.new(:`, 1, [:simple]))
    end

    def compile_dregx(node)
      len = node.length - 1
      if node[-1].is_a?(Integer)
        options = node[-1]
        len -= 1
      end
      compile_dstr_nodes(node[1..(options ? -2 : -1)])
      add_instruction(:to_regexp, options, len)
    end

    def compile_dregx_once(node)
      # TODO: actually do something fancy here
      compile_dregx(node)
    end

    def compile_evstr(node)
      compile(node[1])
      add_instruction(:send_without_block, CallInfo.new(:to_s, 0, [:simple]))
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

    def compile_dot2(node)
      compile_new_range(node, false)
    end

    def compile_dot3(node)
      compile_new_range(node, true)
    end

    def compile_new_range(node, excl)
      compile(node[1])
      if node[2]
        compile(node[2])
      else
        add_instruction(:put_nil)
      end
      add_instruction(:new_range, excl)
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

    def compile_masgn(node)
      locals = node[1][1..-1]
      case node[2][0]
      when :to_ary
        compile(node[2][1])
        add_instruction(:dup)
      when :splat
        compile(node[2][1])
        add_instruction(:splat_array, true)
        add_instruction(:dup)
      when :array
        compile(node[2])
        add_instruction(:dup)
      end
      i = locals.index { |l| l[0] == :splat}
      if i.nil?
        add_instruction(:expand_array, locals.count, false, false)
        locals.each do |l|
          compile_assignment(l)
          add_instruction(:pop)
        end
      else
        pre = locals[0...i]
        splat = locals[i]
        post = locals[(i + 1)..-1]

        add_instruction(:expand_array, pre.count, true, false)
        pre.each do |l|
          compile_assignment(l)
          add_instruction(:pop)
        end
        if post.empty?
          compile_assignment(splat[1])
          add_instruction(:pop)
        else
          add_instruction(:expand_array, post.count, true, true)
          compile_assignment(splat[1])
          add_instruction(:pop)
          post.each do |l|
            compile_assignment(l)
            add_instruction(:pop)
          end
        end
      end
    end

    def compile_assignment(node)
      return if node.nil?

      case node[0]
      when :lasgn
        add_set_local(node[1])
      when :iasgn
        add_instruction(:set_instance_variable, node[1])
      when :attrasgn
        compile(node[1])
        argc, flags = compile_call_args(node)
        add_instruction(:putn, argc + 1)
        argc += 1
        add_instruction(:send_without_block, CallInfo.new(node[2], argc, flags))
        add_instruction(:pop)
      when :gasgn
        add_instruction(:set_global, node[1])
      when :cvdecl, :cvasgn
        add_instruction(:set_class_variable, node[1])
      end
    end

    def compile_hash_elements(nodes)
      nodes.each do |n|
        compile(n)
      end
      nodes.length
    end

    def compile_kwsplat(node)
      compile(node[1])
      add_instruction(:hash_merge_kwd)
    end

    def compile_hash(node)
      if node.length == 1
        add_instruction(:new_hash, 0)
        return
      end

      slices = node[1..-1].slice_when { |a, b| a[0] == :kwsplat || b[0] == :kwsplat }.to_a
      if slices[0][0][0] != :kwsplat
        n = compile_hash_elements(slices.shift)
        add_instruction(:new_hash, n)
      else
        add_instruction(:new_hash, 0)
      end
      slices.each do |nodes|
        if nodes[0][0] == :kwsplat
          compile(nodes[0])
        else
          n = compile_hash_elements(nodes)
          add_instruction(:hash_merge_ptr, n)
        end
      end
    end

    def compile_or(node)
      compile_boolean_op(node, :branch_if)
    end

    def compile_and(node)
      compile_boolean_op(node, :branch_unless)
    end

    def compile_not(node)
      if (%i[match2 match3].include?(node[1][0]))
        compile_regex_match_not(node[1])
      elsif node[1][0] == :call
        compile(node[1])
        add_instruction(:not)
      end
    end

    def compile_boolean_op(node, branch_type)
      end_label = new_label

      compile(node[1])
      add_instruction(:dup)
      add_instruction_with_label(branch_type, end_label)
      add_instruction(:pop)
      compile(node[2])
      add_label(end_label)
    end

    def compile_if(node)
      else_label = new_label
      end_label = new_label

      cond, if_branch, else_branch = node[1..3]
      compile(cond)
      add_instruction_with_label(:branch_unless, else_label)
      compile(if_branch || [:nil])
      add_instruction_with_label(:jump, end_label)
      add_label(else_label)
      compile(else_branch || [:nil])
      add_label(end_label)
    end

    def compile_case(node)
      *whens, else_block = node[2..-1]
      else_block ||= [:nil]

      when_labels = whens.map { new_label }
      end_label = new_label

      compile(node[1])

      whens.each_with_index do |w, i|
        w[1][1..-1].each do |c|
          add_instruction(:dup)
          flags = []

          if c[0] == :splat
            compile(c[1])
            add_instruction(:splat_array, false)
            flags << :array
          else
            compile(c)
          end

          add_instruction(:check_match, :case, flags)
          add_instruction_with_label(:branch_if, when_labels[i])
        end
      end

      add_instruction(:pop)
      compile(else_block)
      add_instruction_with_label(:jump, end_label)

      whens.each_with_index do |w, i|
        add_label(when_labels[i])
        add_instruction(:pop)

        w[2..-2].each do |n|
          compile(n)
          add_instruction(:pop)
        end

        compile(w[-1]) unless w[-1].nil?

        unless i == whens.length - 1
          add_instruction_with_label(:jump, end_label)
        end
      end

      add_label(end_label)
    end

    def compile_while(node)
      compile_loop(node, :branch_if)
    end

    def compile_until(node)
      compile_loop(node, :branch_unless)
    end

    def compile_loop(node, branch_type)
      cond, body = node[1..2]

      prev_start_label = @iseq.start_label
      prev_redo_label = @iseq.redo_label

      next_label = @iseq.start_label = new_label
      redo_label = @iseq.redo_label = new_label
      end_label = new_label

      # TODO: figure out what the hell this is supposed to be...
      add_instruction_with_label(:jump, next_label)
      add_instruction(:put_nil)
      add_instruction(:pop)
      add_instruction_with_label(:jump, next_label)

      add_label(redo_label)
      compile(body)
      add_instruction(:pop)

      add_label(next_label)
      compile(cond)
      add_instruction_with_label(branch_type, redo_label)

      add_instruction(:put_nil)

      add_label(end_label)
      add_instruction(:nop)

      @iseq.add_catch_type(:break, redo_label.line, end_label.line, end_label.line, @iseq)

      @iseq.start_label = prev_start_label
      @iseq.redo_label = prev_redo_label
    end

    def compile_lvar(node)
      add_get_local(node[1])
    end

    def compile_lasgn(node)
      compile(node[2])
      add_set_local(node[1])
    end

    def compile_cdecl(node)
      id = compile_const_base(node[1])
      compile(node[2])
      add_instruction(:set_constant, id)
    end

    def compile_colon2(node)
      compile(node[1])
      add_instruction(:get_constant, node[2])
    end

    def compile_colon3(node)
      add_instruction(:put_object, Core.cObject)
      add_instruction(:get_constant, node[1])
    end

    def compile_const(node)
      id = compile_const_base(node[1])
      add_instruction(:get_constant, id)
    end

    def compile_gasgn(node)
      compile(node[2])
      add_instruction(:set_global, node[1])
    end

    def compile_gvar(node)
      add_instruction(:get_global, node[1])
    end

    def compile_iasgn(node)
      compile(node[2])
      add_instruction(:set_instance_variable, node[1])
    end

    def compile_ivar(node)
      add_instruction(:get_instance_variable, node[1])
    end

    def compile_cvdecl(node)
      compile(node[2])
      add_instruction(:set_class_variable, node[1])
    end

    def compile_cvasgn(node)
      compile(node[2])
      add_instruction(:set_class_variable, node[1])
    end

    def compile_cvar(node)
      add_instruction(:get_class_variable, node[1])
    end

    def compile_back_ref(node)
      add_instruction(:get_special, 1, node[1])
    end

    def compile_nth_ref(node)
      add_instruction(:get_special, 1, node[1])
    end

    def compile_const_base(node)
      if node.is_a?(Symbol)
        add_instruction(:put_special_object, :const_base)
        return node
      elsif node[0] == :colon2
        compile(node[1])
        return node[2]
      else
        raise "UNKNOWN CONST BASE: #{node}"
      end
    end

    def compile_class(node)
      _, name, super_class, *nodes = node
      flags = []
      if super_class
        flags << :has_superclass
      else
        super_class = [:nil]
      end
      type = :class
      id = compile_const_base(name)
      flags << :scoped unless id == name

      class_iseq = Iseq.new("<class:#{id}>", :class, @iseq)
      compiler = Compiler.new(class_iseq)
      compiler.compile_nodes(nodes)

      compile(super_class)
      add_instruction(:define_class, id, class_iseq, type, flags)
    end

    def compile_module(node)
      _, name, *nodes = node
      flags = []
      type = :module
      if name.is_a?(Symbol)
        add_instruction(:put_special_object, :const_base)
        id = name
      else
        flags << :scoped
        # TODO: scoped class definitions
      end

      class_iseq = Iseq.new("<module:#{id}>", :class, @iseq)
      compiler = Compiler.new(class_iseq)
      compiler.compile_nodes(nodes)

      add_instruction(:put_nil)
      add_instruction(:define_class, id, class_iseq, type, flags)
    end

    def compile_sclass(node)
      _, target, *nodes = node

      class_iseq = Iseq.new('singleton class', :class, @iseq)
      compiler = Compiler.new(class_iseq)
      compiler.compile_nodes(nodes)

      compile(target)
      add_instruction(:put_nil)
      add_instruction(:define_class, :singleton_class, class_iseq, :singleton_class, [])
    end

    def compile_defn(node)
      _, mid, args, *nodes = node

      method_iseq = Iseq.new(mid.to_s, :method, @iseq, {})
      compiler = Compiler.new(method_iseq)
      populate_local_table(args[1..-1], compiler, method_iseq)
      compiler.compile_nodes(nodes)

      add_instruction(:put_object, RSymbol.new(Core.cSymbol, 0, mid))
      add_instruction(:put_iseq, method_iseq)
      add_instruction(:define_method)
    end

    def compile_defs(node)
      _, target, mid, args, *nodes = node

      method_iseq = Iseq.new(mid.to_s, :method, @iseq, {})
      compiler = Compiler.new(method_iseq)
      populate_local_table(args[1..-1], compiler, method_iseq)
      compiler.compile_nodes(nodes)

      compile(target)
      add_instruction(:put_object, RSymbol.new(Core.cSymbol, 0, mid))
      add_instruction(:put_iseq, method_iseq)
      add_instruction(:define_singleton_method)
    end

    def compile_alias(node)
      compile(node[1])
      compile(node[2])
      add_instruction(:set_method_alias)
    end

    def compile_undef(node)
      compile(node[1])
      add_instruction(:undefine_method)
    end

    def compile_return(node)
      if node.length > 1
        compile(node[1])
      else
        add_instruction(:put_nil)
      end
      case @iseq.type
      when :method, :main, :top
        add_instruction(:leave, :return)
      when :class
        raise CompilationError, 'Invalid return in class/module body'
      else
        add_instruction(:throw, :return)
      end
    end

    def compile_next(node)
      if node.length > 1
        compile(node[1])
      else
        add_instruction(:put_nil)
      end
      if @iseq.redo_label
        add_instruction(:pop)
        add_instruction_with_label(:jump, @iseq.start_label)
      else
        add_instruction(:leave, :next)
      end
    end

    def compile_redo(node)
      add_instruction_with_label(:jump, @iseq.start_label)
      # if @iseq.redo_label
      #   add_instruction_with_label(:jump, @iseq.start_label)
      # elsif @iseq.end_label
      #   add_instruction_with_label(:jump, @iseq.end_label)
      # else
      #   # TODO: ??
      # end
    end

    def compile_retry(node)
      add_instruction(:throw, :retry)
    end

    def compile_break(node)
      if node.length > 1
        compile(node[1])
      else
        add_instruction(:put_nil)
      end
      add_instruction(:throw, :break)
    end

    def compile_rescue(node)
      block, *resbodies = node[1..-1]

      else_block = resbodies.pop if resbodies.last[0] != :resbody

      start_label = new_label
      end_label = new_label
      cont_label = new_label

      local_table = { :"\#$!" => [:exception] }
      rescue_iseq = Iseq.new("rescue in #{@iseq.name}", :rescue, @iseq, local_table)
      compiler = Compiler.new(rescue_iseq)
      compiler.compile_resbodies(resbodies)

      add_label(start_label)
      compile(block)
      add_label(end_label)
      compile(else_block) if else_block
      add_instruction(:nop)
      add_label(cont_label)

      @iseq.add_catch_type(:rescue, start_label.line, end_label.line, cont_label.line, rescue_iseq)
      @iseq.add_catch_type(:retry, end_label.line, cont_label.line, start_label.line, rescue_iseq)
    end

    def compile_ensure(node)
      block, ensure_body = node[1..-1]

      local_table = { :"\#$!" => [:exception] }
      ensure_iseq = Iseq.new("ensure in #{@iseq.name}", :ensure, @iseq, local_table)
      compiler = Compiler.new(ensure_iseq)
      compiler.compile_ensure_body(ensure_body)

      start_label = new_label
      end_label = new_label
      cont_label = new_label

      add_label(start_label)
      compile(block)
      add_label(end_label)
      compile(ensure_body)
      add_label(cont_label)
      add_instruction(:pop)

      @iseq.add_catch_type(:ensure, start_label.line, end_label.line, cont_label.line, ensure_iseq)
    end

    def compile_defined(node)
      # TODO: some fancy logic
      add_instruction(:put_object, RString.from('expression'))
    end

    def compile_call(node, safe = false)
      end_label = new_label if safe

      if @iseq.type == :eval && !node[1] && node.length == 3 && @iseq.can_find_local?(node[2])
        add_get_local(node[2])
        return
      end

      if node[1]
        compile(node[1])
      else
        add_instruction(:put_self)
      end

      if safe
        add_instruction(:dup)
        add_instruction_with_label(:branch_nil, end_label)
      end

      argc, flags = compile_call_args(node)
      add_instruction(:send_without_block, CallInfo.new(node[2], argc, flags))

      add_label(end_label) if safe
    end

    def compile_safe_call(node)
      compile_call(node, true)
    end

    def compile_yield(node)
      argc, flags = compile_args(node[1..-1])
      add_instruction(:invoke_block, CallInfo.new(nil, argc, flags))
    end

    def compile_super(node)
      argc, flags = compile_args(node[1..-1])
      add_instruction(:invoke_super, CallInfo.new(nil, argc, flags | [:super]))
    end

    def compile_zsuper(node)
      argc, flags = compile_zsuper_args
      add_instruction(:invoke_super, CallInfo.new(nil, argc, flags))
    end

    def compile_iter(node)
      st = @iseq.instructions.length
      end_label = new_label

      block_args = node[2] == 0 ? [] : node[2][1..-1]
      block_iseq = Iseq.new("block in #{@iseq.name}", :block, @iseq, {})
      compiler = Compiler.new(block_iseq)
      populate_local_table(block_args, compiler, block_iseq)
      compiler.compile_block_node(node[3] || [:nil])

      call_node = node[1]
      if call_node[0] == :lambda
        mid = :lambda
        add_instruction(:put_self)
        argc = 0
        flags = [:simple]
      else
        mid = call_node[2]
        if call_node[1]
          compile(call_node[1])
        else
          add_instruction(:put_self)
        end

        if call_node[0] == :safe_call
          add_instruction(:dup)
          add_instruction_with_label(:branch_nil, end_label)
        end

        argc, flags = compile_call_args(call_node)
      end

      add_instruction(:send, CallInfo.new(mid, argc, flags, block_iseq))
      add_label(end_label)
      add_instruction(:nop)

      ed = end_label.line
      @iseq.add_catch_type(:break, st, ed, ed, block_iseq)
    end

    def compile_for(node)
      st = @iseq.instructions.length

      block_iseq = Iseq.new("block in #{@iseq.name}", :block, @iseq, {})
      compiler = Compiler.new(block_iseq)
      populate_local_table(for_block_args(node[2]), compiler, block_iseq)
      compiler.compile_block_node(node[3])

      compile(node[1])
      add_instruction(:send, CallInfo.new(:each, 0, [:simple], block_iseq))
      add_instruction(:nop)

      ed = @iseq.instructions.length - 1
      @iseq.add_catch_type(:break, st, ed, ed, block_iseq)
    end

    def for_block_args(node)
      case node[0]
      when :lasgn
        [node[1]]
      when :masgn
        node[1][1..-1].map do |n|
          case n[0]
          when :lasgn then n[1]
          when :splat then :"*#{n[1][1]}"
          end
        end
      end
    end

    def populate_local_table(args, compiler, iseq)
      splatted = false
      args.each do |a|
        if a.is_a?(Symbol)
          s = a.to_s
          case s
          when /^\*\*/
            iseq.local_table[s[2..-1].to_sym] = [:kwsplat]
          when /^\*/
            id = s == :* ? :"?" : s[1..-1].to_sym
            iseq.local_table[id] = [:splat]
            splatted = true
          when /^&/
            iseq.local_table[s[1..-1].to_sym] = [:block]
          else
            iseq.local_table[a] = splatted ? [:post] : [:arg]
          end
        elsif a.nil?
          iseq.local_table[:_] = splatted ? [:post] : [:arg]
        elsif a[0] == :lasgn
          iseq.local_table[a[1]] = [:opt]
          compiler.compile(a)
          compiler.add_instruction(:pop)
          iseq.local_table[a[1]][1] = iseq.instructions.length
        elsif a[0] == :kwarg
          iseq.local_table[:'?'] = [:kwargs]
          iseq.local_table[a[1]] = [:kwarg]
          compiler.compile_kwarg(a)
        end
      end
    end
    
    def compile_kwarg(node)
      end_label = new_label

      add_get_local(:'?')

      if node.length == 3
        kwarg_label = new_label
        add_instruction(:put_object, RSymbol.from(node[1]))
        add_instruction(:send_without_block, CallInfo.new(:key?, 1, [:simple]))
        add_instruction_with_label(:branch_if, kwarg_label)

        compile(node[2])
        add_instruction_with_label(:jump, end_label)

        add_label(kwarg_label)
        add_get_local(:'?')
      end

      add_instruction(:put_object, RSymbol.from(node[1]))
      add_instruction(:send_without_block, CallInfo.new(:[], 1, [:simple]))

      add_label(end_label)
      add_set_local(node[1])
      add_instruction(:pop)
    end

    def compile_attrasgn(node, safe = false)
      end_label = new_label if safe

      add_instruction(:put_nil)
      compile(node[1])

      if safe
        add_instruction(:dup)
        add_instruction_with_label(:branch_nil, end_label)
      end

      argc, flags = compile_call_args(node)
      add_instruction(:setn, argc + 1)
      add_instruction(:send_without_block, CallInfo.new(node[2], argc, flags))
      add_instruction(:pop)

      add_label(end_label) if safe
    end

    def compile_safe_attrasgn(node)
      compile_attrasgn(node, true)
    end

    def compile_op_asgn_or(node)
      compile_op_asgn_or_and(node, :branch_if)
    end

    def compile_op_asgn_and(node)
      compile_op_asgn_or_and(node, :branch_unless)
    end

    def compile_op_asgn_or_and(node, branch_type)
      end_label = new_label

      compile(node[1])
      add_instruction(:dup)
      add_instruction_with_label(branch_type, end_label)
      add_instruction(:pop)
      compile(node[2])

      add_label(end_label)
    end

    def compile_op_asgn1(node)
      add_instruction(:put_nil)
      compile(node[1])
      argc, flags = compile_argslist(node[2])
      compile_op_asgn_generic(node, :[], :[]=, argc, flags)
    end

    def compile_op_asgn2(node)
      add_instruction(:put_nil)
      compile(node[1])
      compile_op_asgn_generic(node, node[2].to_s[0..-2].to_sym, node[2], 0, [:simple])
    end

    def compile_op_asgn_generic(node, getter, setter, argc, flags)
      add_instruction(:dupn, argc + 1)
      add_instruction(:send_without_block, CallInfo.new(getter, argc, [:simple]))
      case node[3]
      when :'||', :'&&'
        match_label = new_label
        end_label = new_label
        add_instruction(:dup)
        add_instruction_with_label(node[3] == :'&&' ? :branch_unless : :branch_if, match_label)
        add_instruction(:pop)
        compile(node[4])
        add_instruction(:send_without_block, CallInfo.new(setter, argc + 1, flags))
        add_instruction(:pop)
        add_instruction_with_label(:jump, end_label)
        add_label(match_label)
        add_instruction(:setn, argc + 2)
        add_instruction(:adjust_stack, argc + 2)
        add_label(end_label)
      else
        compile(node[4])
        add_instruction(:send_without_block, CallInfo.new(node[3], 1, [:simple]))
        add_instruction(:setn, argc + 2)
        add_instruction(:send_without_block, CallInfo.new(setter, argc + 1, flags))
        add_instruction(:pop)
      end
    end

    def compile_match2(node)
      # TODO: compile to optimised regexp_match instruction
      compile_regex_match(node)
    end

    def compile_match3(node)
      # TODO: compile to optimised regexp_match instruction
      compile_regex_match(node)
    end

    def compile_regex_match(node, mid = :=~)
      left, right = node[1..2]
      compile(left)
      compile(right)
      add_instruction(:send_without_block, CallInfo.new(mid, 1, [:simple]))
    end

    def compile_regex_match_not(node)
      compile_regex_match(node, :'!~')
    end

    def compile_call_args(node)
      compile_args(node[3..-1])
    end

    def compile_argslist(node)
      compile_args(node[1..-1])
    end

    def compile_args(args)
      flags = []
      has_splat = args.find { |x| x[0] == :splat }
      block_pass = args.delete_at(-1) if args.find { |x| x[0] == :block_pass }
      slices = args.slice_when { |a, b| a[0] == :splat || b[0] == :splat }.to_a
      count = 0
      if has_splat
        if slices[0][0][0] == :splat
          pargs = []
        else
          pargs = slices[0]
          slices = slices[1..-1]
        end
        count = pargs.count + 1
        flags << :splat
      else
        pargs = args
        count = pargs.count
        flags << :simple
      end
      pargs.each do |n|
        compile(n)
      end
      if has_splat
        slices.each_with_index do |slice, index|
          if slice[0][0] == :splat
            compile(slice[0][1])
            add_instruction(:splat_array, index != slices.count - 1)
          else
            slice.each do |a|
              compile(a)
            end
            add_instruction(:new_array, slice.count)
          end
        end
        (slices.count - 1).times do
          add_instruction(:concat_array)
        end
      end
      if block_pass
        flags << :blockarg
        compile(block_pass[1])
      end
      [count, flags]
    end

    def compile_zsuper_args
      args = @iseq.local_table.to_a
      count = args.count { |_, v| [:arg, :opt, :splat].include?(v[0]) }
      post_count = args.count { |k, v| v[0] == :post }
      has_splat = args.find { |_, x| x[0] == :splat }
      flags = has_splat ? [:splat] : [:simple]
      args.each do |k, v|
        case v[0]
        when :arg, :opts, :post
          add_get_local(k)
        when :splat
          add_get_local(k)
          add_instruction(:splat_array, false)
        end
      end
      if post_count.positive?
        add_instruction(:new_array, post_count)
        add_instruction(:concat_array)
      end
      [count, flags]
    end

    def new_label
      Label.new(@iseq)
    end

    def add_label(label)
      label.add
    end

    def add_label_at_line(label, line)
      label.add(line)
    end

    def add_instruction(type, *args, node: @node)
      @iseq.add_instruction(node, type, *args)
    end

    def add_instruction_with_label(type, label, node: @node)
      @iseq.add_instruction(node, type, nil).tap { |i| label.ref(i) }
    end

    def add_set_local(name, node: @node)
      level = @iseq.local_level(name)
      pi = @iseq
      level.times { pi = pi.parent_iseq }
      if pi.local_table.dig(name, 0) == :block
        add_instruction(:set_block_param_proxy, name, level, node: node)
      else
        add_instruction(:set_local, name, level, node: node)
      end
    end

    def add_get_local(name, node: @node)
      level = @iseq.local_level(name)
      pi = @iseq
      level.times { pi = pi.parent_iseq }
      if pi.local_table.dig(name, 0) == :block
        add_instruction(:get_block_param_proxy, name, level, node: node)
      else
        add_instruction(:get_local, name, level, node: node)
      end
    end
  end
end
