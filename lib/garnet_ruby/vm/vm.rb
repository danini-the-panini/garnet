module GarnetRuby
  class VM
    class GarnetThrow < StandardError
      attr_reader :throw_type, :value, :cfp, :exc, :tag

      def initialize(throw_type, value, cfp, exc = nil, tag = nil)
        super(throw_type.to_s)
        @throw_type = throw_type
        @value = value
        @cfp = cfp
        @exc = exc
        @tag = tag
      end
    end

    class << self
      attr_reader :instance

      def new(*args)
        @instance ||= super
      end
    end

    class ExecutionError < StandardError
      def initialize(message, insn)
        super("#{message} (#{insn.file}:#{insn.line})")
      end
    end

    attr_reader :special_variables
    attr_accessor :running

    def initialize(top_self)
      $indent = '' if __grb_debug__?
      @top_self = top_self
      @running = false
      @control_frames = []
      @global_variables = {}
      @special_variables = {
        backref: Q_NIL
      }
    end

    def __vm_debug__?
      __grb_debug__? && @running
    end

    def current_control_frame
      @control_frames.last
    end

    def previous_control_frame
      @control_frames[-2]
    end

    def caller_environment(cfp = current_control_frame)
      env = cfp.environment
      env = env.previous until env.previous.nil?
      env
    end

    def execute_main(iseq)
      control_frame = ControlFrame.new(@top_self, iseq, Environment.new(Core.cObject, nil))
      push_control_frame(control_frame)

      begin
        execute(iseq) until @control_frames.empty?
      rescue GarnetThrow => e
        handle_uncaught_throw(e)
      end
    end

    def populate_locals(env, iseq, args)
      offset = 0
      num_locals = iseq.local_table.size
      num_post = iseq.local_table.count { |_, v| v[0] == :post }
      iseq.local_table.each_with_index do |(k, v), i|
        case v[0]
        when :arg
          env.locals[k] = args[i]
        when :post
          env.locals[k] = args[i - num_locals]
        when :opt
          if args[i]
            env.locals[k] = args[i]
            offset = v[1]
          end
        when :splat
          env.locals[k] = RArray.from(args[i, args.length - num_post - i] || [])
        end
      end
      offset
    end

    def execute_method_iseq(target, method, args, block=nil)
      iseq = method.definition.iseq
      env = Environment.new(target.klass, method.definition.environment, {})
      env.method_entry = env
      env.method_object = method
      control_frame = ControlFrame.new(target, iseq, env, block)
      control_frame.pc = populate_locals(env, iseq, args)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop
    end

    def execute_block_iseq(block, args, block_block=nil)
      prev_control_frame = current_control_frame

      iseq = block.iseq
      env = Environment.new(block.self_value.klass, block.environment, {}, block.environment, prev_control_frame.environment.method_entry)
      control_frame = ControlFrame.new(block.self_value, iseq, env, block_block)
      control_frame.pc = populate_locals(env, iseq, args)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop
    end

    def execute_rescue_iseq(iseq, throw_data, prev_control_frame=current_control_frame)
      locals = { :"\#$!" => throw_data.exc }
      env = Environment.new(prev_control_frame.self_value.klass, prev_control_frame.environment, locals, prev_control_frame.environment, prev_control_frame.environment.method_entry)
      env.errinfo = throw_data.exc
      control_frame = ControlFrame.new(prev_control_frame.self_value, iseq, env, prev_control_frame.block)
      control_frame.throw_data = throw_data
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop
    rescue GarnetThrow => e
      handle_rescue_throw(e)
    end

    def execute_class_iseq(iseq, klass)
      prev_control_frame = current_control_frame
      env = Environment.new(klass, prev_control_frame.environment)
      control_frame = ControlFrame.new(klass, iseq, env)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop || Q_NIL
    end

    def execute_eval_iseq(iseq, prev_control_frame = previous_control_frame)
      env = Environment.new(prev_control_frame.klass, prev_control_frame.environment, {}, prev_control_frame.environment)
      control_frame = ControlFrame.new(prev_control_frame.klass, iseq, env)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      control_frame.stack.pop || Q_NIL
    end

    def execute_load_iseq(iseq)
      env = Environment.new(Core.cObject, nil)
      control_frame = ControlFrame.new(@top_self, iseq, env)
      push_control_frame(control_frame)

      execute(iseq) until current_control_frame != control_frame

      Q_NIL
    end

    def execute(iseq)
      control_frame = current_control_frame
      insn = iseq.instructions[control_frame.pc]

      puts "#{$indent}begin : #{insn} for #{control_frame}" if __vm_debug__?

      method_name = :"exec_#{insn.type}"
      raise ExecutionError.new("EXEC_ERROR: Unknown Instruction Type #{insn.type}", insn) unless respond_to?(method_name)

      prev_pc = control_frame.pc
      begin
        __send__(method_name, control_frame, insn)
      rescue GarnetThrow => e
        handle_rescue_throw(e)
      rescue => e
        raise ExecutionError.new(e.message, insn)
      end
      control_frame.pc += 1 if control_frame.pc == prev_pc

      puts "#{$indent}end   : #{insn} for #{control_frame}" if __vm_debug__?
    end

    def exec_leave(control_frame, insn)
      pop_control_frame
      if control_frame.iseq.type == :rescue
        cfp = current_control_frame
        cr = cfp.iseq.catch_table.find do |x|
          x.type == :rescue && x.iseq == control_frame.iseq
        end
        current_control_frame.stack << control_frame.stack.last
        current_control_frame.pc = cr.cont if cr
      end
      if control_frame.iseq.type == :ensure
        cfp = current_control_frame
        cr = cfp.iseq.catch_table.find do |x|
          x.type == :ensure && x.iseq == control_frame.iseq
        end
        current_control_frame.pc = cr.cont if cr
      end
      puts "#{$indent}  --- leave: now executing: #{current_control_frame}" if __vm_debug__?
    end

    def exec_nop(control_frame, insn)
    end

    def exec_pop(control_frame, insn)
      pop_stack
    end

    def exec_dup(control_frame, insn)
      push_stack(peek_stack)
    end

    def exec_swap(control_frame, insn)
      s = control_frame.stack
      s[-1], s[-2] = s[-2], s[-1]
    end

    def exec_put_object(control_frame, insn)
      push_stack insn.arguments[0]
    end

    def exec_put_self(control_frame, insn)
      push_stack control_frame.self_value
    end

    def exec_put_nil(control_frame, insn)
      push_stack Q_NIL
    end

    def exec_put_string(control_frame, insn)
      push_stack RString.from(insn.arguments[0])
    end

    def exec_put_special_object(control_frame, insn)
      type = insn.arguments[0]
      case type
      when :const_base
        push_stack(control_frame.environment.lexical_scope.klass)
      # when :vm_core
      # when :cbase
      end
    end

    def exec_concat_strings(control_frame, insn)
      count = insn.arguments[0]
      strings = pop_stack_multi(count)
      string = RString.from(strings.map(&:string_value).join(''))
      push_stack(string)
    end

    def exec_to_regexp(control_frame, insn)
      options, count = insn.arguments
      strings = pop_stack_multi(count)
      string = RString.from(strings.map(&:string_value).join(''))
      regexp = RRegexp.from_string(string, options)
      push_stack(regexp)
    end

    def exec_new_array(control_frame, insn)
      count = insn.arguments[0]
      items = pop_stack_multi(count)
      array = RArray.from(items)
      push_stack(array)
    end

    def make_array(x)
      case x
      when RArray then x
      when RPrimitive then RArray.from([x])
      else Core.rb_funcall(x, :to_a)
      end
    end

    def dup_array(ary)
      RArray.from(ary.array_value)
    end

    def exec_concat_array(control_frame, insn)
      ary1, ary2 = pop_stack_multi(2).map { |x| make_array(x) }
      ary = RArray.from(ary1.array_value + ary2.array_value)
      push_stack(ary)
    end

    def exec_splat_array(control_frame, insn)
      flag = insn.arguments[0]
      ary = make_array(pop_stack)
      ary = dup_array(ary) if flag
      push_stack(ary)
    end

    def exec_expand_array(control_frame, insn)
      num, is_splat, post = insn.arguments
      ary = make_array(pop_stack).array_value
      len = ary.length
      if post
        (num - len).times { push_stack(Q_NIL) } if len < num
        [num, len].min.times { |j| push_stack(ary[len - j - 1]) }
        if is_splat
          push_stack(RArray.from(ary[0,(len - [num, len].min)]))
        end
      else
        if is_splat
          if num > len
            push_stack(RArray.from([]))
          else
            push_stack(RArray.from(ary[num..-1]))
          end
        end
        (num - 1).downto(0) do |i|
          if len <= i
            push_stack(Q_NIL)
          else
            push_stack(ary[i])
          end
        end
      end
    end

    def exec_new_hash(control_frame, insn)
      count = insn.arguments[0]
      items = pop_stack_multi(count)
      hash = RHash.from(items.each_slice(2).to_a.to_h)
      push_stack(hash)
    end

    def exec_new_range(control_frame, insn)
      excl = insn.arguments[0]
      st, ed = pop_stack_multi(2)
      range = RRange.make(st, ed, excl)
      push_stack(range)
    end

    def exec_put_iseq(control_frame, insn)
      push_stack insn.arguments[0]
    end

    def exec_define_method(control_frame, insn)
      method_iseq = pop_stack
      mid_sym = pop_stack
      mid = mid_sym.symbol_value

      klass = control_frame.environment.lexical_scope.klass
      definition = ISeqMethodDef.new(method_iseq, control_frame.environment)
      method = Core.method_entry_create(mid, klass, :public, definition)
      klass.method_table[mid] = method

      push_stack(mid_sym)
    end

    def exec_define_singleton_method(control_frame, insn)
      method_iseq = pop_stack
      mid_sym = pop_stack
      mid = mid_sym.symbol_value
      target = pop_stack
      singleton = Core.singleton_class_of(target)

      definition = ISeqMethodDef.new(method_iseq, control_frame.environment)
      method = Core.method_entry_create(mid, singleton, :public, definition)
      singleton.method_table[mid] = method

      push_stack(mid_sym)
    end

    def exec_set_method_alias(control_frame, insn)
      new_mid_sym, old_mid_sym = pop_stack_multi(2)
      mid = new_mid_sym.symbol_value

      klass = control_frame.environment.lexical_scope.klass
      original_method = find_method(klass, old_mid_sym.symbol_value, klass)

      definition = AliasMethodDef.new(original_method)
      method = Core.method_entry_create(mid, klass, :public, definition)
      klass.method_table[mid] = method

      push_stack(new_mid_sym)
    end

    def exec_undefine_method(control_frame, insn)
      mid_sym = pop_stack
      mid = mid_sym.symbol_value

      klass = control_frame.environment.lexical_scope.klass
      definition = UndefinedMethodDef.new
      method = Core.method_entry_create(mid, klass, :public, definition)
      klass.method_table[mid] = method

      push_stack(mid_sym)
    end

    def exec_define_class(control_frame, insn)
      id, iseq, type, flags = insn.arguments

      cbase, super_class = pop_stack_multi(2)

      klass = find_or_create_class_by_id(id, type, flags, cbase, super_class)

      ret = execute_class_iseq(iseq, klass)

      push_stack(ret)
    end

    def exec_branch_if(control_frame, insn)
      cond = pop_stack
      control_frame.pc = insn.arguments[0] if rtest(cond)
    end

    def exec_branch_unless(control_frame, insn)
      cond = pop_stack
      control_frame.pc = insn.arguments[0] unless rtest(cond)
    end

    def exec_branch_nil(control_frame, insn)
      cond = pop_stack
      control_frame.pc = insn.arguments[0] if cond == Q_NIL
    end

    def exec_check_match(control_frame, insn)
      target, pattern = pop_stack_multi(2)
      type, flags = insn.arguments
      if flags.include?(:array)
        result = pattern.array_value.any? do |v|
          rtest(Core.check_match(target, v, type))
        end
        push_stack(result ? Q_TRUE : Q_FALSE)
      else
        push_stack Core.check_match(target, pattern, type)
      end
    end

    def exec_jump(control_frame, insn)
      control_frame.pc = insn.arguments[0]
    end

    def exec_throw(control_frame, insn)
      throw_type = insn.arguments[0]
      raise GarnetThrow.new(throw_type, pop_stack, current_control_frame)
    end

    def exec_send_without_block(control_frame, insn)
      callinfo = insn.arguments[0]
      blockarg = get_block_arg(callinfo)
      blockarg = nil if blockarg == Q_NIL
      args = collect_args(callinfo)
      target = pop_stack
      method = find_method(target, callinfo.mid)
      ret = dispatch_method(target, method, args, blockarg&.block)
      push_stack(ret) unless ret.nil? || ret == Q_UNDEF
    end

    def exec_send(control_frame, insn)
      callinfo = insn.arguments[0]
      args = collect_args(callinfo)
      target = pop_stack
      method = find_method(target, callinfo.mid)
      block = IseqBlock.new(control_frame.environment, control_frame.self_value, callinfo.block_iseq)
      ret = dispatch_method(target, method, args, block)
      push_stack(ret) unless ret.nil? || ret == Q_UNDEF
    end

    def exec_invoke_block(control_frame, insn)
      callinfo = insn.arguments[0]
      args = collect_args(callinfo)
      block = caller_environment.block
      ret = execute_block(block, args, callinfo.argc)
      push_stack(ret) unless ret.nil? || ret == Q_UNDEF
    end

    def exec_invoke_super(control_frame, insn)
      callinfo = insn.arguments[0]
      block = get_block_for_super(control_frame, callinfo)
      args = collect_args(callinfo)
      target = control_frame.self_value
      method = find_super_method(target, control_frame.method_entry.method_object)
      ret = dispatch_method(target, method, args, block)
      push_stack(ret) unless ret.nil? || ret == Q_UNDEF
    end

    def collect_args(callinfo)
      args = pop_stack_multi(callinfo.argc)
      if callinfo.flags.include?(:splat)
        *pargs, splat = args
        args = [*pargs, *splat.array_value]
      end
      args
    end

    def get_block_arg(callinfo)
      return nil unless callinfo.flags.include?(:blockarg)

      block_value = pop_stack
      return block_value if block_value == Q_NIL

      Core.rb_funcall(block_value, :to_proc)
    end

    def get_block_for_super(control_frame, callinfo)
      blockarg = get_block_arg(callinfo)
      if blockarg.nil?
        control_frame.block
      elsif blockarg == Q_NIL
        nil
      else
        blockarg.block
      end
    end

    def exec_get_local(control_frame, insn)
      name, level = insn.arguments
      local_env = get_local_env(level)
      push_stack(local_env.locals[name] || Q_NIL)
    end

    def exec_set_local(control_frame, insn)
      value = pop_stack
      name, level = insn.arguments
      local_env = get_local_env(level)
      local_env.locals[name] = value
      push_stack(value)
    end

    def exec_get_instance_variable(control_frame, insn)
      id = insn.arguments[0]
      value = control_frame.self_value.ivar_get(id) || Q_NIL
      push_stack(value)
    end

    def exec_set_instance_variable(control_frame, insn)
      id = insn.arguments[0]
      value = pop_stack
      control_frame.self_value.ivar_set(id, value)
      push_stack(value)
    end

    def exec_get_class_variable(control_frame, insn)
      id = insn.arguments[0]
      value = cvar_base.cvar_get(id) || Q_NIL
      push_stack(value)
    end

    def exec_set_class_variable(control_frame, insn)
      id = insn.arguments[0]
      value = pop_stack
      cvar_base.cvar_set(id, value)
      push_stack(value)
    end

    def exec_get_block_param_proxy(control_frame, insn)
      level = insn.arguments[0]
      local_env = get_local_env(level)
      block_param = local_env.block
      if block_param
        push_stack(block_param.proc)
      else
        push_stack(Q_NIL)
      end
    end

    def exec_set_constant(control_frame, insn)
      const_base, value = pop_stack_multi(2)
      name = insn.arguments[0]
      const_base.rb_const_set(name, value)
    end

    def exec_get_constant(control_frame, insn)
      const_base = pop_stack
      name = insn.arguments[0]
      ret = const_base.rb_const_get(name)
      raise NameError, "Undefined Constant #{name}" if ret.nil?
      push_stack(ret)
    end

    def exec_set_global(control_frame, insn)
      name = insn.arguments[0]
      value = pop_stack

      if Core.virtual_variable?(name)
        Core.virtual_variable_set(name, value)
      else
        set_global(name, value)
      end

      push_stack(value)
    end

    def exec_get_global(control_frame, insn)
      name = insn.arguments[0]
      
      value = if Core.virtual_variable?(name)
                Core.virtual_variable_get(name)
              else
                get_global(name)
              end

      push_stack(value)
    end

    def exec_get_special(control_frame, insn)
      key, type = insn.arguments

      val = if type.nil?
              lep_svar_get(key)
            else
              backref = lep_svar_get(:backref)

              case type
              when :&
                Core.reg_last_match(backref)
              when :`
                Core.reg_match_pre(backref)
              when :"'"
                Core.reg_match_post(backref)
              when :+
                Core.reg_match_last(backref)
              when Integer
                Core.reg_nth_match(type, backref)
              else
                raise "unexpected back-ref: #{type}"
              end
            end

      push_stack(val)
    end

    def exec_setn(control_frame, insn)
      n = insn.arguments[0]
      control_frame.stack[-n - 1] = control_frame.stack.last
    end

    def exec_putn(control_frame, insn)
      n = insn.arguments[0]
      control_frame.stack << control_frame.stack[-n - 1]
    end

    def exec_dupn(control_frame, insn)
      n = insn.arguments[0]
      control_frame.stack[-n..-1].each do |x|
        control_frame.stack << x
      end
    end

    def exec_adjust_stack(control_frame, insn)
      n = insn.arguments[0]
      control_frame.stack.pop(n)
    end

    def push_stack(obj)
      current_control_frame.push_stack(obj)
    end

    def pop_stack
      control_frame = current_control_frame
      control_frame.stack.pop
    end

    def peek_stack
      control_frame = current_control_frame
      control_frame.stack.last
    end

    def pop_stack_multi(n)
      control_frame = current_control_frame
      control_frame.stack.pop(n)
    end

    def rb_call(recv, mid, *args)
      method = find_method(recv, mid)
      dispatch_method(recv, method, args)
    end

    def rb_call_with_block(recv, mid, block, *args)
      method = find_method(recv, mid)
      dispatch_method(recv, method, args, block)
    end

    def rb_check_funcall(recv, mid, *args)
      rb_check_funcall_default(recv, mid, Q_UNDEF, *args)
    end

    def rb_check_funcall_default(recv, mid, df, *args)
      return df unless rb_respond_to(recv, mid)
      rb_call(recv, mid, *args)
    end

    def call_super(*args)
      cfp = current_control_frame
      recv = cfp.self_value
      me = cfp.method_entry.method_object

      klass = me.defined_class
      klass = klass.super_class
      id = me.called_id
      me = find_method(recv, id, klass)

      dispatch_method(recv, me, args)
    end

    def rb_block_call(recv, mid, *args, &block)
      control_frame = current_control_frame
      method = find_method(recv, mid)
      block = BuiltInBlock.new(control_frame.environment, control_frame.self_value, &block)
      dispatch_method(recv, method, args, block)
    end

    def rb_respond_to(recv, mid)
      # TODO: actually call recv#respond_to?
      method = find_method_unchecked(recv, mid)
      method && !method.definition.is_a?(UndefinedMethodDef)
    end

    def rb_yield(*args)
      block = caller_environment.block
      execute_block(block, args, args.length)
    end

    def is_block_orphan?(block)
      @control_frames.reverse_each do |cfp|
        next if cfp.iseq.nil?
        cr = cfp.iseq.catch_table.find do |x|
          x.type == :break && x.iseq == block.iseq && (x.st..x.ed).include?(cfp.pc)
        end
        return false if cr
      end
      true
    end

    def undefined_method(mid, target)
      # method_missing
      Core.rb_raise(Core.eNoMethodError, "undefined method #{mid} for #{target}")
    end

    def find_method_unchecked(target, mid, klass = target.klass)
      raise "TRYING TO CALL #{mid} on NIL" if target.nil?
      raise "TRYING TO CALL #{mid} on NIL KLASS (#{target})" if klass.nil?
      Core.find_method(klass, mid)
    end

    def find_method(target, mid, klass = target.klass)
      method = find_method_unchecked(target, mid, klass)
      undefined_method(mid, target) if method.nil? || method.definition.is_a?(UndefinedMethodDef)
      method
    end

    def find_super_method(target, me)
      find_method(target, me.called_id, me.defined_class.super_class)
    end

    def dispatch_method(target, method, args, block=nil)
      case method.definition
      when BuiltInMethodDef
        env = Environment.new(target.klass, nil)
        env.method_entry = env
        env.method_object = method
        control_frame = ControlFrame.new(target, nil, env, block)
        push_control_frame(control_frame)
        begin
          ret = method.definition.block.call(target, *args)
        rescue GarnetThrow => e
          handle_rescue_throw(e)
        end
        pop_control_frame if current_control_frame == control_frame
        ret
      when ISeqMethodDef
        execute_method_iseq(target, method, args, block)
      when AliasMethodDef
        dispatch_method(target, method.definition.original_method, args, block)
      when UndefinedMethodDef
        raise "CANNOT CALL UNDEFINED METHOD"
      else
        raise "NOT IMPLEMENTED: #{method.class} dispatch"
      end
    end

    def execute_block(block, args, argc, block_block = nil)
      if !block.proc.is_lambda && args.length == 1 && argc == 1 && args.first.type?(Array) && block.arity > 1
        args = args[0].array_value
      end

      case block
      when BuiltInBlock
        if block_block
          block.block.call(*args) do |*blargs|
            execute_block(block_block, blargs, blargs.length)
          end
        else
          block.block.call(*args)
        end
      when IseqBlock
        execute_block_iseq(block, args, block_block)
      else
        raise "Unknown Block Type: #{block.class}"
      end
    end

    def find_or_create_class_by_id(id, type, flags, cbase, super_class)
      case type
      when :class
        define_class(id, flags, cbase, super_class)
      when :singleton_class
        Core.singleton_class_of(cbase)
      when :module
        define_module(id, flags, cbase)
      else
        raise "unknown defineclass type: #{type}"
      end
    end

    def check_if_namespace(klass)
      unless klass.flags.include?(:CLASS) || klass.flags.include?(:MODULE)
        raise TypeError, "#{klass} is not a class/module"
      end
    end

    def check_class_redefinition(id, flags, super_class, klass)
      unless klass.flags.include?(:CLASS)
        raise TypeError, "#{klass} is not a class"
      end

      if flags.include?(:has_superclass) && super_class != klass.super_class.real
        raise TypeError, "superclass mismatch for #{id}"
      end
    end

    def check_module_redefinition(id, flags, klass)
      unless klass.flags.include?(:MODULE)
        raise TypeError, "#{klass} is not a module"
      end
    end

    def define_class(id, flags, cbase, super_class)
      if flags.include?(:has_superclass) && !super_class.flags.include?(:CLASS) # TODO: also check it isn't a model
        raise TypeError, "superclass must be a Class (#{super_class.klass} given)"
      end

      check_if_namespace(cbase)
      klass = cbase.rb_const_get(id, false)
      if klass
        check_class_redefinition(id, flags, super_class, klass)
        return klass
      end

      return declare_class(id, flags, cbase, super_class)
    end

    def define_module(id, flags, cbase)
      check_if_namespace(cbase)
      klass = cbase.rb_const_get(id, false)
      if klass
        check_module_redefinition(id, flags, klass)
        return klass
      end

      return declare_module(id, flags, cbase)
    end

    def declare_class(id, flags, cbase, super_class)
      super_class = flags.include?(:has_superclass) ? super_class : Core.cObject
      klass = RClass.new_class(super_class)
      klass.name = id
      cbase.rb_const_set(id, klass)
      klass
    end

    def declare_module(id, flags, cbase)
      klass = RClass.new_module
      klass.name = id
      cbase.rb_const_set(id, klass)
      klass
    end

    def set_visibility(visi)
      scope_visi = previous_control_frame.environment.scope_visi
      scope_visi.method_visi = visi
      # TODO: module_func?
    end

    def get_local_env(level)
      control_frame = current_control_frame
      local_env = control_frame.environment
      level.times do
        local_env = local_env.previous
      end
      local_env
    end

    def set_global(name, value)
      @global_variables[name] = value
    end

    def get_global(name)
      @global_variables[name] || Q_NIL
    end

    def rtest(value)
      Core.rtest(value)
    end

    def lep_svar_get(key)
      @special_variables[key]
    end

    def cvar_base
      env = current_control_frame.environment

      while env.next_scope && (env.klass.nil? || env.klass.flags.include?(:SINGLETON))
        env = env.next_scope
      end

      puts 'WARNING: class variable access from top level' if env.next_scope.nil?

      klass = env.klass

      raise TypeError, 'no class variables available' if klass == Q_NIL

      klass
    end

    def do_raise(exception)
      exception.ivar_set(:backtrace, backtrace_to_ary([], 0, true))
      raise GarnetThrow.new(:raise, exception, current_control_frame, exception)
    end

    def handle_rescue_throw(e)
      cfp = current_control_frame
      unless cfp.iseq.nil?
        case e.throw_type
        when :raise
          unless cfp.iseq.nil?
            cr = cfp.iseq.catch_table.find do |x|
              (x.type == :rescue || x.type == :ensure) && (x.st..x.ed).include?(cfp.pc)
            end
            if cr
              cfp.pc = cr.cont
              execute_rescue_iseq(cr.iseq, e)
              return
            end
          end
        when :break
           unless cfp.iseq.nil?
            cr = cfp.iseq.catch_table.find do |x|
              next false unless (x.st..x.ed).include?(cfp.pc)
              (x.type == :ensure && x.iseq != e.cfp.iseq) || (x.type == :break && x.iseq == e.cfp.iseq)
            end
            if cr
              cfp.pc = cr.cont
              case cr.type
              when :break
                cfp.push_stack(e.value)
              when :ensure
                execute_rescue_iseq(cr.iseq, e, cfp)
              end
              return
            end
          end
        when :retry
          unless cfp.iseq.nil?
            cr = cfp.iseq.catch_table.find do |x|
              x.type == :retry && x.iseq == e.cfp.iseq && (x.st..x.ed).include?(cfp.pc)
            end
            if cr
              cfp.pc = cr.cont
              return
            end
          end
        when :continue
          pop_control_frame
          raise e.cfp.throw_data
        end
      end
      pop_control_frame
      raise e
    end

    def handle_uncaught_throw(e)
      case e.throw_type
      when :raise
        puts "Uncaught Exception: #{e.exc} #{Core.exc_message(e.exc)}"
        bt = e.exc.ivar_get(:backtrace)
        if !bt.nil? && bt.type?(Array)
          bt.array_value.each do |x|
            puts x.string_value
          end
        end
      else
        raise "Uncaught throw of type #{e.throw_type}"
      end
    end

    def get_errinfo
      current_control_frame.environment.errinfo
    end

    def backtrace
      @control_frames.filter(&:iseq).reverse.map do |cfp|
        insn = cfp.iseq.instructions[cfp.pc]
        "#{insn.file}:#{insn.line} in `#{cfp.iseq.name}'"
      end
    end

    def backtrace_to_ary(args, lev_default, to_str)
      level, vn = args
      bt = backtrace

      lev = n = 0

      case args.length
      when 0
        lev = lev_default
        n = bt.length - lev
      when 1
        if level.is_a?(Range)
          # TODO
        else
          lev = level.value
          raise ArgumentError, "negative level (#{lev})" if lev.negative?

          n = bt.length - lev
        end
      when 2
        lev = level.value
        n = vn.value
        raise ArgumentError, "negative level (#{lev})" if lev.negative?
        raise ArgumentError, "negative size (#{n})" if n.negative?
      end

      return RArray.from([]) if n.zero?

      if to_str
        RArray.from(bt[lev, n])
      else
        # TODO: backtrace_to_location_ary
      end
    end

    def make_binding(src_cfp)
      i = @control_frames.find_index(src_cfp)
      cfp = i.downto(0).each do |n|
        c = @control_frames[n]
        break c if c.iseq
      end

      RBinding.new(Core.cBinding, [], cfp)
    end

    def push_control_frame(cfp)
      if __vm_debug__?
        puts "#{$indent}BEGIN CONTROL FRAME: #{cfp} (#{caller.first})"
        $indent += "  "
      end
      @control_frames << cfp
    end

    def pop_control_frame
      $indent.slice!(0, 2) if __vm_debug__?
      @control_frames.pop.tap { |cfp|
        puts "#{$indent}END CONTROL FRAME: #{cfp} (#{caller(3, 1).first})" if __vm_debug__?
      }
    end

    def while_current_control_frame
      cfp = current_control_frame
      r = Q_NIL
      while current_control_frame == cfp
        r = yield
      end
      r
    end
  end
end
